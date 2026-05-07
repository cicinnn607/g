import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

type EstimatedFood = {
  name: string;
  aliases: string[];
  calories_per_100g: number;
  carbs_per_100g?: number | null;
  protein_per_100g?: number | null;
  fat_per_100g?: number | null;
  gi_value?: number | null;
  serving_options: Record<string, number>;
  source: string;
  is_ai_generated: boolean;
  confidence: number;
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
    const zhipuApiKey = mustGetEnv('ZHIPU_API_KEY');

    const authHeader = req.headers.get('Authorization') ?? '';
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) {
      return json({ error: 'Unauthorized' }, 401);
    }

    const body = await req.json().catch(() => ({}));
    const foodName = `${body.food_name ?? ''}`.trim();
    if (!foodName) {
      return json({ error: 'Missing food_name' }, 400);
    }
    if (foodName.length > 40) {
      return json({ error: 'food_name too long' }, 400);
    }

    const preferredModel =
      Deno.env.get('ZHIPU_FOOD_MODEL') ?? Deno.env.get('ZHIPU_MODEL') ?? '';
    const estimated = await callZhipuLLM(zhipuApiKey, foodName, preferredModel);
    const item = sanitizeEstimatedFood(estimated, foodName);
    if (!item) {
      return json({ error: 'Unable to estimate food' }, 422);
    }

    return json({ item });
  } catch (error) {
    console.error(error);
    if (isRetryableZhipuError(error)) {
      return json(
        { error: 'AI 服务当前比较忙，请稍后重试。', retryable: true },
        503,
      );
    }
    return json({ error: errorMessage(error) }, 500);
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

class ZhipuRequestError extends Error {
  constructor(message: string, readonly status: number, readonly model: string) {
    super(message);
    this.name = 'ZhipuRequestError';
  }
}

async function callZhipuLLM(
  apiKey: string,
  foodName: string,
  preferredModel: string,
) {
  const systemPrompt = `你是一个严谨的营养学数据库接口。
必须只返回 JSON 对象，不能返回 Markdown。
注意：serving_options 必须是键值对对象格式，例如 {"1碗": 150, "半碗": 75, "1勺": 15}。
JSON 结构示例：
{"name":"菜名","aliases":["别名1"],"calories_per_100g":数字,"carbs_per_100g":数字,"protein_per_100g":数字,"fat_per_100g":数字,"gi_value":数字,"serving_options":{"量词":克数数字}}`;

  const models = unique([
    preferredModel,
    'glm-4-flash-250414',
    'glm-4.7-flash',
  ]);
  let lastError: unknown = null;
  for (const model of models) {
    try {
      return await requestZhipuModel(apiKey, model, systemPrompt, foodName);
    } catch (error) {
      lastError = error;
      if (!isRetryableZhipuError(error)) throw error;
      console.warn(`Zhipu model ${model} failed, trying fallback: ${errorMessage(error)}`);
    }
  }

  throw lastError ?? new Error('Zhipu request failed');
}

async function requestZhipuModel(
  apiKey: string,
  model: string,
  systemPrompt: string,
  foodName: string,
) {
  const body: Record<string, unknown> = {
    model,
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: `估算【${foodName}】每100g热量和常见视觉份量。` },
    ],
    response_format: { type: 'json_object' },
    max_tokens: 512,
    temperature: 0.1,
  };
  if (model.includes('4.5') || model.includes('4.7')) {
    body.thinking = { type: 'disabled' };
  }

  const response = await fetch('https://open.bigmodel.cn/api/paas/v4/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify(body),
  });

  const text = await response.text();
  const data = parseJson(text);
  if (!response.ok) {
    const message =
      data?.error?.message ?? data?.message ?? text ?? 'Zhipu request failed';
    throw new ZhipuRequestError(message, response.status, model);
  }

  const content = data.choices?.[0]?.message?.content;
  if (!content) throw new Error('Zhipu returned empty content');
  return typeof content === 'string' ? JSON.parse(content) : content;
}

function unique(values: string[]) {
  return [...new Set(values.map((value) => value.trim()).filter(Boolean))];
}

function parseJson(text: string): any {
  try {
    return JSON.parse(text);
  } catch (_) {
    return null;
  }
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : 'Unknown error';
}

function isRetryableZhipuError(error: unknown) {
  const message = errorMessage(error).toLowerCase();
  const status = error instanceof ZhipuRequestError ? error.status : 0;
  return (
    status === 429 ||
    status >= 500 ||
    message.includes('访问量过大') ||
    message.includes('当前比较忙') ||
    message.includes('busy') ||
    message.includes('overload') ||
    message.includes('rate limit') ||
    message.includes('too many requests') ||
    message.includes('timeout')
  );
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

function sanitizeEstimatedFood(value: unknown, fallbackName: string): EstimatedFood | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const row = value as Record<string, unknown>;
  const name = `${row.name ?? fallbackName}`.trim() || fallbackName;
  const calories = clampNumber(row.calories_per_100g, 1, 1200);
  if (calories === null) return null;

  const servingOptions = normalizeServingOptions(row.serving_options);
  return {
    name,
    aliases: normalizeAliases(row.aliases, name),
    calories_per_100g: Math.round(calories),
    carbs_per_100g: clampNumber(row.carbs_per_100g, 0, 100),
    protein_per_100g: clampNumber(row.protein_per_100g, 0, 100),
    fat_per_100g: clampNumber(row.fat_per_100g, 0, 100),
    gi_value: clampNumber(row.gi_value, 0, 100),
    serving_options: Object.keys(servingOptions).length > 0 ? servingOptions : { '100克': 100 },
    source: 'zhipu',
    is_ai_generated: true,
    confidence: 0.85,
  };
}
