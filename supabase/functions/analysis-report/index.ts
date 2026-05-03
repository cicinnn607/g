import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const allowedTimezones = new Set([
  'Asia/Shanghai',
  'Asia/Tokyo',
  'Asia/Hong_Kong',
  'Asia/Singapore',
  'UTC',
  'America/New_York',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'Europe/London',
  'Europe/Paris',
]);

type DailyStat = {
  record_date?: string;
  reading_count?: number | string | null;
  avg_glucose?: number | string | null;
  cv?: number | string | null;
  in_range_ratio?: number | string | null;
};

type WeeklySummary = {
  reading_count?: number | string | null;
  valid_day_count?: number | string | null;
  avg_glucose?: number | string | null;
  cv?: number | string | null;
  in_range_ratio?: number | string | null;
  range_glucose?: number | string | null;
};

type FoodSignal = {
  food_name?: string | null;
  signal_level?: string | null;
  avg_excursion?: number | string | null;
  meal_count?: number | string | null;
  reason?: string | null;
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
    const authHeader = req.headers.get('Authorization') ?? '';
    if (!authHeader.toLowerCase().startsWith('bearer ')) {
      return json({ error: 'Unauthorized' }, 401);
    }

    const client = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await client.auth.getUser();
    if (userError || !userData.user) {
      return json({ error: 'Unauthorized' }, 401);
    }

    const body = await req.json().catch(() => ({}));
    const range = normalizeDateRange(body.start_date, body.end_date);
    const timezone = normalizeTimezone(body.timezone);
    const rpcParams = {
      start_date: range.startDate,
      end_date: range.endDate,
      timezone_param: timezone,
    };

    const [dailyStats, weeklyRows, foodSignals, energyCorrelation] = await Promise.all([
      rpc<DailyStat>(client, 'get_daily_glucose_stats', rpcParams),
      rpc<WeeklySummary>(client, 'get_weekly_glucose_summary', rpcParams),
      rpc<FoodSignal>(client, 'get_food_impact_stats', rpcParams),
      rpc<Record<string, unknown>>(client, 'get_energy_correlation', rpcParams),
    ]);

    const weeklySummary = weeklyRows[0] ?? {};
    const dataQuality = buildDataQuality(weeklySummary, foodSignals);
    const templateSummary = buildTemplateSummary(weeklySummary, foodSignals, dataQuality);
    const summaryText = await buildLlmSummary({
      weekly_summary_metrics: weeklySummary,
      food_signals: foodSignals.slice(0, 3),
      energy_correlation: energyCorrelation,
      data_quality: dataQuality,
      fallback: templateSummary,
    });

    return json({
      daily_stats: dailyStats,
      weekly_summary_metrics: weeklySummary,
      food_signals: foodSignals,
      energy_correlation: energyCorrelation,
      data_quality: dataQuality,
      summary_text: summaryText,
    });
  } catch (error) {
    console.error(error);
    return json({ error: error instanceof Error ? error.message : 'Unknown error' }, 500);
  }
});

async function rpc<T>(
  client: ReturnType<typeof createClient>,
  name: string,
  params: Record<string, unknown>,
): Promise<T[]> {
  const { data, error } = await client.rpc(name, params);
  if (error) throw error;
  return Array.isArray(data) ? data as T[] : [];
}

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

function normalizeDateRange(startValue: unknown, endValue: unknown) {
  const today = new Date();
  const defaultEnd = toDateOnly(today);
  const defaultStart = toDateOnly(new Date(today.getTime() - 6 * 24 * 60 * 60 * 1000));
  const startDate = isDateOnly(startValue) ? `${startValue}` : defaultStart;
  const endDate = isDateOnly(endValue) ? `${endValue}` : defaultEnd;
  if (startDate > endDate) {
    return { startDate: endDate, endDate: startDate };
  }
  return { startDate, endDate };
}

function isDateOnly(value: unknown) {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value);
}

function toDateOnly(value: Date) {
  return value.toISOString().slice(0, 10);
}

function normalizeTimezone(value: unknown) {
  const timezone = typeof value === 'string' ? value.trim() : '';
  return allowedTimezones.has(timezone) ? timezone : 'Asia/Shanghai';
}

function toNumber(value: unknown) {
  if (value === null || value === undefined || value === '') return null;
  const parsed = Number.parseFloat(`${value}`);
  return Number.isFinite(parsed) ? parsed : null;
}

function buildDataQuality(weekly: WeeklySummary, foods: FoodSignal[]) {
  const readingCount = toNumber(weekly.reading_count) ?? 0;
  const validDayCount = toNumber(weekly.valid_day_count) ?? 0;
  const hasEnoughGlucose = readingCount >= 4 && validDayCount >= 2;
  const hasEnoughFoodSignals = foods.some((food) => (toNumber(food.meal_count) ?? 0) >= 2);
  const messages: string[] = [];
  if (!hasEnoughGlucose) {
    messages.push('本周血糖记录偏少，波动指标仅供参考');
  }
  if (!hasEnoughFoodSignals) {
    messages.push('餐后配对样本偏少，红绿灯食物会先保持保守');
  }
  if (messages.length === 0) {
    messages.push('本周记录可用于观察趋势');
  }
  return {
    reading_count: readingCount,
    valid_day_count: validDayCount,
    has_enough_glucose: hasEnoughGlucose,
    has_enough_food_signals: hasEnoughFoodSignals,
    messages,
  };
}

function buildTemplateSummary(
  weekly: WeeklySummary,
  foods: FoodSignal[],
  dataQuality: { messages: string[] },
) {
  const avg = toNumber(weekly.avg_glucose);
  const cv = toNumber(weekly.cv);
  const inRange = toNumber(weekly.in_range_ratio);
  const riskyFood = foods.find((food) => food.signal_level === 'red');
  if (avg === null) {
    return '本周血糖记录还不够，先固定记录空腹或餐后血糖，再结合饮食和状态看趋势。';
  }
  const parts = [
    `本周平均血糖约 ${avg.toFixed(1)} mmol/L`,
    cv === null ? dataQuality.messages[0] : `CV ${cv.toFixed(1)}%`,
    inRange === null ? '' : `目标范围内记录占比 ${(inRange * 100).toFixed(0)}%`,
  ].filter(Boolean);
  if (riskyFood?.food_name) {
    parts.push(`${riskyFood.food_name} 的餐后升幅偏高，下一次先减量或搭配蛋白质和蔬菜`);
  }
  return `${parts.join('，')}。仅供生活习惯参考。`;
}

async function buildLlmSummary(payload: {
  weekly_summary_metrics: WeeklySummary;
  food_signals: FoodSignal[];
  energy_correlation: Record<string, unknown>[];
  data_quality: Record<string, unknown>;
  fallback: string;
}) {
  const apiKey = Deno.env.get('ANALYSIS_LLM_API_KEY');
  const apiUrl = Deno.env.get('ANALYSIS_LLM_API_URL');
  const model = Deno.env.get('ANALYSIS_LLM_MODEL') ?? 'deepseek-chat';
  if (!apiKey || !apiUrl) return payload.fallback;

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 3500);
  try {
    const response = await fetch(apiUrl, {
      method: 'POST',
      signal: controller.signal,
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        messages: [
          {
            role: 'system',
            content:
              '你是血糖健康管理助手，只能基于已给出的聚合指标写生活习惯建议，不做诊断，不重新计算数值。输出 50-80 字中文。',
          },
          {
            role: 'user',
            content: JSON.stringify({
              weekly_summary_metrics: payload.weekly_summary_metrics,
              food_signals: payload.food_signals,
              energy_correlation: payload.energy_correlation,
              data_quality: payload.data_quality,
            }),
          },
        ],
        temperature: 0.2,
      }),
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) return payload.fallback;
    const content = data?.choices?.[0]?.message?.content;
    const summary = typeof content === 'string' ? content.trim() : '';
    if (!summary) return payload.fallback;
    return summary.length > 120 ? `${summary.slice(0, 120)}...` : summary;
  } catch (error) {
    console.error('analysis summary fallback:', error);
    return payload.fallback;
  } finally {
    clearTimeout(timeoutId);
  }
}
