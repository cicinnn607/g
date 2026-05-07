-- Demo data import for the glucose assistant.
-- Source reference: CGM report 数据.pdf, original range 2025-05-08 to 2025-05-21.
-- Target demo range: 2026-04-23 to 2026-05-05.
--
-- Usage:
-- 1. Open Supabase Dashboard -> SQL Editor.
-- 2. Replace demo_email below with the email of the account used in the app demo.
-- 3. Run the whole script.
--
-- Notes:
-- - The PDF is a report, not raw CGM exports. It contains daily MBG/TIR/TBR and
--   meal/exercise events, but not every original sensor reading.
-- - The glucose rows below are reasonable demo CGM readings shaped around the
--   daily averages in the report, so the app can show charts and analysis.
-- - The report has 14 days, while 2026-04-23 to 2026-05-05 has 13 days, so this
--   script maps the first 13 report days to the target range.

do $$
declare
  demo_email text := 'REPLACE_WITH_DEMO_ACCOUNT_EMAIL';
  demo_user_id uuid;
  start_ts timestamptz := '2026-04-23 00:00:00+08';
  end_ts timestamptz := '2026-05-06 00:00:00+08';
  demo_weight numeric := 65;
  meal_row record;
  item_row record;
  new_meal_id uuid;
begin
  select id
  into demo_user_id
  from auth.users
  where email = demo_email
  limit 1;

  if demo_user_id is null then
    raise exception 'No auth.users row found for email: %', demo_email;
  end if;

  -- Clean only this demo account and only the target demo window.
  delete from public.wellness_status
  where user_id = demo_user_id
    and record_time >= start_ts
    and record_time < end_ts;

  delete from public.exercise_logs
  where user_id = demo_user_id
    and exercise_time >= start_ts
    and exercise_time < end_ts;

  delete from public.meals
  where user_id = demo_user_id
    and meal_time >= start_ts
    and meal_time < end_ts;

  delete from public.blood_glucose_logs
  where user_id = demo_user_id
    and record_time >= start_ts
    and record_time < end_ts;

  delete from public.user_body_metrics
  where user_id = demo_user_id
    and record_time >= start_ts
    and record_time < end_ts;

  insert into public.user_body_metrics (id, user_id, weight, record_time)
  values (gen_random_uuid(), demo_user_id, demo_weight, start_ts + interval '8 hours');

  -- Some deployed databases may not have the exercise catalog seed rows.
  -- The demo exercise logs below reference these IDs through a foreign key,
  -- so make sure the required catalog entries exist first.
  insert into public.exercise_catalog (id, name, met_value, category, description)
  values
    ('10000000-0000-4000-8000-000000000001', '缓慢步行 (<4km/h)', 2.0, '低强度', '散步、逛街等非常轻松的走动'),
    ('10000000-0000-4000-8000-000000000007', '慢跑 (8km/h)', 7.0, '中等强度', '初学者常见的跑步速度'),
    ('10000000-0000-4000-8000-000000000011', '上下楼梯', 8.0, '高强度', '爬楼梯锻炼')
  on conflict (id) do update set
    name = excluded.name,
    met_value = excluded.met_value,
    category = excluded.category,
    description = excluded.description;

  -- CGM-style glucose readings. Values are in mmol/L.
  insert into public.blood_glucose_logs (
    id,
    user_id,
    record_time,
    time_period,
    value,
    unit,
    source
  )
  select
    gen_random_uuid(),
    demo_user_id,
    v.record_time::timestamptz,
    v.time_period,
    v.value,
    'mmol/L',
    'cgm'
  from (
    values
      ('2026-04-23 07:20:00+08', '空腹', 4.9),
      ('2026-04-23 09:30:00+08', '早餐后', 5.4),
      ('2026-04-23 11:30:00+08', '午餐前', 5.1),
      ('2026-04-23 14:00:00+08', '午餐后', 5.2),
      ('2026-04-23 18:00:00+08', '晚餐前', 5.0),
      ('2026-04-23 19:30:00+08', '晚餐后', 5.7),
      ('2026-04-23 22:30:00+08', '睡前', 5.1),
      ('2026-04-24 06:50:00+08', '空腹', 4.6),
      ('2026-04-24 09:40:00+08', '早餐后', 5.6),
      ('2026-04-24 11:50:00+08', '午餐前', 5.0),
      ('2026-04-24 13:50:00+08', '午餐后', 5.4),
      ('2026-04-24 17:50:00+08', '晚餐前', 4.9),
      ('2026-04-24 20:00:00+08', '晚餐后', 5.7),
      ('2026-04-24 22:50:00+08', '睡前', 4.7),
      ('2026-04-25 06:55:00+08', '空腹', 4.5),
      ('2026-04-25 09:35:00+08', '早餐后', 5.3),
      ('2026-04-25 11:50:00+08', '午餐前', 4.9),
      ('2026-04-25 13:50:00+08', '午餐后', 5.2),
      ('2026-04-25 17:30:00+08', '晚餐前', 4.8),
      ('2026-04-25 19:30:00+08', '晚餐后', 5.6),
      ('2026-04-25 22:30:00+08', '睡前', 4.6),
      ('2026-04-26 07:10:00+08', '空腹', 4.7),
      ('2026-04-26 09:30:00+08', '早餐后', 5.2),
      ('2026-04-26 11:40:00+08', '午餐前', 5.0),
      ('2026-04-26 14:10:00+08', '午餐后', 5.5),
      ('2026-04-26 18:00:00+08', '晚餐前', 4.8),
      ('2026-04-26 20:30:00+08', '晚餐后', 5.6),
      ('2026-04-26 22:40:00+08', '睡前', 4.9),
      ('2026-04-27 07:10:00+08', '空腹', 4.6),
      ('2026-04-27 09:30:00+08', '早餐后', 5.1),
      ('2026-04-27 11:30:00+08', '午餐前', 4.9),
      ('2026-04-27 13:50:00+08', '午餐后', 5.3),
      ('2026-04-27 17:00:00+08', '晚餐前', 4.7),
      ('2026-04-27 19:20:00+08', '晚餐后', 5.4),
      ('2026-04-27 22:30:00+08', '睡前', 4.8),
      ('2026-04-28 07:00:00+08', '空腹', 4.7),
      ('2026-04-28 09:30:00+08', '早餐后', 5.2),
      ('2026-04-28 11:30:00+08', '午餐前', 4.9),
      ('2026-04-28 13:50:00+08', '午餐后', 5.4),
      ('2026-04-28 17:30:00+08', '晚餐前', 4.8),
      ('2026-04-28 19:40:00+08', '晚餐后', 5.3),
      ('2026-04-28 22:20:00+08', '睡前', 4.9),
      ('2026-04-29 07:10:00+08', '空腹', 4.4),
      ('2026-04-29 09:30:00+08', '早餐后', 5.0),
      ('2026-04-29 11:30:00+08', '午餐前', 4.6),
      ('2026-04-29 13:50:00+08', '午餐后', 5.1),
      ('2026-04-29 17:10:00+08', '晚餐前', 4.6),
      ('2026-04-29 19:20:00+08', '晚餐后', 5.1),
      ('2026-04-29 22:20:00+08', '睡前', 4.7),
      ('2026-04-30 07:10:00+08', '空腹', 4.7),
      ('2026-04-30 09:40:00+08', '早餐后', 5.4),
      ('2026-04-30 11:30:00+08', '午餐前', 4.8),
      ('2026-04-30 13:50:00+08', '午餐后', 5.5),
      ('2026-04-30 17:30:00+08', '晚餐前', 4.8),
      ('2026-04-30 19:40:00+08', '晚餐后', 5.3),
      ('2026-04-30 22:20:00+08', '睡前', 4.8),
      ('2026-05-01 07:10:00+08', '空腹', 4.0),
      ('2026-05-01 09:30:00+08', '早餐后', 4.8),
      ('2026-05-01 11:30:00+08', '午餐前', 4.5),
      ('2026-05-01 13:50:00+08', '午餐后', 4.9),
      ('2026-05-01 17:30:00+08', '晚餐前', 4.3),
      ('2026-05-01 19:40:00+08', '晚餐后', 4.8),
      ('2026-05-01 22:20:00+08', '睡前', 3.8),
      ('2026-05-02 07:10:00+08', '空腹', 4.2),
      ('2026-05-02 09:30:00+08', '早餐后', 5.1),
      ('2026-05-02 11:30:00+08', '午餐前', 4.6),
      ('2026-05-02 13:50:00+08', '午餐后', 5.0),
      ('2026-05-02 17:30:00+08', '晚餐前', 4.4),
      ('2026-05-02 20:30:00+08', '晚餐后', 5.0),
      ('2026-05-02 22:40:00+08', '睡前', 4.5),
      ('2026-05-03 07:10:00+08', '空腹', 3.7),
      ('2026-05-03 09:30:00+08', '早餐后', 4.4),
      ('2026-05-03 11:30:00+08', '午餐前', 4.2),
      ('2026-05-03 13:50:00+08', '午餐后', 4.6),
      ('2026-05-03 17:30:00+08', '晚餐前', 3.8),
      ('2026-05-03 20:10:00+08', '晚餐后', 4.3),
      ('2026-05-03 22:30:00+08', '睡前', 3.6),
      ('2026-05-04 07:10:00+08', '空腹', 4.1),
      ('2026-05-04 09:30:00+08', '早餐后', 4.9),
      ('2026-05-04 11:30:00+08', '午餐前', 4.5),
      ('2026-05-04 13:50:00+08', '午餐后', 5.0),
      ('2026-05-04 17:30:00+08', '晚餐前', 4.2),
      ('2026-05-04 20:10:00+08', '晚餐后', 4.8),
      ('2026-05-04 22:40:00+08', '睡前', 3.9),
      ('2026-05-05 07:10:00+08', '空腹', 3.5),
      ('2026-05-05 09:30:00+08', '早餐后', 4.1),
      ('2026-05-05 11:30:00+08', '午餐前', 3.8),
      ('2026-05-05 13:50:00+08', '午餐后', 4.2),
      ('2026-05-05 17:30:00+08', '晚餐前', 3.6),
      ('2026-05-05 20:30:00+08', '晚餐后', 4.0),
      ('2026-05-05 22:40:00+08', '睡前', 3.4)
  ) as v(record_time, time_period, value);

  for meal_row in
    select *
    from jsonb_to_recordset($meals$
    [
      {"meal_time":"2026-04-23 18:05:00+08","meal_type":"晚餐","items":[{"name":"番茄","grams":150,"unit":"g","cal":18,"carbs":3.5,"protein":0.9,"fat":0.2,"gi":15},{"name":"鸡蛋","grams":130,"unit":"g","cal":143,"carbs":1.1,"protein":13,"fat":10,"gi":0}]},
      {"meal_time":"2026-04-24 08:20:00+08","meal_type":"早餐","items":[{"name":"拿铁","grams":230,"unit":"ml","cal":60,"carbs":6,"protein":3,"fat":2.5,"gi":45}]},
      {"meal_time":"2026-04-24 12:00:00+08","meal_type":"午餐","items":[{"name":"饭菜","grams":100,"unit":"g","cal":160,"carbs":22,"protein":6,"fat":5,"gi":60}]},
      {"meal_time":"2026-04-24 18:20:00+08","meal_type":"晚餐","items":[{"name":"番茄","grams":150,"unit":"g","cal":18,"carbs":3.5,"protein":0.9,"fat":0.2,"gi":15},{"name":"北京烤鸭","grams":400,"unit":"g","cal":240,"carbs":3,"protein":18,"fat":18,"gi":20}]},
      {"meal_time":"2026-04-24 21:45:00+08","meal_type":"加餐","items":[{"name":"西梅汁","grams":35,"unit":"ml","cal":55,"carbs":13,"protein":0.2,"fat":0,"gi":50}]},
      {"meal_time":"2026-04-25 08:05:00+08","meal_type":"早餐","items":[{"name":"豆浆","grams":250,"unit":"ml","cal":33,"carbs":3.1,"protein":3,"fat":1.8,"gi":30},{"name":"蓝莓","grams":125,"unit":"g","cal":57,"carbs":14,"protein":0.7,"fat":0.3,"gi":53},{"name":"柚见咖啡","grams":300,"unit":"ml","cal":50,"carbs":7,"protein":2,"fat":1.5,"gi":45}]},
      {"meal_time":"2026-04-25 11:25:00+08","meal_type":"午餐","items":[{"name":"沙汤","grams":100,"unit":"g","cal":70,"carbs":8,"protein":4,"fat":2,"gi":50},{"name":"锅贴","grams":100,"unit":"g","cal":230,"carbs":28,"protein":8,"fat":10,"gi":65}]},
      {"meal_time":"2026-04-25 17:30:00+08","meal_type":"晚餐","items":[{"name":"北京烤鸭","grams":400,"unit":"g","cal":240,"carbs":3,"protein":18,"fat":18,"gi":20}]},
      {"meal_time":"2026-04-25 19:35:00+08","meal_type":"加餐","items":[{"name":"西梅汁","grams":100,"unit":"ml","cal":55,"carbs":13,"protein":0.2,"fat":0,"gi":50}]},
      {"meal_time":"2026-04-26 08:08:00+08","meal_type":"早餐","items":[{"name":"茶叶蛋","grams":80,"unit":"g","cal":150,"carbs":1.5,"protein":12,"fat":10,"gi":0}]},
      {"meal_time":"2026-04-26 12:10:00+08","meal_type":"午餐","items":[{"name":"饭菜","grams":100,"unit":"g","cal":160,"carbs":22,"protein":6,"fat":5,"gi":60}]},
      {"meal_time":"2026-04-26 15:50:00+08","meal_type":"加餐","items":[{"name":"面包","grams":200,"unit":"g","cal":265,"carbs":49,"protein":9,"fat":3.2,"gi":75}]},
      {"meal_time":"2026-04-26 19:45:00+08","meal_type":"晚餐","items":[{"name":"北京烤鸭","grams":400,"unit":"g","cal":240,"carbs":3,"protein":18,"fat":18,"gi":20}]},
      {"meal_time":"2026-04-26 21:36:00+08","meal_type":"加餐","items":[{"name":"西梅汁","grams":100,"unit":"ml","cal":55,"carbs":13,"protein":0.2,"fat":0,"gi":50}]},
      {"meal_time":"2026-04-27 08:34:00+08","meal_type":"早餐","items":[{"name":"西梅汁柠檬汁","grams":200,"unit":"ml","cal":45,"carbs":11,"protein":0.2,"fat":0,"gi":45}]},
      {"meal_time":"2026-04-27 11:20:00+08","meal_type":"午餐","items":[{"name":"热干面","grams":400,"unit":"g","cal":210,"carbs":35,"protein":7,"fat":6,"gi":78}]},
      {"meal_time":"2026-04-27 16:12:00+08","meal_type":"加餐","items":[{"name":"碱水面包","grams":30,"unit":"g","cal":260,"carbs":52,"protein":8,"fat":2,"gi":72}]},
      {"meal_time":"2026-04-27 17:00:00+08","meal_type":"晚餐","items":[{"name":"北京烤鸭","grams":400,"unit":"g","cal":240,"carbs":3,"protein":18,"fat":18,"gi":20}]},
      {"meal_time":"2026-04-28 07:50:00+08","meal_type":"早餐","items":[{"name":"牛奶","grams":180,"unit":"ml","cal":54,"carbs":5,"protein":3.2,"fat":3.3,"gi":27}]},
      {"meal_time":"2026-04-28 11:20:00+08","meal_type":"午餐","items":[{"name":"老乡鸡","grams":100,"unit":"g","cal":165,"carbs":4,"protein":18,"fat":8,"gi":30}]},
      {"meal_time":"2026-04-28 17:26:00+08","meal_type":"晚餐","items":[{"name":"北京烤鸭","grams":400,"unit":"g","cal":240,"carbs":3,"protein":18,"fat":18,"gi":20}]},
      {"meal_time":"2026-04-29 08:15:00+08","meal_type":"早餐","items":[{"name":"番茄","grams":120,"unit":"g","cal":18,"carbs":3.5,"protein":0.9,"fat":0.2,"gi":15},{"name":"牛奶","grams":250,"unit":"ml","cal":54,"carbs":5,"protein":3.2,"fat":3.3,"gi":27}]},
      {"meal_time":"2026-04-29 11:20:00+08","meal_type":"午餐","items":[{"name":"热干面","grams":400,"unit":"g","cal":210,"carbs":35,"protein":7,"fat":6,"gi":78},{"name":"番茄","grams":120,"unit":"g","cal":18,"carbs":3.5,"protein":0.9,"fat":0.2,"gi":15}]},
      {"meal_time":"2026-04-29 17:20:00+08","meal_type":"晚餐","items":[{"name":"北京烤鸭","grams":400,"unit":"g","cal":240,"carbs":3,"protein":18,"fat":18,"gi":20}]},
      {"meal_time":"2026-04-30 08:36:00+08","meal_type":"早餐","items":[{"name":"抹茶拿铁","grams":180,"unit":"ml","cal":70,"carbs":9,"protein":3,"fat":2.5,"gi":50}]},
      {"meal_time":"2026-04-30 10:07:00+08","meal_type":"加餐","items":[{"name":"苏打饼干","grams":32,"unit":"g","cal":435,"carbs":72,"protein":9,"fat":12,"gi":72}]},
      {"meal_time":"2026-04-30 11:43:00+08","meal_type":"午餐","items":[{"name":"麻辣烫","grams":100,"unit":"g","cal":120,"carbs":10,"protein":7,"fat":6,"gi":45}]},
      {"meal_time":"2026-04-30 16:10:00+08","meal_type":"加餐","items":[{"name":"粗面大排卤蛋","grams":350,"unit":"g","cal":180,"carbs":22,"protein":12,"fat":6,"gi":65}]},
      {"meal_time":"2026-05-01 08:31:00+08","meal_type":"早餐","items":[{"name":"水果玉米","grams":100,"unit":"g","cal":106,"carbs":22,"protein":3.5,"fat":1.2,"gi":55}]},
      {"meal_time":"2026-05-01 11:15:00+08","meal_type":"午餐","items":[{"name":"北京烤鸭","grams":400,"unit":"g","cal":240,"carbs":3,"protein":18,"fat":18,"gi":20}]},
      {"meal_time":"2026-05-01 15:08:00+08","meal_type":"加餐","items":[{"name":"苏打饼干","grams":32,"unit":"g","cal":435,"carbs":72,"protein":9,"fat":12,"gi":72}]},
      {"meal_time":"2026-05-01 17:00:00+08","meal_type":"晚餐","items":[{"name":"热干面","grams":400,"unit":"g","cal":210,"carbs":35,"protein":7,"fat":6,"gi":78}]},
      {"meal_time":"2026-05-02 08:17:00+08","meal_type":"早餐","items":[{"name":"潘帕斯生酪","grams":100,"unit":"g","cal":300,"carbs":35,"protein":7,"fat":15,"gi":60}]},
      {"meal_time":"2026-05-02 11:35:00+08","meal_type":"午餐","items":[{"name":"热干面","grams":400,"unit":"g","cal":210,"carbs":35,"protein":7,"fat":6,"gi":78}]},
      {"meal_time":"2026-05-02 16:43:00+08","meal_type":"加餐","items":[{"name":"苏打饼干","grams":32,"unit":"g","cal":435,"carbs":72,"protein":9,"fat":12,"gi":72}]},
      {"meal_time":"2026-05-02 19:10:00+08","meal_type":"晚餐","items":[{"name":"泡面","grams":200,"unit":"g","cal":180,"carbs":26,"protein":5,"fat":7,"gi":70}]},
      {"meal_time":"2026-05-03 11:25:00+08","meal_type":"午餐","items":[{"name":"锅贴沙汤","grams":200,"unit":"g","cal":150,"carbs":20,"protein":6,"fat":5,"gi":60}]},
      {"meal_time":"2026-05-03 18:50:00+08","meal_type":"晚餐","items":[{"name":"泡面","grams":200,"unit":"g","cal":180,"carbs":26,"protein":5,"fat":7,"gi":70}]},
      {"meal_time":"2026-05-04 08:28:00+08","meal_type":"早餐","items":[{"name":"烧卖","grams":100,"unit":"g","cal":220,"carbs":32,"protein":8,"fat":7,"gi":67},{"name":"脱脂牛奶","grams":200,"unit":"ml","cal":34,"carbs":5,"protein":3.4,"fat":0.2,"gi":27}]},
      {"meal_time":"2026-05-04 11:35:00+08","meal_type":"午餐","items":[{"name":"泡面","grams":400,"unit":"g","cal":180,"carbs":26,"protein":5,"fat":7,"gi":70}]},
      {"meal_time":"2026-05-04 16:15:00+08","meal_type":"加餐","items":[{"name":"汉堡","grams":100,"unit":"g","cal":250,"carbs":30,"protein":12,"fat":10,"gi":61},{"name":"苏打饼干","grams":32,"unit":"g","cal":435,"carbs":72,"protein":9,"fat":12,"gi":72},{"name":"鸭脖","grams":100,"unit":"g","cal":190,"carbs":5,"protein":18,"fat":11,"gi":20}]},
      {"meal_time":"2026-05-04 22:40:00+08","meal_type":"加餐","items":[{"name":"香蕉","grams":100,"unit":"g","cal":89,"carbs":23,"protein":1.1,"fat":0.3,"gi":52}]},
      {"meal_time":"2026-05-05 08:55:00+08","meal_type":"早餐","items":[{"name":"苏打饼干","grams":32,"unit":"g","cal":435,"carbs":72,"protein":9,"fat":12,"gi":72}]},
      {"meal_time":"2026-05-05 11:34:00+08","meal_type":"午餐","items":[{"name":"饭菜","grams":100,"unit":"g","cal":160,"carbs":22,"protein":6,"fat":5,"gi":60}]}
    ]
    $meals$::jsonb) as x(meal_time text, meal_type text, items jsonb)
  loop
    new_meal_id := gen_random_uuid();
    insert into public.meals (id, user_id, meal_type, meal_time)
    values (new_meal_id, demo_user_id, meal_row.meal_type, meal_row.meal_time::timestamptz);

    for item_row in
      select *
      from jsonb_to_recordset(meal_row.items) as i(
        name text,
        grams numeric,
        unit text,
        cal numeric,
        carbs numeric,
        protein numeric,
        fat numeric,
        gi numeric
      )
    loop
      insert into public.meal_items (
        id,
        meal_id,
        food_name_raw,
        food_name_confirmed,
        calories_raw,
        carbs_raw,
        protein_raw,
        fat_raw,
        gi_value_snapshot,
        portion_size,
        grams,
        serving_unit
      )
      values (
        gen_random_uuid(),
        new_meal_id,
        item_row.name,
        item_row.name,
        item_row.cal,
        item_row.carbs,
        item_row.protein,
        item_row.fat,
        item_row.gi,
        1.0,
        item_row.grams,
        item_row.unit
      );
    end loop;
  end loop;

  insert into public.exercise_logs (
    id,
    user_id,
    exercise_time,
    motion_id,
    duration,
    mets_snapshot,
    calories_burned
  )
  select
    gen_random_uuid(),
    demo_user_id,
    v.exercise_time::timestamptz,
    v.motion_id::uuid,
    v.duration,
    v.mets,
    round(v.mets * demo_weight * v.duration / 60)
  from (
    values
      ('2026-04-23 18:27:00+08', '10000000-0000-4000-8000-000000000011', 2, 8.0),
      ('2026-04-24 10:24:00+08', '10000000-0000-4000-8000-000000000001', 16, 2.0),
      ('2026-04-24 11:06:00+08', '10000000-0000-4000-8000-000000000001', 10, 2.0),
      ('2026-04-24 17:56:00+08', '10000000-0000-4000-8000-000000000011', 2, 8.0),
      ('2026-04-24 19:06:00+08', '10000000-0000-4000-8000-000000000001', 15, 2.0),
      ('2026-04-24 20:30:00+08', '10000000-0000-4000-8000-000000000001', 20, 2.0),
      ('2026-04-25 07:35:00+08', '10000000-0000-4000-8000-000000000001', 10, 2.0),
      ('2026-04-25 09:00:00+08', '10000000-0000-4000-8000-000000000001', 5, 2.0),
      ('2026-04-25 20:40:00+08', '10000000-0000-4000-8000-000000000007', 15, 7.0),
      ('2026-04-27 12:10:00+08', '10000000-0000-4000-8000-000000000001', 5, 2.0),
      ('2026-04-27 19:35:00+08', '10000000-0000-4000-8000-000000000007', 15, 7.0),
      ('2026-04-27 19:36:00+08', '10000000-0000-4000-8000-000000000011', 5, 8.0),
      ('2026-04-28 07:28:00+08', '10000000-0000-4000-8000-000000000001', 5, 2.0),
      ('2026-04-28 19:55:00+08', '10000000-0000-4000-8000-000000000007', 10, 7.0),
      ('2026-05-02 21:05:00+08', '10000000-0000-4000-8000-000000000007', 15, 7.0),
      ('2026-05-04 21:30:00+08', '10000000-0000-4000-8000-000000000007', 15, 7.0),
      ('2026-05-05 20:00:00+08', '10000000-0000-4000-8000-000000000007', 15, 7.0)
  ) as v(exercise_time, motion_id, duration, mets);

  -- The PDF has no subjective status rows. These are demo status records
  -- derived from the daily low-glucose trend so the analysis page can show
  -- diet/exercise/status associations.
  insert into public.wellness_status (
    id,
    user_id,
    status_level,
    notes,
    record_time
  )
  select
    gen_random_uuid(),
    demo_user_id,
    v.status_level,
    v.notes,
    v.record_time::timestamptz
  from (
    values
      ('2026-04-23 22:00:00+08', '状态平稳', '晚餐后整体平稳。'),
      ('2026-04-24 22:00:00+08', '感觉不错', '晚饭后散步，状态比较轻松。'),
      ('2026-04-25 22:00:00+08', '感觉不错', '早餐和午餐后有步行，精力较好。'),
      ('2026-04-26 22:00:00+08', '状态平稳', '白天饮食记录完整，整体平稳。'),
      ('2026-04-27 22:00:00+08', '状态平稳', '主食较多，饭后有轻运动。'),
      ('2026-04-28 22:00:00+08', '感觉不错', '晚饭后慢跑，状态尚可。'),
      ('2026-04-29 22:00:00+08', '状态平稳', '全天波动不大。'),
      ('2026-04-30 22:00:00+08', '状态平稳', '加餐较多，建议继续观察饥饿感。'),
      ('2026-05-01 22:00:00+08', '略感疲惫', '睡前血糖偏低，下午后容易疲劳。'),
      ('2026-05-02 22:00:00+08', '状态平稳', '晚饭后慢跑，状态恢复尚可。'),
      ('2026-05-03 22:00:00+08', '略感疲惫', '全天偏低时段较多，容易犯困。'),
      ('2026-05-04 22:00:00+08', '略感疲惫', '下午加餐较集中，晚间略疲惫。'),
      ('2026-05-05 22:00:00+08', '极度疲劳', '多次读数偏低，适合演示低血糖趋势提醒。')
  ) as v(record_time, status_level, notes);

  raise notice 'Demo data imported for %, user_id=%', demo_email, demo_user_id;
end $$;
