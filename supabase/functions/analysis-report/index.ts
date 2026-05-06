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

type Row = Record<string, unknown>;

type GlucoseRow = {
  id: string;
  user_id: string;
  record_time: string;
  time_period?: string | null;
  value: number | string;
  unit?: string | null;
  source?: string | null;
};

type MealRow = {
  id: string;
  user_id: string;
  meal_time: string;
  meal_type?: string | null;
};

type MealItemRow = {
  meal_id: string;
  food_name_confirmed?: string | null;
};

type StatusRow = {
  related_meal_id?: string | null;
  related_exercise_id?: string | null;
  record_time: string;
  status_level?: string | null;
};

type ExerciseRow = {
  id: string;
  exercise_time: string;
  duration?: number | string | null;
  calories_burned?: number | string | null;
  mets_snapshot?: number | string | null;
  exercise_catalog?: { name?: string | null } | null;
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

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser();
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

    const report = await buildReportFromRpc(
      userClient,
      rpcParams,
      userData.user.id,
      range,
      timezone,
    ).catch(async (error) => {
      console.error('analysis RPC fallback:', error);
      const serviceRoleKey = mustGetEnv('SUPABASE_SERVICE_ROLE_KEY');
      const admin = createClient(supabaseUrl, serviceRoleKey);
      return await buildReportInFunction(admin, userData.user.id, range, timezone);
    });

    const templateSummary = buildTemplateSummary(
      report.weekly_summary_metrics,
      report.food_signals,
      report.energy_correlation,
    );

    if (body.mode === 'cards') {
      const serviceRoleKey = mustGetEnv('SUPABASE_SERVICE_ROLE_KEY');
      const admin = createClient(supabaseUrl, serviceRoleKey);
      const evidence = await buildEvidencePayload(
        admin,
        userData.user.id,
        range,
        timezone,
        report,
      );
      const cardsResult = await buildAnalysisCards(evidence);
      return json({
        analysis_cards: cardsResult.cards,
        analysis_cards_source: cardsResult.source,
        evidence_cache_key: evidence.cache_key,
        ...(cardsResult.error ? { analysis_cards_error: cardsResult.error } : {}),
      });
    }

    const summaryResult = body.include_summary_llm === true
      ? await buildLlmSummary({
        weekly_summary_metrics: report.weekly_summary_metrics,
        food_signals: report.food_signals.slice(0, 3),
        energy_correlation: report.energy_correlation,
        data_quality: report.data_quality,
        fallback: templateSummary,
      })
      : { text: templateSummary, source: 'template' };

    return json({
      ...report,
      summary_text: summaryResult.text,
      summary_source: summaryResult.source,
      ...(summaryResult.error ? { summary_error: summaryResult.error } : {}),
    });
  } catch (error) {
    console.error(error);
    return json({ error: error instanceof Error ? error.message : 'Unknown error' }, 500);
  }
});

async function buildReportFromRpc(
  client: ReturnType<typeof createClient>,
  rpcParams: Record<string, unknown>,
  userId: string,
  range: { startDate: string; endDate: string },
  timezone: string,
) {
  const [dailyStats, weeklyRows, foodSignals, energyCorrelation] = await Promise.all([
    rpc<Row>(client, 'get_daily_glucose_stats', rpcParams),
    rpc<Row>(client, 'get_weekly_glucose_summary', rpcParams),
    rpc<Row>(client, 'get_food_impact_stats', rpcParams),
    rpc<Row>(client, 'get_energy_correlation', rpcParams),
  ]);
  const latestGlucose = await getLatestGlucoseInRange(client, userId, range, timezone);
  const weeklySummary = { ...(weeklyRows[0] ?? {}), latest_glucose: latestGlucose };
  const dataQuality = buildDataQuality(weeklySummary, foodSignals);
  return {
    daily_stats: dailyStats,
    weekly_summary_metrics: weeklySummary,
    food_signals: foodSignals,
    energy_correlation: energyCorrelation,
    data_quality: dataQuality,
  };
}

async function buildReportInFunction(
  admin: ReturnType<typeof createClient>,
  userId: string,
  range: { startDate: string; endDate: string },
  timezone: string,
) {
  const fromIso = new Date(`${range.startDate}T00:00:00.000Z`);
  fromIso.setUTCDate(fromIso.getUTCDate() - 1);
  const toIso = new Date(`${range.endDate}T23:59:59.999Z`);
  toIso.setUTCDate(toIso.getUTCDate() + 1);

  const [glucoseRows, mealRows, statusRows] = await Promise.all([
    selectRows<GlucoseRow>(
      admin
        .from('blood_glucose_logs')
        .select('id,user_id,record_time,time_period,value,unit,source')
        .eq('user_id', userId)
        .gte('record_time', fromIso.toISOString())
        .lte('record_time', toIso.toISOString())
        .order('record_time', { ascending: true }),
    ),
    selectRows<MealRow>(
      admin
        .from('meals')
        .select('id,user_id,meal_time,meal_type')
        .eq('user_id', userId)
        .gte('meal_time', fromIso.toISOString())
        .lte('meal_time', toIso.toISOString())
        .order('meal_time', { ascending: true }),
    ),
    selectRows<StatusRow>(
      admin
        .from('wellness_status')
        .select('record_time,status_level')
        .eq('user_id', userId)
        .gte('record_time', fromIso.toISOString())
        .lte('record_time', toIso.toISOString())
        .order('record_time', { ascending: true }),
    ),
  ]);

  const mealIds = mealRows.map((meal) => meal.id);
  const mealItems = mealIds.length === 0
    ? []
    : await selectRows<MealItemRow>(
      admin
        .from('meal_items')
        .select('meal_id,food_name_confirmed')
        .in('meal_id', mealIds),
    );

  const normalizedGlucose = glucoseRows
    .map((row) => ({
      ...row,
      glucose_mmol: normalizeGlucose(row.value, row.unit),
      local_date: localDate(row.record_time, timezone),
    }))
    .filter((row) => row.glucose_mmol !== null);
  const glucoseInRange = normalizedGlucose.filter((row) =>
    row.local_date >= range.startDate && row.local_date <= range.endDate
  );
  const mealsInRange = mealRows
    .map((meal) => ({ ...meal, local_date: localDate(meal.meal_time, timezone) }))
    .filter((meal) => meal.local_date >= range.startDate && meal.local_date <= range.endDate);

  const dailyStats = buildDailyStats(glucoseInRange);
  const weeklySummary = buildWeeklySummary(glucoseInRange);
  const mealResponses = buildMealResponses(mealsInRange, normalizedGlucose);
  const foodSignals = buildFoodSignals(mealResponses, mealItems);
  const energyCorrelation = buildEnergyCorrelation(dailyStats, statusRows, timezone, range);
  const dataQuality = buildDataQuality(weeklySummary, foodSignals);

  return {
    daily_stats: dailyStats,
    weekly_summary_metrics: weeklySummary,
    food_signals: foodSignals,
    energy_correlation: energyCorrelation,
    data_quality: dataQuality,
  };
}

async function rpc<T>(
  client: ReturnType<typeof createClient>,
  name: string,
  params: Record<string, unknown>,
): Promise<T[]> {
  const { data, error } = await client.rpc(name, params);
  if (error) throw error;
  return Array.isArray(data) ? data as T[] : [];
}

async function selectRows<T>(
  query: PromiseLike<{ data: unknown; error: unknown }>,
): Promise<T[]> {
  const { data, error } = await query;
  if (error) throw error;
  return Array.isArray(data) ? data as T[] : [];
}

async function getLatestGlucoseInRange(
  client: ReturnType<typeof createClient>,
  userId: string,
  range: { startDate: string; endDate: string },
  timezone: string,
) {
  const fromIso = new Date(`${range.startDate}T00:00:00.000Z`);
  fromIso.setUTCDate(fromIso.getUTCDate() - 1);
  const toIso = new Date(`${range.endDate}T23:59:59.999Z`);
  toIso.setUTCDate(toIso.getUTCDate() + 1);
  const rows = await selectRows<GlucoseRow>(
    client
      .from('blood_glucose_logs')
      .select('id,user_id,record_time,time_period,value,unit,source')
      .eq('user_id', userId)
      .gte('record_time', fromIso.toISOString())
      .lte('record_time', toIso.toISOString())
      .order('record_time', { ascending: false })
      .limit(20),
  );
  for (const row of rows) {
    const date = localDate(row.record_time, timezone);
    if (date < range.startDate || date > range.endDate) continue;
    const value = normalizeGlucose(row.value, row.unit);
    if (value !== null) return round(value);
  }
  return null;
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

function localDate(isoValue: string, timezone: string) {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
  return formatter.format(new Date(isoValue));
}

function toNumber(value: unknown) {
  if (value === null || value === undefined || value === '') return null;
  const parsed = Number.parseFloat(`${value}`);
  return Number.isFinite(parsed) ? parsed : null;
}

function round(value: number | null, digits = 2) {
  if (value === null || !Number.isFinite(value)) return null;
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function normalizeGlucose(value: unknown, unit: unknown) {
  const parsed = toNumber(value);
  const unitText = `${unit ?? 'mmol/L'}`;
  if (parsed === null) return null;
  if (unitText === 'mg/dL') {
    if (parsed < 10 || parsed > 600) return null;
    return parsed / 18;
  }
  if (parsed < 0.6 || parsed > 33.3) return null;
  return parsed;
}

function average(values: number[]) {
  if (values.length === 0) return null;
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function stddevSample(values: number[]) {
  if (values.length < 2) return null;
  const avg = average(values)!;
  const variance = values.reduce((sum, value) => sum + (value - avg) ** 2, 0) / (values.length - 1);
  return Math.sqrt(variance);
}

function buildDailyStats(glucoseRows: Array<GlucoseRow & { glucose_mmol: number | null; local_date: string }>) {
  const byDate = new Map<string, number[]>();
  for (const row of glucoseRows) {
    if (row.glucose_mmol === null) continue;
    const values = byDate.get(row.local_date) ?? [];
    values.push(row.glucose_mmol);
    byDate.set(row.local_date, values);
  }
  return [...byDate.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([date, values]) => {
    const avg = average(values);
    const sd = stddevSample(values);
    const min = Math.min(...values);
    const max = Math.max(...values);
    return {
      record_date: date,
      reading_count: values.length,
      avg_glucose: round(avg),
      std_glucose: round(sd),
      cv: avg !== null && sd !== null && avg > 0 ? round(sd / avg * 100, 1) : null,
      in_range_ratio: round(values.filter((value) => value >= 3.9 && value <= 10.0).length / values.length, 3),
      range_glucose: round(max - min),
      min_glucose: round(min),
      max_glucose: round(max),
    };
  });
}

function buildWeeklySummary(glucoseRows: Array<GlucoseRow & { glucose_mmol: number | null; local_date: string }>) {
  const values = glucoseRows.map((row) => row.glucose_mmol).filter((value): value is number => value !== null);
  const avg = average(values);
  const sd = stddevSample(values);
  const dates = new Set(glucoseRows.map((row) => row.local_date));
    if (values.length === 0) {
    return {
      reading_count: 0,
      valid_day_count: 0,
      avg_glucose: null,
      std_glucose: null,
      cv: null,
      in_range_ratio: null,
      range_glucose: null,
      min_glucose: null,
      max_glucose: null,
      latest_glucose: null,
    };
  }
  const min = Math.min(...values);
  const max = Math.max(...values);
  const latest = [...glucoseRows]
    .filter((row) => row.glucose_mmol !== null)
    .sort((a, b) => new Date(b.record_time).getTime() - new Date(a.record_time).getTime())[0];
  return {
    reading_count: values.length,
    valid_day_count: dates.size,
    avg_glucose: round(avg),
    std_glucose: round(sd),
    cv: avg !== null && sd !== null && avg > 0 ? round(sd / avg * 100, 1) : null,
    in_range_ratio: round(values.filter((value) => value >= 3.9 && value <= 10.0).length / values.length, 3),
    range_glucose: round(max - min),
    min_glucose: round(min),
    max_glucose: round(max),
    latest_glucose: round(latest?.glucose_mmol ?? null),
  };
}

function buildMealResponses(
  meals: Array<MealRow & { local_date: string }>,
  glucoseRows: Array<GlucoseRow & { glucose_mmol: number | null; local_date: string }>,
) {
  const responses = new Map<string, {
    meal_id: string;
    meal_time: string;
    meal_date: string;
    meal_type?: string | null;
    baseline_glucose: number | null;
    peakValues: number[];
  }>();
  for (const meal of meals) {
    const mealTime = new Date(meal.meal_time).getTime();
    const baseline = glucoseRows
      .filter((row) => {
        const recordTime = new Date(row.record_time).getTime();
        return row.glucose_mmol !== null &&
          recordTime >= mealTime - 120 * 60 * 1000 &&
          recordTime < mealTime &&
          ['空腹', '午餐前', '晚餐前', '随机'].includes(`${row.time_period ?? ''}`);
      })
      .sort((a, b) => new Date(b.record_time).getTime() - new Date(a.record_time).getTime())[0];
    responses.set(meal.id, {
      meal_id: meal.id,
      meal_time: meal.meal_time,
      meal_date: meal.local_date,
      meal_type: meal.meal_type,
      baseline_glucose: baseline?.glucose_mmol ?? null,
      peakValues: [],
    });
  }
  const sortedMeals = [...meals].sort((a, b) => new Date(a.meal_time).getTime() - new Date(b.meal_time).getTime());
  for (const row of glucoseRows) {
    if (row.glucose_mmol === null) continue;
    const recordTime = new Date(row.record_time).getTime();
    const assigned = sortedMeals
      .filter((meal) => {
        const mealTime = new Date(meal.meal_time).getTime();
        return recordTime > mealTime + 30 * 60 * 1000 && recordTime <= mealTime + 180 * 60 * 1000;
      })
      .sort((a, b) => new Date(b.meal_time).getTime() - new Date(a.meal_time).getTime())[0];
    if (assigned) {
      responses.get(assigned.id)?.peakValues.push(row.glucose_mmol);
    }
  }
  return [...responses.values()].map((response) => {
    const peak = response.peakValues.length === 0 ? null : Math.max(...response.peakValues);
    return {
      meal_id: response.meal_id,
      meal_time: response.meal_time,
      meal_date: response.meal_date,
      meal_type: response.meal_type,
      baseline_glucose: round(response.baseline_glucose),
      peak_glucose: round(peak),
      delta_glucose:
        response.baseline_glucose === null || peak === null ? null : round(peak - response.baseline_glucose),
      post_reading_count: response.peakValues.length,
    };
  });
}

function buildFoodSignals(mealResponses: Row[], mealItems: MealItemRow[]) {
  const responseByMeal = new Map(mealResponses.map((response) => [`${response.meal_id}`, response]));
  const stats = new Map<string, { deltas: number[]; latest: string }>();
  for (const item of mealItems) {
    const name = `${item.food_name_confirmed ?? ''}`.trim();
    const response = responseByMeal.get(`${item.meal_id}`);
    const delta = toNumber(response?.delta_glucose);
    if (!name || !response || delta === null) continue;
    const existing = stats.get(name) ?? { deltas: [], latest: `${response.meal_time ?? ''}` };
    existing.deltas.push(delta);
    if (`${response.meal_time ?? ''}` > existing.latest) existing.latest = `${response.meal_time ?? ''}`;
    stats.set(name, existing);
  }
  return [...stats.entries()].map(([name, item]) => {
    const avg = average(item.deltas)!;
    const mealCount = item.deltas.length;
    const signal = mealCount < 2 ? 'yellow' : avg >= 2.0 ? 'red' : avg <= 1.4 ? 'green' : 'yellow';
    return {
      food_name: name,
      signal_level: signal,
      avg_excursion: round(avg),
      meal_count: mealCount,
      latest_meal_time: item.latest,
      reason: foodReason(signal, mealCount, avg),
    };
  }).sort((a, b) => {
    const rank = { red: 0, yellow: 1, green: 2 } as Record<string, number>;
    const rankDiff = (rank[a.signal_level] ?? 3) - (rank[b.signal_level] ?? 3);
    if (rankDiff !== 0) return rankDiff;
    return (b.avg_excursion ?? 0) - (a.avg_excursion ?? 0);
  }).slice(0, 8);
}

function foodReason(signal: string, mealCount: number, avg: number) {
  if (mealCount < 2) return '样本还少，先继续记录餐后血糖';
  if (signal === 'red') return `多次记录后平均餐后升幅 ${avg.toFixed(1)} mmol/L，建议减少频率并控制份量`;
  if (signal === 'green') return '多次记录后餐后升幅较小，可以继续保留';
  return '影响还不稳定，建议结合份量、搭配和饭后活动继续观察';
}

function buildEnergyCorrelation(
  dailyStats: Row[],
  statusRows: StatusRow[],
  timezone: string,
  range: { startDate: string; endDate: string },
) {
  const energyByDate = new Map<string, number[]>();
  for (const status of statusRows) {
    const date = localDate(status.record_time, timezone);
    if (date < range.startDate || date > range.endDate) continue;
    const score = statusScore(status.status_level);
    if (score === null) continue;
    const values = energyByDate.get(date) ?? [];
    values.push(score);
    energyByDate.set(date, values);
  }
  const groups = new Map<string, number[]>();
  for (const stat of dailyStats) {
    const date = `${stat.record_date ?? ''}`;
    const energy = average(energyByDate.get(date) ?? []);
    if (energy === null) continue;
    const cv = toNumber(stat.cv);
    const category = cv === null ? 'insufficient' : cv < 36 ? 'stable' : 'unstable';
    const values = groups.get(category) ?? [];
    values.push(energy);
    groups.set(category, values);
  }
  return [...groups.entries()].map(([category, values]) => ({
    cv_category: category,
    avg_energy: round(average(values)),
    day_count: values.length,
    insight: category === 'stable'
      ? '血糖波动较稳的日子，平均精力状态更值得继续观察'
      : category === 'unstable'
        ? '血糖波动较大的日子，精力状态可能更容易受影响'
        : '有效血糖记录偏少，先积累更多同日状态记录',
  }));
}

function statusScore(status: unknown) {
  switch (`${status ?? ''}`) {
    case '极度疲劳':
      return 1;
    case '略感疲惫':
      return 2;
    case '状态平稳':
      return 3;
    case '感觉不错':
      return 4;
    case '精力充沛':
      return 5;
    default:
      return null;
  }
}

function buildDataQuality(weekly: Row, foods: Row[]) {
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

async function buildEvidencePayload(
  admin: ReturnType<typeof createClient>,
  userId: string,
  range: { startDate: string; endDate: string },
  timezone: string,
  report: {
    daily_stats: Row[];
    weekly_summary_metrics: Row;
    food_signals: Row[];
    energy_correlation: Row[];
    data_quality: Row;
  },
) {
  const fromIso = new Date(`${range.startDate}T00:00:00.000Z`);
  fromIso.setUTCDate(fromIso.getUTCDate() - 1);
  const toIso = new Date(`${range.endDate}T23:59:59.999Z`);
  toIso.setUTCDate(toIso.getUTCDate() + 1);

  const [glucoseRows, mealRows, statusRows, exerciseRows] = await Promise.all([
    selectRows<GlucoseRow>(
      admin
        .from('blood_glucose_logs')
        .select('id,user_id,record_time,time_period,value,unit,source')
        .eq('user_id', userId)
        .gte('record_time', fromIso.toISOString())
        .lte('record_time', toIso.toISOString())
        .order('record_time', { ascending: true }),
    ),
    selectRows<MealRow>(
      admin
        .from('meals')
        .select('id,user_id,meal_time,meal_type')
        .eq('user_id', userId)
        .gte('meal_time', fromIso.toISOString())
        .lte('meal_time', toIso.toISOString())
        .order('meal_time', { ascending: true }),
    ),
    selectRows<StatusRow>(
      admin
        .from('wellness_status')
        .select('record_time,status_level,related_meal_id,related_exercise_id')
        .eq('user_id', userId)
        .gte('record_time', fromIso.toISOString())
        .lte('record_time', toIso.toISOString())
        .order('record_time', { ascending: true }),
    ),
    selectRows<ExerciseRow>(
      admin
        .from('exercise_logs')
        .select('id,exercise_time,duration,calories_burned,mets_snapshot,exercise_catalog(name)')
        .eq('user_id', userId)
        .gte('exercise_time', fromIso.toISOString())
        .lte('exercise_time', toIso.toISOString())
        .order('exercise_time', { ascending: true }),
    ),
  ]);

  const mealIds = mealRows.map((meal) => meal.id);
  const mealItems = mealIds.length === 0
    ? []
    : await selectRows<MealItemRow>(
      admin
        .from('meal_items')
        .select('meal_id,food_name_confirmed')
        .in('meal_id', mealIds),
    );
  const itemsByMeal = new Map<string, string[]>();
  for (const item of mealItems) {
    const name = `${item.food_name_confirmed ?? ''}`.trim();
    if (!name) continue;
    const names = itemsByMeal.get(item.meal_id) ?? [];
    names.push(name);
    itemsByMeal.set(item.meal_id, names);
  }

  const normalizedGlucose = glucoseRows
    .map((row) => ({
      id: row.id,
      record_time: row.record_time,
      local_date: localDate(row.record_time, timezone),
      time_period: row.time_period ?? null,
      source: row.source ?? 'manual',
      glucose_mmol: normalizeGlucose(row.value, row.unit),
    }))
    .filter((row) => row.glucose_mmol !== null);
  const glucoseInRange = normalizedGlucose.filter((row) =>
    row.local_date >= range.startDate && row.local_date <= range.endDate
  );
  const mealsInRange = mealRows
    .map((meal) => ({ ...meal, local_date: localDate(meal.meal_time, timezone) }))
    .filter((meal) => meal.local_date >= range.startDate && meal.local_date <= range.endDate);
  const statusInRange = statusRows.filter((status) => {
    const date = localDate(status.record_time, timezone);
    return date >= range.startDate && date <= range.endDate;
  });
  const exerciseInRange = exerciseRows.filter((exercise) => {
    const date = localDate(exercise.exercise_time, timezone);
    return date >= range.startDate && date <= range.endDate;
  });

  const mealEvidence = mealsInRange.slice(-8).reverse().map((meal) => {
    const mealTime = new Date(meal.meal_time).getTime();
    const pre = [...normalizedGlucose]
      .filter((row) => {
        const recordTime = new Date(row.record_time).getTime();
        return row.glucose_mmol !== null &&
          recordTime >= mealTime - 180 * 60 * 1000 &&
          recordTime < mealTime;
      })
      .sort((a, b) => new Date(b.record_time).getTime() - new Date(a.record_time).getTime())[0];
    const postRows = normalizedGlucose
      .filter((row) => {
        const recordTime = new Date(row.record_time).getTime();
        return row.glucose_mmol !== null &&
          recordTime >= mealTime + 30 * 60 * 1000 &&
          recordTime <= mealTime + 180 * 60 * 1000;
      })
      .sort((a, b) => (b.glucose_mmol ?? 0) - (a.glucose_mmol ?? 0));
    const post = postRows[0];
    const status = statusInRange.find((item) => item.related_meal_id === meal.id) ??
      statusInRange.find((item) => {
        const recordTime = new Date(item.record_time).getTime();
        return recordTime >= mealTime && recordTime <= mealTime + 240 * 60 * 1000;
      });
    const exercise = exerciseInRange.find((item) => {
      const exerciseTime = new Date(item.exercise_time).getTime();
      return exerciseTime >= mealTime && exerciseTime <= mealTime + 180 * 60 * 1000;
    });
    const missing: string[] = [];
    if (!pre) missing.push('pre_glucose');
    if (!post) missing.push('post_glucose');
    if (!status) missing.push('status');
    if (!exercise) missing.push('after_meal_exercise');
    return {
      meal: meal.meal_type ?? '餐食',
      time: localDisplayTime(meal.meal_time, timezone),
      foods: itemsByMeal.get(meal.id) ?? [],
      pre_glucose: round(pre?.glucose_mmol ?? null),
      post_glucose: round(post?.glucose_mmol ?? null),
      post_minutes: post ? Math.round((new Date(post.record_time).getTime() - mealTime) / 60000) : null,
      glucose_delta: pre && post ? round((post.glucose_mmol ?? 0) - (pre.glucose_mmol ?? 0)) : null,
      status_after: status?.status_level ?? null,
      exercise_after: exercise ? {
        name: exercise.exercise_catalog?.name ?? '运动',
        minutes: toNumber(exercise.duration) ?? 0,
      } : null,
      missing,
    };
  }).filter((meal) => meal.foods.length > 0);

  const totalExerciseMinutes = exerciseInRange.reduce(
    (sum, item) => sum + (toNumber(item.duration) ?? 0),
    0,
  );
  const cgmRows = glucoseInRange.filter((row) => row.source === 'cgm');
  const missingData = buildMissingDataHints(mealEvidence, report.weekly_summary_metrics, statusInRange, exerciseInRange);
  const latestTimes = [
    ...glucoseInRange.map((item) => item.record_time),
    ...mealsInRange.map((item) => item.meal_time),
    ...statusInRange.map((item) => item.record_time),
    ...exerciseInRange.map((item) => item.exercise_time),
  ].sort();

  return {
    range: `${range.startDate} 至 ${range.endDate}`,
    cache_key: [
      range.startDate,
      range.endDate,
      glucoseInRange.length,
      mealsInRange.length,
      statusInRange.length,
      exerciseInRange.length,
      latestTimes.at(-1) ?? 'empty',
    ].join('|'),
    weekly_metrics: {
      glucose_count: toNumber(report.weekly_summary_metrics.reading_count) ?? 0,
      valid_days: toNumber(report.weekly_summary_metrics.valid_day_count) ?? 0,
      avg_glucose: toNumber(report.weekly_summary_metrics.avg_glucose),
      min_glucose: toNumber(report.weekly_summary_metrics.min_glucose),
      max_glucose: toNumber(report.weekly_summary_metrics.max_glucose),
      cv: toNumber(report.weekly_summary_metrics.cv),
      in_range_ratio: toNumber(report.weekly_summary_metrics.in_range_ratio),
    },
    meal_evidence: mealEvidence,
    food_signals: report.food_signals.slice(0, 5),
    energy_correlation: report.energy_correlation,
    exercise_evidence: {
      recent_count: exerciseInRange.length,
      total_minutes: totalExerciseMinutes,
      after_meal_records: mealEvidence.filter((meal) => meal.exercise_after !== null).length,
    },
    cgm_evidence: {
      count: cgmRows.length,
      has_demo_like_data: cgmRows.length >= 12,
    },
    data_quality: report.data_quality,
    missing_data: missingData,
  };
}

function buildMissingDataHints(
  mealEvidence: Row[],
  weekly: Row,
  statusRows: StatusRow[],
  exerciseRows: ExerciseRow[],
) {
  const hints: string[] = [];
  const missingPost = mealEvidence.filter((meal) => {
    const missing = Array.isArray(meal.missing) ? meal.missing : [];
    return missing.includes('post_glucose');
  }).length;
  const missingStatus = mealEvidence.filter((meal) => {
    const missing = Array.isArray(meal.missing) ? meal.missing : [];
    return missing.includes('status');
  }).length;
  if ((toNumber(weekly.reading_count) ?? 0) < 4) {
    hints.push('本周血糖记录偏少');
  }
  if (missingPost > 0) {
    hints.push('部分餐次缺少餐后2小时血糖');
  }
  if (statusRows.length === 0 || missingStatus > 0) {
    hints.push('部分餐次缺少状态记录');
  }
  if (exerciseRows.length === 0) {
    hints.push('本周运动记录偏少');
  }
  return hints.length === 0 ? ['本周记录可用于继续观察趋势'] : hints;
}

function localDisplayTime(isoValue: string, timezone: string) {
  return new Intl.DateTimeFormat('zh-CN', {
    timeZone: timezone,
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(new Date(isoValue));
}

function buildTemplateSummary(
  weekly: Row,
  foods: Row[],
  energyCorrelation: Row[],
) {
  const readingCount = toNumber(weekly.reading_count) ?? 0;
  const avg = toNumber(weekly.avg_glucose);
  const cv = toNumber(weekly.cv);
  const min = toNumber(weekly.min_glucose) ?? avg;
  const max = toNumber(weekly.max_glucose) ?? avg;
  const latest = toNumber(weekly.latest_glucose) ?? avg;
  if (readingCount < 1 || avg === null || avg <= 0 || min === null || max === null || latest === null) {
    return insufficientSummaryText();
  }

  const spread = max - min;
  const stability = cv === null
    ? spread <= 2.0 ? '比较平稳' : '略有波动'
    : cv < 36 ? '比较平稳' : '略有波动';
  const riskyFood = foods.find((food) => food.signal_level === 'red' && (toNumber(food.meal_count) ?? 0) >= 2);
  const energyHint = energyCorrelation.length > 0 ? '，也可以继续观察精力状态变化' : '';
  const foodHint = riskyFood?.food_name
    ? `，${riskyFood.food_name} 这类餐次建议多打标签`
    : '，特别是容易犯困或饥饿的餐次';

  return `近期血糖主要在 ${min.toFixed(1)}-${max.toFixed(1)} mmol/L 之间，最新记录为 ${latest.toFixed(1)}，整体表现${stability}。请继续保持记录${foodHint}${energyHint}，这样能帮您发现更多饮食规律哦。`;
}

async function buildLlmSummary(payload: {
  weekly_summary_metrics: Row;
  food_signals: Row[];
  energy_correlation: Row[];
  data_quality: Row;
  fallback: string;
}) {
  if (!hasUsableSummaryData(payload.weekly_summary_metrics)) {
    return { text: insufficientSummaryText(), source: 'template', error: 'insufficient_data' };
  }
  const apiKey = Deno.env.get('ANALYSIS_LLM_API_KEY') ?? Deno.env.get('ZHIPU_API_KEY');
  const apiUrl =
    Deno.env.get('ANALYSIS_LLM_API_URL') ??
      (Deno.env.get('ZHIPU_API_KEY')
        ? 'https://open.bigmodel.cn/api/paas/v4/chat/completions'
        : null);
  const model =
    Deno.env.get('ANALYSIS_LLM_MODEL') ??
      (Deno.env.get('ZHIPU_API_KEY') ? 'glm-4.7-flash' : 'deepseek-chat');
  if (!apiKey || !apiUrl) {
    return { text: payload.fallback, source: 'template', error: 'missing_llm_config' };
  }

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 12000);
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
              '你是一个专业的“血糖健康生活助手”。你的任务是根据用户近期（近7天）的结构化血糖和状态数据，生成一段精炼的总结。绝对规则：1.严禁医疗诊断，只能客观描述现象和趋势，不能出现糖尿病、确诊、用药、就医等诊断或治疗建议。2.使用适合手机阅读的自然短句，不要使用Markdown，不要换行，但不要求精确控制字数。3.语气温和、鼓励、客观，像贴心的电子手环。4.直接输出总结正文，禁止出现“好的”“为您生成”“根据提供的数据”等开场白。5.如果输入数据明显缺失或平均血糖为0，直接回复：“近期记录的数据较少，继续保持日常打卡，我会为您提供更准确的趋势分析哦。”',
          },
          {
            role: 'user',
            content: buildSummaryPrompt(payload),
          },
        ],
        temperature: 0.35,
      }),
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      return { text: payload.fallback, source: 'template', error: `llm_http_${response.status}` };
    }
    const content = data?.choices?.[0]?.message?.content;
    const summary = sanitizeLlmSummary(typeof content === 'string' ? content : '');
    if (!summary) {
      return { text: payload.fallback, source: 'template', error: 'invalid_llm_summary' };
    }
    return { text: summary, source: 'llm' };
  } catch (error) {
    console.error('analysis summary fallback:', error);
    const reason = error instanceof Error && error.name === 'AbortError' ? 'llm_timeout' : 'llm_exception';
    return { text: payload.fallback, source: 'template', error: reason };
  } finally {
    clearTimeout(timeoutId);
  }
}

async function buildAnalysisCards(evidence: Row) {
  const fallback = buildFallbackAnalysisCards(evidence);
  if (!hasUsableCardsData((evidence.weekly_metrics as Row | undefined) ?? {})) {
    return { cards: fallback, source: 'template', error: 'insufficient_data' };
  }
  const apiKey = Deno.env.get('ANALYSIS_LLM_API_KEY') ?? Deno.env.get('ZHIPU_API_KEY');
  const apiUrl =
    Deno.env.get('ANALYSIS_LLM_API_URL') ??
      (Deno.env.get('ZHIPU_API_KEY')
        ? 'https://open.bigmodel.cn/api/paas/v4/chat/completions'
        : null);
  const model =
    Deno.env.get('ANALYSIS_LLM_MODEL') ??
      (Deno.env.get('ZHIPU_API_KEY') ? 'glm-4.7-flash' : 'deepseek-chat');
  if (!apiKey || !apiUrl) {
    return { cards: fallback, source: 'template', error: 'missing_llm_config' };
  }

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 12000);
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
            content: analysisCardsSystemPrompt(),
          },
          {
            role: 'user',
            content: buildAnalysisCardsPrompt(evidence),
          },
        ],
        temperature: 0.25,
      }),
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      return { cards: fallback, source: 'template', error: `llm_http_${response.status}` };
    }
    const content = data?.choices?.[0]?.message?.content;
    const parsed = parseAnalysisCards(typeof content === 'string' ? content : '');
    if (!parsed) {
      return { cards: fallback, source: 'template', error: 'invalid_analysis_cards' };
    }
    return { cards: parsed, source: 'llm' };
  } catch (error) {
    console.error('analysis cards fallback:', error);
    const reason = error instanceof Error && error.name === 'AbortError' ? 'llm_timeout' : 'llm_exception';
    return { cards: fallback, source: 'template', error: reason };
  } finally {
    clearTimeout(timeoutId);
  }
}

function hasUsableCardsData(weekly: Row) {
  const avg = toNumber(weekly.avg_glucose);
  const readingCount = toNumber(weekly.glucose_count) ?? toNumber(weekly.reading_count) ?? 0;
  return avg !== null && avg > 0 && readingCount > 0;
}

function analysisCardsSystemPrompt() {
  return [
    '你是一个“普通人群血糖健康管理助手”的分析卡片生成器。',
    '你的任务是把用户近 7 天的血糖、饮食、运动、主观状态记录，转成普通用户能快速看懂的生活习惯观察卡片。',
    '',
    '绝对规则：',
    '1. 只能基于输入的 evidence 数据生成内容，不能编造没有记录的食物、血糖、运动或状态。',
    '2. 不能做医疗诊断，不能出现“糖尿病、确诊、治疗、用药、药物、胰岛素、处方、就医、医院”等表述。',
    '3. 所有结论必须使用保守措辞，例如“观察到、可能、建议继续记录、值得关注”，不能说“一定、必须、导致”。',
    '4. 当样本不足时，要明确说明“样本还少”或“缺少某类记录”，并给出下一步补记录建议。',
    '5. 输出必须是合法 JSON。不要输出解释性文字。不要输出 Markdown。',
    '6. 每条建议要具体、低门槛、可执行，优先围绕份量、搭配、饭后轻运动、状态记录。',
    '7. 面向普通用户，不解释复杂医学术语；如果必须出现 CV/TIR，要改写成“波动程度/目标范围内时间”。',
    '8. 文案要适合手机卡片阅读：短句、自然、不要写成长段报告，但不要求精确控制字数。',
    '',
    '请严格按以下 JSON 结构输出：',
    '{"overall":{"title":"本周重点标题","summary":"本周最重要的一句话观察","confidence":"low | medium | high","confidence_reason":"为什么是这个可信度"},"diet_cards":[{"title":"食物或餐次名","signal":"green | yellow | red | observe","evidence":"只写已有证据","suggestion":"具体饮食调整建议","next_record":"下次建议补充的记录"}],"exercise_card":{"title":"运动建议标题","evidence":"已有运动或缺少运动的证据","suggestion":"具体可执行运动建议"},"next_steps":[{"type":"glucose | diet | exercise | status","task":"下一步补记录任务"}],"safety_note":"仅供生活习惯参考，不替代医疗建议。"}',
  ].join('\n');
}

function buildAnalysisCardsPrompt(evidence: Row) {
  return [
    '请根据以下 evidence 生成分析卡片。',
    '不要重新计算没有提供的指标，不要扩展到证据之外。',
    '',
    'evidence:',
    JSON.stringify(evidence, null, 2),
  ].join('\n');
}

function parseAnalysisCards(raw: string) {
  const jsonText = extractJsonObject(raw);
  if (!jsonText) return null;
  try {
    const parsed = JSON.parse(jsonText);
    return normalizeAnalysisCards(parsed);
  } catch (_) {
    return null;
  }
}

function extractJsonObject(raw: string) {
  const trimmed = raw
    .replace(/```json/gi, '```')
    .replace(/```/g, '')
    .trim();
  const start = trimmed.indexOf('{');
  const end = trimmed.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  return trimmed.slice(start, end + 1);
}

function normalizeAnalysisCards(value: unknown) {
  if (!value || typeof value !== 'object') return null;
  const map = value as Row;
  const overall = map.overall && typeof map.overall === 'object'
    ? map.overall as Row
    : null;
  const exercise = map.exercise_card && typeof map.exercise_card === 'object'
    ? map.exercise_card as Row
    : null;
  if (!overall || !exercise || !Array.isArray(map.next_steps)) return null;

  const cards = {
    overall: {
      title: safeText(overall.title, '本周重点'),
      summary: safeText(overall.summary, '样本还少，建议继续记录餐食、血糖和状态来观察趋势。'),
      confidence: normalizeConfidence(overall.confidence),
      confidence_reason: safeText(overall.confidence_reason, '基于当前记录完整度'),
    },
    diet_cards: Array.isArray(map.diet_cards)
      ? map.diet_cards
        .filter((item) => item && typeof item === 'object')
        .slice(0, 3)
        .map((item) => {
          const row = item as Row;
          return {
            title: safeText(row.title, '饮食观察'),
            signal: normalizeSignal(row.signal),
            evidence: safeText(row.evidence, '样本还少，建议继续配对记录。'),
            suggestion: safeText(row.suggestion, '先控制份量，搭配蛋白质和蔬菜继续观察。'),
            next_record: safeText(row.next_record, '下次补餐后2小时血糖'),
          };
        })
      : [],
    exercise_card: {
      title: safeText(exercise.title, '饭后轻动'),
      evidence: safeText(exercise.evidence, '本周运动记录还可以继续补充。'),
      suggestion: safeText(exercise.suggestion, '先从饭后轻走10分钟开始观察状态。'),
    },
    next_steps: map.next_steps
      .filter((item) => item && typeof item === 'object')
      .slice(0, 4)
      .map((item) => {
        const row = item as Row;
        return {
          type: normalizeStepType(row.type),
          task: safeText(row.task, '继续补充一条记录'),
        };
      }),
    safety_note: '仅供生活习惯参考，不替代医疗建议。',
  };
  if (containsForbiddenMedicalText(JSON.stringify(cards))) return null;
  if (cards.diet_cards.length === 0) {
    cards.diet_cards.push({
      title: '饮食观察',
      signal: 'observe',
      evidence: '样本还少，暂时看不出稳定规律。',
      suggestion: '先选择一餐固定记录餐后血糖和状态。',
      next_record: '餐后2小时补血糖',
    });
  }
  if (cards.next_steps.length === 0) {
    cards.next_steps.push({ type: 'glucose', task: '餐后2小时补血糖' });
  }
  return cards;
}

function buildFallbackAnalysisCards(evidence: Row) {
  const weekly = (evidence.weekly_metrics as Row | undefined) ?? {};
  const missing = Array.isArray(evidence.missing_data)
    ? evidence.missing_data.map((item) => `${item}`)
    : [];
  const mealEvidence = Array.isArray(evidence.meal_evidence)
    ? evidence.meal_evidence as Row[]
    : [];
  const foodSignals = Array.isArray(evidence.food_signals)
    ? evidence.food_signals as Row[]
    : [];
  const glucoseCount = toNumber(weekly.glucose_count) ?? 0;
  const validDays = toNumber(weekly.valid_days) ?? 0;
  const avg = toNumber(weekly.avg_glucose);
  const confidence = glucoseCount >= 8 && validDays >= 4 ? 'medium' : 'low';
  const dietCards = foodSignals.slice(0, 3).map((signal) => ({
    title: safeText(signal.food_name, '饮食观察'),
    signal: normalizeSignal(signal.signal_level),
    evidence: toNumber(signal.avg_excursion) === null
      ? `参与 ${toNumber(signal.meal_count) ?? 0} 餐，样本还少`
      : `平均餐后升幅 ${formatMetric(toNumber(signal.avg_excursion), 'mmol/L')}`,
    suggestion: safeText(signal.reason, '先控制份量并继续观察餐后状态。'),
    next_record: '下次补餐后2小时血糖',
  }));
  for (const meal of mealEvidence) {
    if (dietCards.length >= 3) break;
    const foods = Array.isArray(meal.foods) ? meal.foods.join('、') : '这餐';
    const post = toNumber(meal.post_glucose);
    dietCards.push({
      title: foods || '饮食观察',
      signal: 'observe',
      evidence: post === null
        ? '这餐缺少餐后血糖记录'
        : `餐后约 ${toNumber(meal.post_minutes) ?? 0} 分钟 ${post.toFixed(1)} mmol/L`,
      suggestion: '先观察份量、搭配和饭后活动的变化。',
      next_record: post === null ? '餐后2小时补血糖' : '补一条餐后状态',
    });
  }
  if (dietCards.length === 0) {
    dietCards.push({
      title: '饮食观察',
      signal: 'observe',
      evidence: '样本还少，暂时看不出稳定规律。',
      suggestion: '先选择一餐固定记录餐后血糖和状态。',
      next_record: '餐后2小时补血糖',
    });
  }
  const exercise = (evidence.exercise_evidence as Row | undefined) ?? {};
  const exerciseMinutes = toNumber(exercise.total_minutes) ?? 0;
  return {
    overall: {
      title: '本周重点',
      summary: avg === null
        ? '本周血糖记录还少，建议先把餐食、餐后血糖和状态配对记录起来。'
        : `观察到本周平均血糖约 ${avg.toFixed(1)} mmol/L，建议结合餐后状态继续观察。`,
      confidence,
      confidence_reason: confidence === 'medium' ? '记录覆盖较多天' : '样本还少',
    },
    diet_cards: dietCards,
    exercise_card: {
      title: exerciseMinutes > 0 ? '继续轻运动' : '饭后轻动',
      evidence: exerciseMinutes > 0
        ? `本周已记录运动约 ${Math.round(exerciseMinutes)} 分钟`
        : '本周运动记录偏少',
      suggestion: '先从饭后轻走10分钟开始，记录运动后状态变化。',
    },
    next_steps: buildFallbackNextSteps(missing),
    safety_note: '仅供生活习惯参考，不替代医疗建议。',
  };
}

function buildFallbackNextSteps(missing: string[]) {
  const steps: Array<{ type: string; task: string }> = [];
  if (missing.some((item) => item.includes('血糖'))) {
    steps.push({ type: 'glucose', task: '餐后2小时补血糖' });
  }
  if (missing.some((item) => item.includes('状态'))) {
    steps.push({ type: 'status', task: '餐后犯困时记状态' });
  }
  if (missing.some((item) => item.includes('运动'))) {
    steps.push({ type: 'exercise', task: '饭后轻走后记运动' });
  }
  if (steps.length === 0) {
    steps.push({ type: 'diet', task: '继续记录下一餐搭配' });
  }
  return steps.slice(0, 4);
}

function safeText(value: unknown, fallback: string) {
  const text = `${value ?? ''}`.replace(/\s+/g, ' ').trim();
  if (!text || containsForbiddenMedicalText(text)) return fallback;
  return text;
}

function normalizeSignal(value: unknown) {
  const text = `${value ?? ''}`;
  return ['green', 'yellow', 'red', 'observe'].includes(text) ? text : 'observe';
}

function normalizeConfidence(value: unknown) {
  const text = `${value ?? ''}`;
  return ['low', 'medium', 'high'].includes(text) ? text : 'low';
}

function normalizeStepType(value: unknown) {
  const text = `${value ?? ''}`;
  return ['glucose', 'diet', 'exercise', 'status'].includes(text) ? text : 'diet';
}

function containsForbiddenMedicalText(value: string) {
  return /(糖尿病|确诊|诊断|服药|用药|药物|胰岛素|就医|医院|治疗|处方)/.test(value);
}

function buildSummaryPrompt(payload: {
  weekly_summary_metrics: Row;
  food_signals: Row[];
  energy_correlation: Row[];
  data_quality: Row;
}) {
  const weekly = payload.weekly_summary_metrics;
  const avg = formatMetric(toNumber(weekly.avg_glucose), 'mmol/L');
  const cv = formatMetric(toNumber(weekly.cv), '%');
  const inRange = formatPercent(toNumber(weekly.in_range_ratio));
  const min = formatMetric(toNumber(weekly.min_glucose), 'mmol/L');
  const max = formatMetric(toNumber(weekly.max_glucose), 'mmol/L');
  const latest = formatMetric(toNumber(weekly.latest_glucose), 'mmol/L');
  const foods = payload.food_signals
    .filter((food) => (toNumber(food.meal_count) ?? 0) >= 2)
    .map((food) => `${food.food_name ?? '未命名食物'} ${food.signal_level ?? 'yellow'} 平均升幅 ${formatMetric(toNumber(food.avg_excursion), 'mmol/L')}`)
    .join('；') || '暂无足量食物信号';
  const energy = payload.energy_correlation
    .map((item) => `${item.cv_category ?? 'unknown'}：平均精力 ${formatMetric(toNumber(item.avg_energy), '分')}，样本 ${toNumber(item.day_count) ?? 0} 天`)
    .join('；') || '暂无足量精力关联';
  const qualityMessages = Array.isArray(payload.data_quality.messages)
    ? payload.data_quality.messages.join('；')
    : '无额外质量提示';

  return [
    '用户近7天结构化聚合数据如下，请只基于这些聚合指标总结，不要重新计算：',
    `平均血糖：${avg}`,
    `血糖范围：${min}-${max}`,
    `最新血糖：${latest}`,
    `变异系数CV：${cv}`,
    `目标范围内记录占比：${inRange}`,
    `记录数量：${toNumber(weekly.reading_count) ?? 0} 条，覆盖 ${toNumber(weekly.valid_day_count) ?? 0} 天`,
    `食物信号：${foods}`,
    `精力关联：${energy}`,
    `数据质量：${qualityMessages}`,
    '输出要求：中文自然短句；不要Markdown；不要换行；不要出现“根据提供的数据”；不要诊断、用药或建议就医；不要求精确控制字数。',
  ].join('\n');
}

function hasUsableSummaryData(weekly: Row) {
  const avg = toNumber(weekly.avg_glucose);
  const readingCount = toNumber(weekly.reading_count) ?? 0;
  return avg !== null && avg > 0 && readingCount > 0;
}

function sanitizeLlmSummary(value: string) {
  const summary = value.replace(/\s+/g, ' ').trim();
  if (!summary) return null;
  if (summary.length < 12 || summary.length > 180) return null;
  if (/[\n\r#*_`>]/.test(value)) return null;
  if (/(好的|为您生成|根据提供的数据|根据数据)/.test(summary)) return null;
  if (/(糖尿病|确诊|诊断|服药|用药|药物|胰岛素|就医|医院|治疗|处方)/.test(summary)) return null;
  return summary;
}

function insufficientSummaryText() {
  return '近期记录的数据较少，继续保持日常打卡，我会为您提供更准确的趋势分析哦。';
}

function formatMetric(value: number | null, unit: string) {
  return value === null ? '暂无' : `${value.toFixed(1)} ${unit}`;
}

function formatPercent(value: number | null) {
  return value === null ? '暂无' : `${(value * 100).toFixed(0)}%`;
}
