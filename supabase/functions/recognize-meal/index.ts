import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

type BaiduDish = {
  name?: string;
  calorie?: string | number;
  probability?: string | number;
};

type CatalogFood = {
  id?: string;
  name?: string;
  aliases?: string[];
  calories_per_100g?: number | string;
  carbs_per_100g?: number | string | null;
  protein_per_100g?: number | string | null;
  fat_per_100g?: number | string | null;
  gi_value?: number | string | null;
  serving_options?: Record<string, unknown> | null;
  category?: string | null;
  source?: string | null;
  is_ai_generated?: boolean | null;
  confidence?: number | string | null;
  similarity_score?: number | string | null;
};

type RecognizedItem = {
  food_name_raw: string;
  food_name_confirmed?: string;
  calories_raw: number;
  confidence: number;
  carbs_per_100g?: number | null;
  protein_per_100g?: number | null;
  fat_per_100g?: number | null;
  gi_value?: number | null;
  serving_options?: Record<string, number>;
  source?: string | null;
  is_ai_generated?: boolean;
  catalog_id?: string;
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    if (req.method !== 'POST') {
      return json({ error: 'Method not allowed' }, 405);
    }

    const supabaseUrl = mustGetEnv('SUPABASE_URL');
    const anonKey = mustGetEnv('SUPABASE_ANON_KEY');
    const serviceRoleKey = mustGetEnv('SUPABASE_SERVICE_ROLE_KEY');
    const baiduApiKey = mustGetEnv('BAIDU_API_KEY');
    const baiduSecretKey = mustGetEnv('BAIDU_SECRET_KEY');

    const authHeader = req.headers.get('Authorization') ?? '';
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) {
      return json({ error: 'Unauthorized' }, 401);
    }

    const body = await req.json().catch(() => ({}));
    const storagePath = `${body.storage_path ?? ''}`;
    if (!storagePath || !storagePath.startsWith(`${userData.user.id}/`)) {
      return json({ error: 'Invalid storage_path' }, 400);
    }

    const admin = createClient(supabaseUrl, serviceRoleKey);
    const { data: file, error: downloadError } = await admin.storage
      .from('meal-images')
      .download(storagePath);
    if (downloadError || !file) {
      return json({ error: 'Image not found' }, 404);
    }

    const bytes = new Uint8Array(await file.arrayBuffer());
    const imageBase64 = bytesToBase64(bytes);
    const accessToken = await getBaiduAccessToken(baiduApiKey, baiduSecretKey);
    const dishes = await recognizeDish(accessToken, imageBase64);
    const topDishes = dishes
      .filter((dish) => `${dish.name ?? ''}`.trim().length > 0)
      .slice(0, 5);

    const items: RecognizedItem[] = [];
    for (const dish of topDishes) {
      const rawName = dish.name?.trim() || '未识别食物';
      const baiduCalories = parseCalories(dish.calorie);
      const baiduConfidence = parseProbability(dish.probability);
      const localFood = await findCatalogFood(admin, rawName);

      if (localFood) {
        items.push(toRecognizedItem(rawName, baiduConfidence, baiduCalories, localFood));
        continue;
      }

      items.push({
        food_name_raw: rawName,
        calories_raw: baiduCalories,
        confidence: baiduConfidence,
        is_ai_generated: false,
      });
    }

    if (!items.some((item) => item.catalog_id) && topDishes.length > 0) {
      const topName = topDishes[0].name?.trim() || '';
      if (topName) {
        const estimatedFood = await estimateAndInsertFood(admin, topName).catch((error) => {
          console.error('Zhipu fallback failed:', error);
          return null;
        });
        if (estimatedFood) {
          items.unshift(
            toRecognizedItem(
              topName,
              parseProbability(topDishes[0].probability) || 0.85,
              parseCalories(topDishes[0].calorie),
              estimatedFood,
            ),
          );
        }
      }
    }

    return json({ items });
  } catch (error) {
    console.error(error);
    return json({ error: error instanceof Error ? error.message : 'Unknown error' }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function mustGetEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing env: ${name}`);
  return value;
}

async function getBaiduAccessToken(apiKey: string, secretKey: string) {
  const url = new URL('https://aip.baidubce.com/oauth/2.0/token');
  url.searchParams.set('grant_type', 'client_credentials');
  url.searchParams.set('client_id', apiKey);
  url.searchParams.set('client_secret', secretKey);

  const response = await fetch(url);
  const data = await response.json();
  if (!response.ok || !data.access_token) {
    throw new Error(data.error_description ?? 'Baidu token request failed');
  }
  return `${data.access_token}`;
}

async function recognizeDish(accessToken: string, imageBase64: string): Promise<BaiduDish[]> {
  const url = new URL('https://aip.baidubce.com/rest/2.0/image-classify/v2/dish');
  url.searchParams.set('access_token', accessToken);

  const form = new URLSearchParams();
  form.set('image', imageBase64);
  form.set('top_num', '5');
  form.set('filter_threshold', '0.6');
  form.set('baike_num', '0');

  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: form,
  });
  const data = await response.json();
  if (!response.ok || data.error_code) {
    throw new Error(data.error_msg ?? 'Baidu dish recognition failed');
  }
  return Array.isArray(data.result) ? data.result : [];
}

function parseCalories(value: unknown) {
  const parsed = Number.parseFloat(`${value ?? 0}`);
  return Number.isFinite(parsed) ? parsed : 0;
}

function parseProbability(value: unknown) {
  const parsed = Number.parseFloat(`${value ?? 0}`);
  if (!Number.isFinite(parsed)) return 0;
  return parsed > 1 ? parsed / 100 : parsed;
}

function parseOptionalNumber(value: unknown) {
  if (value === null || value === undefined || value === '') return null;
  const parsed = Number.parseFloat(`${value}`);
  return Number.isFinite(parsed) ? parsed : null;
}

function clampNumber(value: unknown, min: number, max: number) {
  const parsed = parseOptionalNumber(value);
  if (parsed === null) return null;
  return Math.min(max, Math.max(min, parsed));
}

function normalizeServingOptions(value: unknown): Record<string, number> {
  const servingOptions: Record<string, number> = {};
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return servingOptions;
  }

  for (const [label, grams] of Object.entries(value as Record<string, unknown>)) {
    const parsed = parseOptionalNumber(grams);
    if (label.trim() && parsed !== null && parsed > 0 && parsed <= 2000) {
      servingOptions[label.trim()] = Math.round(parsed);
    }
  }
  return servingOptions;
}

function normalizeAliases(value: unknown, name: string): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => `${item}`.trim())
    .filter((item) => item.length > 0 && item !== name)
    .slice(0, 8);
}

async function findCatalogFood(admin: ReturnType<typeof createClient>, foodName: string) {
  const exact = await admin
    .from('food_calorie_catalog')
    .select('*')
    .eq('name', foodName)
    .maybeSingle();
  if (exact.data) return exact.data as CatalogFood;

  const fuzzy = await admin.rpc('search_food_calorie_catalog', {
    query_text: foodName,
    result_limit: 1,
  });
  if (Array.isArray(fuzzy.data) && fuzzy.data.length > 0) {
    return fuzzy.data[0] as CatalogFood;
  }
  return null;
}

function toRecognizedItem(
  rawName: string,
  baiduConfidence: number,
  baiduCalories: number,
  food: CatalogFood,
): RecognizedItem {
  const calories = parseOptionalNumber(food.calories_per_100g) ?? baiduCalories;
  const catalogConfidence = parseOptionalNumber(food.confidence);
  return {
    food_name_raw: rawName,
    food_name_confirmed: food.name || rawName,
    calories_raw: calories,
    confidence: baiduConfidence || catalogConfidence || 0,
    carbs_per_100g: parseOptionalNumber(food.carbs_per_100g),
    protein_per_100g: parseOptionalNumber(food.protein_per_100g),
    fat_per_100g: parseOptionalNumber(food.fat_per_100g),
    gi_value: parseOptionalNumber(food.gi_value),
    serving_options: normalizeServingOptions(food.serving_options),
    source: food.source ?? null,
    is_ai_generated: food.is_ai_generated === true,
    catalog_id: food.id,
  };
}

async function estimateAndInsertFood(admin: ReturnType<typeof createClient>, foodName: string) {
  const apiKey = Deno.env.get('ZHIPU_API_KEY');
  if (!apiKey) return null;

  const estimated = await callZhipuLLM(apiKey, foodName);
  const safeData = sanitizeEstimatedFood(estimated, foodName);
  if (!safeData) return null;

  const insert = await admin
    .from('food_calorie_catalog')
    .insert(safeData)
    .select()
    .single();

  if (!insert.error && insert.data) {
    return insert.data as CatalogFood;
  }

  const conflict = `${insert.error?.code ?? ''} ${insert.error?.message ?? ''}`.toLowerCase();
  if (conflict.includes('23505') || conflict.includes('duplicate')) {
    return await findCatalogFood(admin, safeData.name);
  }

  throw insert.error;
}

async function callZhipuLLM(apiKey: string, foodName: string) {
  const systemPrompt = `你是一个严谨的营养学数据库接口。
必须返回符合以下结构的 JSON 对象。
注意：serving_options 必须是键值对对象格式，例如 {"1碗": 150, "半碗": 75}。
JSON 结构示例：
{"name":"菜名","aliases":["别名1"],"calories_per_100g":数字,"carbs_per_100g":数字,"protein_per_100g":数字,"fat_per_100g":数字,"gi_value":数字,"serving_options":{"量词":克数数字}}`;

  const response = await fetch('https://open.bigmodel.cn/api/paas/v4/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: 'glm-4.7-flash',
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: `查询【${foodName}】的营养成分及常见视觉份量。` },
      ],
      response_format: { type: 'json_object' },
      temperature: 0.1,
    }),
  });

  const data = await response.json();
  if (!response.ok) {
    throw new Error(data.error?.message ?? data.message ?? 'Zhipu request failed');
  }

  const content = data.choices?.[0]?.message?.content;
  if (!content) throw new Error('Zhipu returned empty content');
  return JSON.parse(content);
}

function sanitizeEstimatedFood(value: unknown, fallbackName: string): CatalogFood | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const row = value as Record<string, unknown>;
  const name = `${row.name ?? fallbackName}`.trim() || fallbackName;
  const calories = clampNumber(row.calories_per_100g, 0, 1200);
  if (calories === null) return null;

  const carbs = clampNumber(row.carbs_per_100g, 0, 100);
  const protein = clampNumber(row.protein_per_100g, 0, 100);
  const fat = clampNumber(row.fat_per_100g, 0, 100);
  const gi = clampNumber(row.gi_value, 0, 100);
  const servingOptions = normalizeServingOptions(row.serving_options);

  return {
    name,
    aliases: normalizeAliases(row.aliases, name),
    calories_per_100g: calories,
    carbs_per_100g: carbs,
    protein_per_100g: protein,
    fat_per_100g: fat,
    gi_value: gi,
    serving_options: Object.keys(servingOptions).length > 0 ? servingOptions : { '100克': 100 },
    source: 'zhipu',
    is_ai_generated: true,
    confidence: 0.85,
  };
}

function bytesToBase64(bytes: Uint8Array) {
  let binary = '';
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}
