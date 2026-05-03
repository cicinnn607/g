alter table public.blood_glucose_logs
  drop constraint if exists blood_glucose_logs_value_check;

alter table public.blood_glucose_logs
  drop constraint if exists blood_glucose_logs_value_unit_range;

alter table public.blood_glucose_logs
  add constraint blood_glucose_logs_value_unit_range check (
    (
      coalesce(unit, 'mmol/L') = 'mmol/L'
      and value >= 0.6
      and value <= 33.3
    )
    or (
      unit = 'mg/dL'
      and value >= 10
      and value <= 600
    )
  );

create or replace view public.glucose_normalized
with (security_invoker = true) as
select
  id,
  user_id,
  record_time,
  time_period,
  unit,
  source,
  value as raw_value,
  case
    when coalesce(unit, 'mmol/L') = 'mmol/L'
      and value between 0.6 and 33.3
      then value
    when unit = 'mg/dL'
      and value between 10 and 600
      then value / 18.0
    else null
  end as glucose_mmol
from public.blood_glucose_logs;

grant select on public.glucose_normalized to authenticated;

create or replace function public.get_daily_glucose_stats(
  start_date date,
  end_date date,
  timezone_param text default 'Asia/Shanghai'
)
RETURNS TABLE (
  record_date date,
  reading_count integer,
  avg_glucose numeric,
  std_glucose numeric,
  cv numeric,
  in_range_ratio numeric,
  range_glucose numeric,
  min_glucose numeric,
  max_glucose numeric
)
language sql
stable
set search_path = public
as $$
  with params as (
    select case
      when coalesce($3, '') = any (array[
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
        'Europe/Paris'
      ]) then $3
      else 'Asia/Shanghai'
    end as tz
  ),
  normalized as (
    select
      (gn.record_time at time zone params.tz)::date as local_date,
      gn.glucose_mmol
    from public.glucose_normalized gn
    cross join params
    where gn.user_id = auth.uid()
      and gn.glucose_mmol is not null
      and (gn.record_time at time zone params.tz)::date between $1 and $2
  )
  select
    local_date as record_date,
    count(*)::integer as reading_count,
    round(avg(glucose_mmol), 2) as avg_glucose,
    case
      when count(*) >= 2 then round(stddev_samp(glucose_mmol), 2)
      else null
    end as std_glucose,
    case
      when count(*) >= 2 and avg(glucose_mmol) > 0
        then round(stddev_samp(glucose_mmol) / avg(glucose_mmol) * 100, 1)
      else null
    end as cv,
    round(
      sum(case when glucose_mmol between 3.9 and 10.0 then 1 else 0 end)::numeric
        / nullif(count(*), 0),
      3
    ) as in_range_ratio,
    round(max(glucose_mmol) - min(glucose_mmol), 2) as range_glucose,
    round(min(glucose_mmol), 2) as min_glucose,
    round(max(glucose_mmol), 2) as max_glucose
  from normalized
  group by local_date
  order by local_date;
$$;

create or replace function public.get_weekly_glucose_summary(
  start_date date,
  end_date date,
  timezone_param text default 'Asia/Shanghai'
)
RETURNS TABLE (
  reading_count integer,
  valid_day_count integer,
  avg_glucose numeric,
  std_glucose numeric,
  cv numeric,
  in_range_ratio numeric,
  range_glucose numeric,
  min_glucose numeric,
  max_glucose numeric,
  first_record_time timestamptz,
  last_record_time timestamptz
)
language sql
stable
set search_path = public
as $$
  with params as (
    select case
      when coalesce($3, '') = any (array[
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
        'Europe/Paris'
      ]) then $3
      else 'Asia/Shanghai'
    end as tz
  ),
  normalized as (
    select
      gn.record_time,
      (gn.record_time at time zone params.tz)::date as local_date,
      gn.glucose_mmol
    from public.glucose_normalized gn
    cross join params
    where gn.user_id = auth.uid()
      and gn.glucose_mmol is not null
      and (gn.record_time at time zone params.tz)::date between $1 and $2
  )
  select
    count(*)::integer as reading_count,
    count(distinct local_date)::integer as valid_day_count,
    round(avg(glucose_mmol), 2) as avg_glucose,
    case
      when count(*) >= 2 then round(stddev_samp(glucose_mmol), 2)
      else null
    end as std_glucose,
    case
      when count(*) >= 2 and avg(glucose_mmol) > 0
        then round(stddev_samp(glucose_mmol) / avg(glucose_mmol) * 100, 1)
      else null
    end as cv,
    round(
      sum(case when glucose_mmol between 3.9 and 10.0 then 1 else 0 end)::numeric
        / nullif(count(*), 0),
      3
    ) as in_range_ratio,
    round(max(glucose_mmol) - min(glucose_mmol), 2) as range_glucose,
    round(min(glucose_mmol), 2) as min_glucose,
    round(max(glucose_mmol), 2) as max_glucose,
    min(record_time) as first_record_time,
    max(record_time) as last_record_time
  from normalized;
$$;

create or replace function public.get_meal_glucose_response(
  start_date date,
  end_date date,
  timezone_param text default 'Asia/Shanghai'
)
RETURNS TABLE (
  meal_id uuid,
  meal_time timestamptz,
  meal_date date,
  meal_type text,
  baseline_glucose numeric,
  peak_glucose numeric,
  delta_glucose numeric,
  post_reading_count integer
)
language sql
stable
set search_path = public
as $$
  with params as (
    select case
      when coalesce($3, '') = any (array[
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
        'Europe/Paris'
      ]) then $3
      else 'Asia/Shanghai'
    end as tz
  ),
  meals_in_scope as (
    select
      m.id as meal_id,
      m.meal_time,
      (m.meal_time at time zone params.tz)::date as meal_date,
      m.meal_type
    from public.meals m
    cross join params
    where m.user_id = auth.uid()
      and (m.meal_time at time zone params.tz)::date between $1 and $2
  ),
  baseline as (
    select
      m.meal_id,
      bg.glucose_mmol as baseline_glucose
    from meals_in_scope m
    left join lateral (
      select gn.glucose_mmol
      from public.glucose_normalized gn
      where gn.user_id = auth.uid()
        and gn.glucose_mmol is not null
        and gn.record_time >= m.meal_time - interval '120 minutes'
        and gn.record_time < m.meal_time
        and gn.time_period in ('空腹', '午餐前', '晚餐前', '随机')
      order by gn.record_time desc
      limit 1
    ) bg on true
  ),
  post_assignments as (
    select
      assigned.meal_id,
      bg.id as glucose_id,
      bg.glucose_mmol
    from public.glucose_normalized bg
    join lateral (
      select m.meal_id, m.meal_time
      from meals_in_scope m
      where bg.record_time > m.meal_time + interval '30 minutes'
        and bg.record_time <= m.meal_time + interval '180 minutes'
      order by m.meal_time desc, m.meal_id
      limit 1
    ) assigned on true
    where bg.user_id = auth.uid()
      and bg.glucose_mmol is not null
  ),
  post_peak as (
    select
      meal_id,
      max(glucose_mmol) as peak_glucose,
      count(distinct glucose_id)::integer as post_reading_count
    from post_assignments
    group by meal_id
  )
  select
    m.meal_id,
    m.meal_time,
    m.meal_date,
    m.meal_type,
    round(baseline.baseline_glucose, 2) as baseline_glucose,
    round(post_peak.peak_glucose, 2) as peak_glucose,
    case
      when baseline.baseline_glucose is null or post_peak.peak_glucose is null
        then null
      else round(post_peak.peak_glucose - baseline.baseline_glucose, 2)
    end as delta_glucose,
    coalesce(post_peak.post_reading_count, 0) as post_reading_count
  from meals_in_scope m
  left join baseline on baseline.meal_id = m.meal_id
  left join post_peak on post_peak.meal_id = m.meal_id
  order by m.meal_time desc;
$$;

create or replace function public.get_food_impact_stats(
  start_date date,
  end_date date,
  timezone_param text default 'Asia/Shanghai'
)
RETURNS TABLE (
  food_name text,
  signal_level text,
  avg_excursion numeric,
  meal_count integer,
  latest_meal_time timestamptz,
  reason text
)
language sql
stable
set search_path = public
as $$
  with responses as (
    select *
    from public.get_meal_glucose_response($1, $2, $3)
    where delta_glucose is not null
  ),
  food_rows as (
    select distinct
      responses.meal_id,
      responses.meal_time,
      nullif(trim(mi.food_name_confirmed), '') as food_name,
      responses.delta_glucose
    from responses
    join public.meal_items mi on mi.meal_id = responses.meal_id
    where nullif(trim(mi.food_name_confirmed), '') is not null
  ),
  grouped as (
    select
      food_name,
      count(distinct meal_id)::integer as meal_count,
      round(avg(delta_glucose), 2) as avg_excursion,
      max(meal_time) as latest_meal_time
    from food_rows
    group by food_name
  )
  select
    grouped.food_name,
    case
      when grouped.meal_count < 2 then 'yellow'
      when grouped.avg_excursion >= 2.0 then 'red'
      when grouped.avg_excursion <= 1.4 then 'green'
      else 'yellow'
    end as signal_level,
    grouped.avg_excursion,
    grouped.meal_count,
    grouped.latest_meal_time,
    case
      when grouped.meal_count < 2 then '样本还少，先继续记录餐后血糖'
      when grouped.avg_excursion >= 2.0 then
        '多次记录后平均餐后升幅 ' || round(grouped.avg_excursion, 1)::text || ' mmol/L，建议减少频率并控制份量'
      when grouped.avg_excursion <= 1.4 then
        '多次记录后餐后升幅较小，可以继续保留'
      else
        '影响还不稳定，建议结合份量、搭配和饭后活动继续观察'
    end as reason
  from grouped
  order by
    case
      when grouped.meal_count >= 2 and grouped.avg_excursion >= 2.0 then 0
      when grouped.meal_count < 2 then 1
      when grouped.avg_excursion <= 1.4 then 3
      else 2
    end,
    grouped.avg_excursion desc nulls last,
    grouped.latest_meal_time desc
  limit 8;
$$;

create or replace function public.get_energy_correlation(
  start_date date,
  end_date date,
  timezone_param text default 'Asia/Shanghai'
)
RETURNS TABLE (
  cv_category text,
  avg_energy numeric,
  day_count integer,
  insight text
)
language sql
stable
set search_path = public
as $$
  with params as (
    select case
      when coalesce($3, '') = any (array[
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
        'Europe/Paris'
      ]) then $3
      else 'Asia/Shanghai'
    end as tz
  ),
  daily_energy as (
    select
      (ws.record_time at time zone params.tz)::date as record_date,
      avg(case ws.status_level
        when '极度疲劳' then 1
        when '略感疲惫' then 2
        when '状态平稳' then 3
        when '感觉不错' then 4
        when '精力充沛' then 5
        else null
      end) as energy_score
    from public.wellness_status ws
    cross join params
    where ws.user_id = auth.uid()
      and (ws.record_time at time zone params.tz)::date between $1 and $2
    group by (ws.record_time at time zone params.tz)::date
  ),
  joined as (
    select
      case
        when dgs.cv is null then 'insufficient'
        when dgs.cv < 36 then 'stable'
        else 'unstable'
      end as cv_category,
      de.energy_score
    from public.get_daily_glucose_stats($1, $2, $3) dgs
    join daily_energy de on de.record_date = dgs.record_date
    where de.energy_score is not null
  )
  select
    joined.cv_category,
    round(avg(joined.energy_score), 2) as avg_energy,
    count(*)::integer as day_count,
    case joined.cv_category
      when 'stable' then '血糖波动较稳的日子，平均精力状态更值得继续观察'
      when 'unstable' then '血糖波动较大的日子，精力状态可能更容易受影响'
      else '有效血糖记录偏少，先积累更多同日状态记录'
    end as insight
  from joined
  group by joined.cv_category
  order by joined.cv_category;
$$;

grant execute on function public.get_daily_glucose_stats(date, date, text) to authenticated;
grant execute on function public.get_weekly_glucose_summary(date, date, text) to authenticated;
grant execute on function public.get_meal_glucose_response(date, date, text) to authenticated;
grant execute on function public.get_food_impact_stats(date, date, text) to authenticated;
grant execute on function public.get_energy_correlation(date, date, text) to authenticated;

notify pgrst, 'reload schema';
