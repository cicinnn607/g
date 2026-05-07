import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const functionVersion = 'analysis-report-2026-05-06-v2';
const maxEvidenceRows = 80;

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
  food_name_raw?: string | null;
  food_name_confirmed?: string | null;
  calories_raw?: number | string | null;
  calories_final?: number | string | null;
  calories_user_override?: number | string | null;
  portion_size?: number | string | null;
  grams?: number | string | null;
  serving_unit?: string | null;
};

type StatusRow = {
  id?: string;
  related_meal_id?: string | null;
  related_exercise_id?: string | null;
  record_time: string;
  status_level?: string | null;
  notes?: string | null;
};

type ExerciseRow = {
  id: string;
  motion_id?: string | null;
  exercise_time: string;
  duration?: number | string | null;
  calories_burned?: number | string | null;
  mets_snapshot?: number | string | null;
  exercise_catalog?: { name?: string | null } | null;
};

type ExerciseCatalogRow = {
  id: string;
  name?: string | null;
};

type ProfileRow = {
  id: string;
  display_name?: string | null;
  gender?: string | null;
  height?: number | string | null;
  birth_date?: string | null;
};

type BodyMetricRow = {
  weight?: number | string | null;
  record_time?: string | null;
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
    if (body.mode === 'cards') {
      const serviceRoleKey = mustGetEnv('SUPABASE_SERVICE_ROLE_KEY');
      const admin = createClient(supabaseUrl, serviceRoleKey);
      const report = await buildReportInFunction(admin, userData.user.id, range, timezone);
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
        report_type: cardsResult.cards.report_type ?? 'glucose_report',
        evidence_cache_key: evidence.cache_key,
        ...(cardsResult.error ? { analysis_cards_error: cardsResult.error } : {}),
      });
    }

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
    const message = describeError(error);
    console.error('analysis-report fatal:', message, error);
    return json({ error: message }, 500);
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
        .order('record_time', { ascending: true })
        .limit(maxEvidenceRows),
    ),
    selectRows<MealRow>(
      admin
        .from('meals')
        .select('id,user_id,meal_time,meal_type')
        .eq('user_id', userId)
        .gte('meal_time', fromIso.toISOString())
        .lte('meal_time', toIso.toISOString())
        .order('meal_time', { ascending: true })
        .limit(maxEvidenceRows),
    ),
    selectRows<StatusRow>(
      admin
        .from('wellness_status')
        .select('record_time,status_level')
        .eq('user_id', userId)
        .gte('record_time', fromIso.toISOString())
        .lte('record_time', toIso.toISOString())
        .order('record_time', { ascending: true })
        .limit(maxEvidenceRows),
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
  if (error) throw new Error(`${name}: ${describeError(error)}`);
  return Array.isArray(data) ? data as T[] : [];
}

async function selectRows<T>(
  query: PromiseLike<{ data: unknown; error: unknown }>,
): Promise<T[]> {
  const { data, error } = await query;
  if (error) throw new Error(describeError(error));
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

async function fetchMealItemsForEvidence(
  admin: ReturnType<typeof createClient>,
  mealIds: string[],
) {
  const modern = await admin
    .from('meal_items')
    .select('meal_id,food_name_raw,food_name_confirmed,calories_raw,calories_final,calories_user_override,grams,serving_unit')
    .in('meal_id', mealIds);

  if (!modern.error) {
    return Array.isArray(modern.data) ? modern.data as MealItemRow[] : [];
  }

  const message = describeError(modern.error).toLowerCase();
  const canFallback =
    message.includes('calories_user_override') ||
    message.includes('grams') ||
    message.includes('serving_unit') ||
    message.includes('column') && message.includes('does not exist') ||
    message.includes('could not find');
  if (!canFallback) {
    throw new Error(`meal_items modern select: ${describeError(modern.error)}`);
  }

  const legacy = await admin
    .from('meal_items')
    .select('meal_id,food_name_raw,food_name_confirmed,calories_raw,calories_final,portion_size')
    .in('meal_id', mealIds);
  if (legacy.error) {
    throw new Error(`meal_items legacy select: ${describeError(legacy.error)}`);
  }
  return Array.isArray(legacy.data) ? legacy.data as MealItemRow[] : [];
}

function json(body: unknown, status = 200) {
  const payload = body && typeof body === 'object' && !Array.isArray(body)
    ? { ...(body as Row), function_version: functionVersion }
    : body;
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function mustGetEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing env: ${name}`);
  return value;
}

function describeError(error: unknown): string {
  if (error instanceof Error) {
    return error.message || error.name;
  }
  if (typeof error === 'string') return error;
  if (error && typeof error === 'object') {
    const row = error as Row;
    const parts = [
      row.message,
      row.code,
      row.details,
      row.hint,
      row.error,
    ]
      .map((part) => `${part ?? ''}`.trim())
      .filter((part) => part.length > 0 && part !== 'null' && part !== 'undefined');
    if (parts.length > 0) return parts.join(' | ');
  }
  try {
    const value = JSON.stringify(error);
    if (value && value !== '{}') return value;
    return Object.prototype.toString.call(error);
  } catch (_) {
    return 'Unknown error';
  }
}

function resolveMealItemCalories(item: MealItemRow) {
  const finalCalories = toNumber(item.calories_final);
  if (finalCalories !== null) return finalCalories;
  const override = toNumber(item.calories_user_override);
  if (override !== null) return override;
  const raw = toNumber(item.calories_raw);
  if (raw === null) return null;
  const grams = toNumber(item.grams);
  if (grams !== null && grams > 0) return raw * grams / 100;
  const portion = toNumber(item.portion_size);
  if (portion !== null && portion > 0) return raw * portion;
  return raw;
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

function sumNumbers(values: Array<number | null>) {
  return values.reduce((sum, value) => sum + (value ?? 0), 0);
}

function ageFromBirthDate(value: unknown) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}/.test(value)) return null;
  const birthDate = new Date(`${value.slice(0, 10)}T00:00:00.000Z`);
  if (Number.isNaN(birthDate.getTime())) return null;
  const today = new Date();
  let age = today.getUTCFullYear() - birthDate.getUTCFullYear();
  const monthDiff = today.getUTCMonth() - birthDate.getUTCMonth();
  const dayDiff = today.getUTCDate() - birthDate.getUTCDate();
  if (monthDiff < 0 || (monthDiff === 0 && dayDiff < 0)) age -= 1;
  return age >= 0 && age <= 120 ? age : null;
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

  const [glucoseRows, mealRows, statusRows, exerciseRows, profileRow, bodyMetricRows] = await Promise.all([
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
        .select('id,record_time,status_level,notes,related_meal_id,related_exercise_id')
        .eq('user_id', userId)
        .gte('record_time', fromIso.toISOString())
        .lte('record_time', toIso.toISOString())
        .order('record_time', { ascending: true }),
    ),
    selectRows<ExerciseRow>(
      admin
        .from('exercise_logs')
        .select('id,motion_id,exercise_time,duration,calories_burned,mets_snapshot')
        .eq('user_id', userId)
        .gte('exercise_time', fromIso.toISOString())
        .lte('exercise_time', toIso.toISOString())
        .order('exercise_time', { ascending: true })
        .limit(maxEvidenceRows),
    ),
    admin
      .from('user_profile')
      .select('id,display_name,gender,height,birth_date')
      .eq('id', userId)
      .maybeSingle()
      .then(({ data }) => data as ProfileRow | null),
    selectRows<BodyMetricRow>(
      admin
        .from('user_body_metrics')
        .select('weight,record_time')
        .eq('user_id', userId)
        .order('record_time', { ascending: false })
        .limit(1),
    ),
  ]);

  const motionIds = Array.from(
    new Set(
      exerciseRows
        .map((item) => `${item.motion_id ?? ''}`.trim())
        .filter((id) => id.length > 0),
    ),
  );
  const exerciseCatalogRows = motionIds.length === 0
    ? []
    : await selectRows<ExerciseCatalogRow>(
      admin
        .from('exercise_catalog')
        .select('id,name')
        .in('id', motionIds),
    );
  const exerciseNameById = new Map(
    exerciseCatalogRows.map((item) => [item.id, item.name ?? '运动']),
  );

  const mealIds = mealRows.map((meal) => meal.id);
  const mealItems = mealIds.length === 0
    ? []
    : await fetchMealItemsForEvidence(admin, mealIds);
  const itemsByMeal = new Map<string, Array<{
    name: string;
    raw_name: string | null;
    calories_final: number | null;
    calories_raw: number | null;
    grams: number | null;
    serving_unit: string | null;
  }>>();
  for (const item of mealItems) {
    const name = `${item.food_name_confirmed ?? ''}`.trim();
    if (!name) continue;
    const items = itemsByMeal.get(item.meal_id) ?? [];
    items.push({
      name,
      raw_name: `${item.food_name_raw ?? ''}`.trim() || null,
      calories_final: resolveMealItemCalories(item),
      calories_raw: toNumber(item.calories_raw),
      grams: toNumber(item.grams),
      serving_unit: `${item.serving_unit ?? ''}`.trim() || null,
    });
    itemsByMeal.set(item.meal_id, items);
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
  const mealItemsInRange = mealsInRange.flatMap((meal) => itemsByMeal.get(meal.id) ?? []);

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
      foods: (itemsByMeal.get(meal.id) ?? []).map((item) => item.name),
      items: itemsByMeal.get(meal.id) ?? [],
      total_calories: round(sumNumbers((itemsByMeal.get(meal.id) ?? []).map((item) => item.calories_final)), 0),
      pre_glucose: round(pre?.glucose_mmol ?? null),
      post_glucose: round(post?.glucose_mmol ?? null),
      post_minutes: post ? Math.round((new Date(post.record_time).getTime() - mealTime) / 60000) : null,
      glucose_delta: pre && post ? round((post.glucose_mmol ?? 0) - (pre.glucose_mmol ?? 0)) : null,
      status_after: status?.status_level ?? null,
      status_notes: status?.notes ?? null,
      exercise_after: exercise ? {
        name: exerciseNameById.get(`${exercise.motion_id ?? ''}`) ?? '运动',
        minutes: toNumber(exercise.duration) ?? 0,
        calories_burned: toNumber(exercise.calories_burned),
        mets_snapshot: toNumber(exercise.mets_snapshot),
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
      latestTimes.length === 0 ? 'empty' : latestTimes[latestTimes.length - 1],
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
    user_profile: {
      gender: profileRow?.gender ?? null,
      height: toNumber(profileRow?.height),
      birth_date: profileRow?.birth_date ?? null,
      age: ageFromBirthDate(profileRow?.birth_date),
      weight: toNumber(bodyMetricRows[0]?.weight),
      weight_record_time: bodyMetricRows[0]?.record_time ?? null,
    },
    glucose_records: glucoseInRange.slice(-24).map((row) => ({
      time: localDisplayTime(row.record_time, timezone),
      period: row.time_period,
      value: round(row.glucose_mmol),
      source: row.source,
    })),
    dietary: {
      meal_count: mealsInRange.length,
      item_count: mealItemsInRange.length,
      total_calories: round(sumNumbers(mealItemsInRange.map((item) => item.calories_final)), 0),
      recent_meals: mealEvidence,
    },
    meal_evidence: mealEvidence,
    food_signals: report.food_signals.slice(0, 5),
    energy_correlation: report.energy_correlation,
    exercise_evidence: {
      recent_count: exerciseInRange.length,
      total_minutes: totalExerciseMinutes,
      total_calories_burned: round(sumNumbers(exerciseInRange.map((item) => toNumber(item.calories_burned))), 0),
      after_meal_records: mealEvidence.filter((meal) => meal.exercise_after !== null).length,
      logs: exerciseInRange.slice(-12).map((item) => ({
        time: localDisplayTime(item.exercise_time, timezone),
        name: exerciseNameById.get(`${item.motion_id ?? ''}`) ?? '运动',
        duration: toNumber(item.duration),
        calories_burned: toNumber(item.calories_burned),
        mets_snapshot: toNumber(item.mets_snapshot),
      })),
    },
    status_evidence: {
      count: statusInRange.length,
      logs: statusInRange.slice(-12).map((item) => ({
        time: localDisplayTime(item.record_time, timezone),
        level: item.status_level ?? null,
        notes: item.notes ?? null,
        related_meal_id: item.related_meal_id ?? null,
        related_exercise_id: item.related_exercise_id ?? null,
      })),
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
  const timeoutId = setTimeout(() => controller.abort(), 45000);
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
        thinking: { type: 'disabled' },
        max_tokens: 500,
        temperature: 0.35,
      }),
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      return { text: payload.fallback, source: 'template', error: llmHttpError(response.status, data) };
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
  const weekly = (evidence.weekly_metrics as Row | undefined) ?? {};
  const reportType = hasUsableCardsData(weekly)
    ? 'glucose_report'
    : hasLifestyleNoGlucoseData(evidence)
      ? 'lifestyle_no_glucose'
      : 'glucose_report';
  const fallback = reportType === 'lifestyle_no_glucose'
    ? buildFallbackLifestyleNoGlucoseReport(evidence)
    : buildFallbackAnalysisReport(evidence);
  if (reportType === 'glucose_report' && !hasUsableCardsData(weekly)) {
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
  const timeoutId = setTimeout(() => controller.abort(), 45000);
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
            content: reportType === 'lifestyle_no_glucose'
              ? lifestyleNoGlucoseSystemPrompt()
              : analysisReportSystemPrompt(),
          },
          {
            role: 'user',
            content: reportType === 'lifestyle_no_glucose'
              ? buildLifestyleNoGlucoseReportPrompt(evidence)
              : buildAnalysisReportPrompt(evidence),
          },
        ],
        thinking: { type: 'disabled' },
        max_tokens: 1200,
        temperature: 0.35,
      }),
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      return { cards: fallback, source: 'template', error: llmHttpError(response.status, data) };
    }
    const content = data?.choices?.[0]?.message?.content;
    const reportMarkdown = sanitizeReportMarkdown(
      typeof content === 'string' ? content : '',
      reportType,
    );
    if (!reportMarkdown) {
      return { cards: fallback, source: 'template', error: 'invalid_analysis_report' };
    }
    return {
      cards: {
        ...fallback,
        report_markdown: reportMarkdown,
      },
      source: 'llm',
    };
  } catch (error) {
    console.error('analysis report fallback:', error);
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

function hasLifestyleNoGlucoseData(evidence: Row) {
  const weekly = (evidence.weekly_metrics as Row | undefined) ?? {};
  const glucoseRecords = Array.isArray(evidence.glucose_records) ? evidence.glucose_records : [];
  const glucoseCount =
    toNumber(weekly.glucose_count) ??
      toNumber(weekly.reading_count) ??
      glucoseRecords.length;
  if (glucoseCount > 0) return false;

  const dietary = (evidence.dietary as Row | undefined) ?? {};
  const exercise = (evidence.exercise_evidence as Row | undefined) ?? {};
  const status = (evidence.status_evidence as Row | undefined) ?? {};
  const mealCount = toNumber(dietary.meal_count) ?? 0;
  const itemCount = toNumber(dietary.item_count) ?? 0;
  const exerciseCount = toNumber(exercise.recent_count) ?? 0;
  const statusCount = toNumber(status.count) ?? 0;
  return mealCount > 0 || itemCount > 0 || exerciseCount > 0 || statusCount > 0;
}

function llmHttpError(status: number, data: unknown) {
  const detail = describeError(data)
    .replaceAll(/\s+/g, ' ')
    .slice(0, 220);
  return detail && detail !== 'Unknown error'
    ? `llm_http_${status}: ${detail}`
    : `llm_http_${status}`;
}

function analysisReportSystemPrompt() {
  return [
    '你是一个专业的、充满亲和力的“私人精力与身材管理教练”。',
    '你的任务是根据用户过去一周的血糖、饮食、运动、主观状态数据，生成一份个性化、长文本形式的健康分析报告。',
    '',
    '核心分析逻辑：',
    '1. 关注“血糖波动与精力”的关联：高升糖饮食可能带来较快的血糖上升和随后的回落，一些人会表现为疲劳、注意力下降或食欲增强。',
    '2. 关注“运动干预”的反馈：规律运动和饭后轻活动可能降低波动幅度，让能量供应更稳定。',
    '3. 目标是通过数据反馈，引导用户在饮食和运动上做出低门槛微量改变，改善精力和体型管理体验。',
    '',
    '绝对规则：',
    '1. 只能基于输入的 evidence 数据生成内容，不能编造没有记录的食物、血糖、运动或状态。',
    '2. 不能做医疗诊断，不能出现“糖尿病、确诊、治疗、用药、药物、胰岛素、处方、就医、医院”等表述。',
    '3. 所有结论必须使用保守措辞，例如“观察到、可能、建议继续记录、值得关注”，不能说“一定、必须、导致”。',
    '4. 当样本不足时，要明确说明“样本还少”或“缺少某类记录”，并给出下一步补记录建议。',
    '5. 绝对不要输出任何 JSON 代码。请直接输出可展示给用户的 Markdown 富文本。',
    '6. 语气像真人健康教练一样自然、有同理心，避免生硬技术说教。',
    '7. 可以适当使用 Emoji，但不要夸张。',
    '8. 面向普通用户，不解释复杂医学术语；如果必须出现 CV/TIR，要改写成“波动程度/目标范围内时间”。',
    '',
    '报告必须包含以下四个 Markdown 三级标题，标题文字必须完全一致：',
    '### 🌟 本周整体概览',
    '### 🥗 饮食与精力追踪',
    '### 🏃‍♂️ 运动与代谢反馈',
    '### 💡 下一步微量改变',
  ].join('\n');
}

function lifestyleNoGlucoseSystemPrompt() {
  return [
    '你是一个专业的、充满亲和力的“私人精力与身材管理教练”。',
    '你的任务是根据用户过去一周的饮食、运动、主观状态数据，生成一份个性化、长文本形式的生活记录报告。',
    '',
    '当前分支的关键事实：本周血糖记录为 0。你必须明确说明缺少血糖数据，因此本报告只观察生活记录，不评价血糖变化。',
    '',
    '核心分析逻辑：',
    '1. 关注饮食结构、热量、用餐时间和主观精力状态之间的可能关联。',
    '2. 关注运动记录和状态反馈之间的关系，例如运动后是否更轻松、精神更稳定、疲劳感是否缓和。',
    '3. 目标是通过生活记录反馈，引导用户做出低门槛微量改变，并鼓励下一步补充血糖记录。',
    '',
    '绝对规则：',
    '1. 只能基于输入的 evidence 数据生成内容，不能编造没有记录的食物、运动或状态。',
    '2. 不能评价血糖平稳、血糖波动、达标占比、餐后血糖变化、血糖因果关系，也不能写“血糖更稳定、波动更小、达标更好”。',
    '3. 不能做医疗诊断，不能出现“糖尿病、确诊、治疗、用药、药物、胰岛素、处方、就医、医院”等表述。',
    '4. 所有结论必须使用保守措辞，例如“观察到、可能、建议继续记录、值得关注”，不能说“一定、必须、导致”。',
    '5. 当某类记录不足时，要明确说明“样本还少”或“缺少某类记录”，并给出下一步补记录建议。',
    '6. 绝对不要输出任何 JSON 代码。请直接输出可展示给用户的 Markdown 富文本。',
    '7. 语气像真人健康教练一样自然、有同理心，避免生硬技术说教。',
    '8. 可以适当使用 Emoji，但不要夸张。',
    '',
    '报告必须包含以下四个 Markdown 三级标题，标题文字必须完全一致：',
    '### 🌟 本周整体概览',
    '### 🥗 饮食与精力追踪',
    '### 🏃‍♂️ 运动与状态反馈',
    '### 💡 下一步微量改变',
  ].join('\n');
}

function buildAnalysisReportPrompt(evidence: Row) {
  return [
    '请根据以下 evidence 生成分析报告。',
    '不要重新计算没有提供的指标，不要扩展到证据之外。',
    '输出必须是 Markdown 正文，不要包裹代码块。',
    '',
    'evidence:',
    JSON.stringify(evidence, null, 2),
  ].join('\n');
}

function buildLifestyleNoGlucoseReportPrompt(evidence: Row) {
  return [
    '请根据以下 evidence 生成生活记录报告。',
    '本周没有血糖记录，不要重新计算或推断任何血糖指标。',
    '只能分析饮食、运动、主观状态记录，并在下一步建议中鼓励补充血糖记录。',
    '输出必须是 Markdown 正文，不要包裹代码块。',
    '',
    'evidence:',
    JSON.stringify(evidence, null, 2),
  ].join('\n');
}

function sanitizeReportMarkdown(raw: string, reportType = 'glucose_report') {
  const markdown = normalizeReportHeadings(
    stripBenignMedicalDisclaimers(
      raw.replace(/```(?:markdown|md)?/gi, '').replace(/```/g, '').trim(),
    ),
    reportType,
  );
  if (!markdown || markdown.length < 80 || markdown.length > 4000) return null;
  if (markdown.includes('{') && markdown.includes('"report_markdown"')) return null;
  if (containsForbiddenMedicalText(markdown)) return null;
  if (
    reportType === 'lifestyle_no_glucose' &&
    containsNoGlucoseForbiddenInference(markdown)
  ) return null;
  const required = requiredReportHeadings(reportType);
  if (!required.every((heading) => markdown.includes(heading))) return null;
  return markdown;
}

function containsNoGlucoseForbiddenInference(markdown: string) {
  const compact = markdown.replace(/\s+/g, '');
  return (
    /血糖(更|较|比较|整体|看起来|保持|依然)(平稳|稳定)/.test(compact) ||
    /血糖波动(明显|较大|较小|更小|更平缓|稳定|平稳)/.test(compact) ||
    /餐后血糖(上升|下降|回落|达到|约为)/.test(compact) ||
    /达标占比(较高|较低|更好|不错|改善|稳定|达到|约为)/.test(compact) ||
    /血糖因果关系/.test(compact)
  );
}

function requiredReportHeadings(reportType = 'glucose_report') {
  return [
    '### 🌟 本周整体概览',
    '### 🥗 饮食与精力追踪',
    reportType === 'lifestyle_no_glucose'
      ? '### 🏃‍♂️ 运动与状态反馈'
      : '### 🏃‍♂️ 运动与代谢反馈',
    '### 💡 下一步微量改变',
  ];
}

function normalizeReportHeadings(markdown: string, reportType = 'glucose_report') {
  const movementTarget = reportType === 'lifestyle_no_glucose'
    ? '### 🏃‍♂️ 运动与状态反馈'
    : '### 🏃‍♂️ 运动与代谢反馈';
  const movementPattern = reportType === 'lifestyle_no_glucose'
    ? /(运动|活动).*(状态|反馈|精力|感受)|运动建议|运动与状态/
    : /(运动|活动).*(代谢|反馈|血糖|状态)|运动建议|运动与代谢/;
  const rules = [
    {
      target: '### 🌟 本周整体概览',
      pattern: /(本周|整体).*(概览|总结|表现|情况)|本周重点|整体概览/,
    },
    {
      target: '### 🥗 饮食与精力追踪',
      pattern: /(饮食|餐食|食物).*(精力|状态|追踪|观察)|饮食与精力|饮食观察/,
    },
    {
      target: movementTarget,
      pattern: movementPattern,
    },
    {
      target: '### 💡 下一步微量改变',
      pattern: /(下一步|下周|微量|小建议|建议).*(改变|行动|记录|尝试)|下一步微量改变/,
    },
  ];
  const used = new Set<string>();
  return markdown
    .split('\n')
    .map((line) => {
      const candidate = line
        .replace(/^#{1,6}\s*/, '')
        .replace(/^\*\*/, '')
        .replace(/\*\*$/, '')
        .replace(/[🌟🥗🏃‍♂️💡⭐✨📌📊📝、：:]/g, '')
        .trim();
      for (const rule of rules) {
        if (!used.has(rule.target) && rule.pattern.test(candidate)) {
          used.add(rule.target);
          return rule.target;
        }
      }
      return line;
    })
    .join('\n')
    .trim();
}

function stripBenignMedicalDisclaimers(markdown: string) {
  return markdown
    .split('\n')
    .filter((line) => {
      const text = line.replace(/\s+/g, '');
      return !(
        /仅供.*参考/.test(text) && /(诊断|治疗|就医|医生|医疗)/.test(text) ||
        /不替代.*(诊断|治疗|就医|医生|医疗)/.test(text) ||
        /不能替代.*(诊断|治疗|就医|医生|医疗)/.test(text)
      );
    })
    .join('\n')
    .trim();
}

function buildFallbackAnalysisReport(evidence: Row) {
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
  const exercise = (evidence.exercise_evidence as Row | undefined) ?? {};
  const glucoseCount = toNumber(weekly.glucose_count) ?? 0;
  const validDays = toNumber(weekly.valid_days) ?? 0;
  const avg = toNumber(weekly.avg_glucose);
  const confidence = glucoseCount >= 8 && validDays >= 4 ? 'medium' : 'low';
  const exerciseMinutes = toNumber(exercise.total_minutes) ?? 0;
  const firstFood = foodSignals.find((signal) => safeText(signal.food_name, '').length > 0);
  const firstMeal = mealEvidence.find((meal) => Array.isArray(meal.foods) && meal.foods.length > 0);
  const foodText = firstFood
    ? `${safeText(firstFood.food_name, '部分餐食')} 已经有一些记录，可以继续配对餐后血糖和状态观察。`
    : firstMeal
      ? `${(firstMeal.foods as unknown[]).map((item) => `${item}`).join('、')} 这类餐食可以作为下一步重点观察对象。`
      : '饮食样本还少，暂时不对某个食物下结论。';
  const exerciseText = exerciseMinutes > 0
    ? `本周已记录运动约 ${Math.round(exerciseMinutes)} 分钟，可以继续观察饭后轻活动后的状态。`
    : '本周运动记录偏少，先从饭后轻走 10 分钟开始比较容易坚持。';
  const reportMarkdown = [
    '### 🌟 本周整体概览',
    avg === null
      ? `本周血糖记录还少，已有 ${glucoseCount} 条血糖记录，建议先把餐食、餐后血糖和状态配对记录起来。`
      : `观察到本周平均血糖约 ${avg.toFixed(1)} mmol/L，记录覆盖 ${validDays} 天，建议结合餐后状态继续观察。`,
    '',
    '### 🥗 饮食与精力追踪',
    `${foodText} 如果餐后容易犯困、饥饿或注意力下降，下一次可以补一条状态备注。`,
    '',
    '### 🏃‍♂️ 运动与代谢反馈',
    exerciseText,
    '',
    '### 💡 下一步微量改变',
    buildFallbackMicroChange(missing),
  ].join('\n');
  return {
    overall: {
      title: '本周重点',
      summary: avg === null
        ? '本周血糖记录还少，建议先把餐食、餐后血糖和状态配对记录起来。'
        : `观察到本周平均血糖约 ${avg.toFixed(1)} mmol/L，建议结合餐后状态继续观察。`,
      confidence,
      confidence_reason: confidence === 'medium' ? '记录覆盖较多天' : '样本还少',
    },
    report_type: 'glucose_report',
    report_markdown: reportMarkdown,
    safety_note: '仅供生活习惯参考，不替代医疗建议。',
  };
}

function buildFallbackLifestyleNoGlucoseReport(evidence: Row) {
  const dietary = (evidence.dietary as Row | undefined) ?? {};
  const mealEvidence = Array.isArray(evidence.meal_evidence)
    ? evidence.meal_evidence as Row[]
    : [];
  const exercise = (evidence.exercise_evidence as Row | undefined) ?? {};
  const status = (evidence.status_evidence as Row | undefined) ?? {};
  const missing = Array.isArray(evidence.missing_data)
    ? evidence.missing_data.map((item) => `${item}`)
    : [];
  const mealCount = toNumber(dietary.meal_count) ?? 0;
  const itemCount = toNumber(dietary.item_count) ?? 0;
  const totalCalories = toNumber(dietary.total_calories);
  const exerciseCount = toNumber(exercise.recent_count) ?? 0;
  const exerciseMinutes = toNumber(exercise.total_minutes) ?? 0;
  const statusCount = toNumber(status.count) ?? 0;
  const firstMeal = mealEvidence.find((meal) => Array.isArray(meal.foods) && meal.foods.length > 0);
  const foodText = firstMeal
    ? `${(firstMeal.foods as unknown[]).map((item) => `${item}`).join('、')} 这类餐食已经进入记录，可以继续配合饭后状态备注来看精力变化。`
    : mealCount > 0
      ? `本周已有 ${mealCount} 餐饮食记录，${itemCount} 个食物条目；如果继续补全食物名和份量，报告会更容易看出饮食节奏。`
      : '本周饮食记录还少，暂时不对具体食物或餐食组合下结论。';
  const calorieText = totalCalories !== null && totalCalories > 0
    ? `记录到的饮食热量约 ${Math.round(totalCalories)} kcal，可作为生活节奏观察，不代表精确摄入。`
    : '饮食热量还不完整，先把常吃餐次记录清楚就很好。';
  const exerciseText = exerciseCount > 0
    ? `本周已记录 ${exerciseCount} 次运动，合计约 ${Math.round(exerciseMinutes)} 分钟，可以继续观察运动当天的精力备注。`
    : '本周运动记录还少，可以先从一次饭后轻走或短时拉伸开始记录。';
  const statusText = statusCount > 0
    ? `本周已有 ${statusCount} 条精力状态记录，这些备注能帮助你回看哪些时段更容易疲惫或状态更好。`
    : '本周精力状态备注还少，建议在犯困、饥饿或状态不错时补一句感受。';
  const reportMarkdown = [
    '### 🌟 本周整体概览',
    `本周没有血糖记录，因此这份报告不评价血糖波动、达标占比或餐后血糖变化；当前先基于 ${mealCount} 餐饮食、${exerciseCount} 次运动和 ${statusCount} 条状态记录做生活观察。`,
    '',
    '### 🥗 饮食与精力追踪',
    `${foodText} ${calorieText}`,
    '',
    '### 🏃‍♂️ 运动与状态反馈',
    `${exerciseText} ${statusText}`,
    '',
    '### 💡 下一步微量改变',
    buildFallbackLifestyleMicroChange(missing, mealCount, exerciseCount, statusCount),
  ].join('\n');
  return {
    overall: {
      title: '本周重点',
      summary: `本周没有血糖记录，先根据饮食、运动和状态记录生成生活观察；下一步建议补一条餐后血糖，让报告能把生活行为和血糖读数配对起来。`,
      confidence: mealCount + exerciseCount + statusCount >= 6 ? 'medium' : 'low',
      confidence_reason: '当前为无血糖生活记录分支',
    },
    report_type: 'lifestyle_no_glucose',
    report_markdown: reportMarkdown,
    safety_note: '仅供生活习惯参考，不替代医疗建议。',
  };
}

function buildFallbackLifestyleMicroChange(
  missing: string[],
  mealCount: number,
  exerciseCount: number,
  statusCount: number,
) {
  if (mealCount === 0) {
    return '下周先固定记录一餐最常吃的饭，再写一句饭后精力感受，先把生活线索连起来。';
  }
  if (statusCount === 0) {
    return '下周在一餐后补一句状态备注，比如“犯困”“饥饿感强”或“状态平稳”，让饮食记录更有上下文。';
  }
  if (exerciseCount === 0) {
    return '下周选择一餐后轻走 10 分钟，并记录当时状态，看看这个小动作是否更容易坚持。';
  }
  if (missing.some((item) => item.includes('血糖'))) {
    return '下周优先补一条餐后 2 小时血糖，再配一条状态备注；这样下一次就能生成完整血糖分析报告。';
  }
  return '下周继续保持生活记录节奏，并优先补一条餐后 2 小时血糖，让报告从生活观察升级到完整血糖分析。';
}

function buildFallbackMicroChange(missing: string[]) {
  if (missing.some((item) => item.includes('血糖'))) {
    return '下周先固定补一条餐后 2 小时血糖，让报告更容易判断餐食后的真实变化。';
  }
  if (missing.some((item) => item.includes('状态'))) {
    return '下周先在犯困、饥饿或状态稳定时补一句状态备注，帮助识别饮食和精力的关系。';
  }
  if (missing.some((item) => item.includes('运动'))) {
    return '下周选择一餐后轻走 10 分钟，并记录当时状态，看看饭后活动是否让你更舒服。';
  }
  return '下周继续保持当前记录节奏，优先把餐食、餐后血糖和状态放在同一天配对记录。';
}

function safeText(value: unknown, fallback: string) {
  const text = `${value ?? ''}`.replace(/\s+/g, ' ').trim();
  if (!text || containsForbiddenMedicalText(text)) return fallback;
  return text;
}

function containsForbiddenMedicalText(value: string) {
  return /(糖尿病|确诊|诊断为|服药|用药|药物|胰岛素|处方|治疗方案|建议就医|及时就医|尽快就医|去医院|看医生)/.test(value);
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
