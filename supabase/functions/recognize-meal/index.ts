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

    return json({
      items: dishes.map((dish) => ({
        food_name_raw: dish.name?.trim() || '未识别食物',
        calories_raw: parseCalories(dish.calorie),
        confidence: parseProbability(dish.probability),
      })),
    });
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

function bytesToBase64(bytes: Uint8Array) {
  let binary = '';
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}
