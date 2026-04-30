create extension if not exists "pgcrypto";

create table if not exists public.user_profile (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  gender text,
  height numeric,
  birth_date date,
  created_at timestamptz default now()
);

create table if not exists public.user_body_metrics (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  weight numeric not null check (weight > 0),
  record_time timestamptz not null,
  created_at timestamptz default now()
);

create table if not exists public.exercise_catalog (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  met_value numeric not null check (met_value > 0),
  category text,
  description text
);

create table if not exists public.meals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  meal_type text not null check (meal_type in ('早餐', '午餐', '晚餐', '加餐')),
  meal_time timestamptz not null,
  created_at timestamptz default now()
);

create table if not exists public.meal_items (
  id uuid primary key default gen_random_uuid(),
  meal_id uuid not null references public.meals(id) on delete cascade,
  food_name_raw text,
  food_name_confirmed text,
  calories_raw numeric check (calories_raw >= 0),
  portion_size numeric not null default 1.0 check (portion_size between 0.5 and 2.0),
  calories_final numeric generated always as (
    coalesce(calories_raw, 0) * portion_size
  ) stored,
  image_url text,
  created_at timestamptz default now()
);

create table if not exists public.exercise_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  exercise_time timestamptz not null,
  motion_id uuid references public.exercise_catalog(id),
  duration integer not null check (duration > 0),
  mets_snapshot numeric,
  calories_burned numeric,
  created_at timestamptz default now()
);

create table if not exists public.blood_glucose_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  record_time timestamptz not null,
  time_period text check (time_period in (
    '空腹', '早餐后', '午餐前', '午餐后', '晚餐前', '晚餐后', '睡前', '凌晨', '随机'
  )),
  value numeric not null check (value >= 0.6 and value <= 33.3),
  unit text default 'mmol/L' check (unit in ('mmol/L', 'mg/dL')),
  source text default 'manual' check (source in ('manual', 'cgm')),
  created_at timestamptz default now()
);

create table if not exists public.wellness_status (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  status_level text check (
    status_level in ('极度疲劳', '略感疲惫', '状态平稳', '感觉不错', '精力充沛')
  ),
  notes text,
  record_time timestamptz not null,
  related_meal_id uuid references public.meals(id) on delete set null,
  related_exercise_id uuid references public.exercise_logs(id) on delete set null,
  created_at timestamptz default now()
);

create table if not exists public.reminder_settings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  time_of_day text not null,
  enabled boolean not null default true,
  label text,
  created_at timestamptz default now()
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_profile (
    id,
    display_name,
    gender,
    height,
    birth_date
  )
  values (
    new.id,
    coalesce(
      nullif(new.raw_user_meta_data->>'display_name', ''),
      nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
      '稳稳'
    ),
    '男',
    170.0,
    make_date((extract(year from now())::int - 23), 1, 1)
  )
  on conflict (id) do nothing;

  insert into public.user_body_metrics (
    user_id,
    weight,
    record_time
  )
  select new.id, 65.0, now()
  where not exists (
    select 1
    from public.user_body_metrics
    where user_body_metrics.user_id = new.id
  );

  insert into public.reminder_settings (
    user_id,
    time_of_day,
    enabled,
    label
  )
  select new.id, default_rows.time_of_day, true, default_rows.label
  from (
    values
      ('08:30', '早餐后记录'),
      ('13:30', '午餐后记录'),
      ('20:30', '晚间回看')
  ) as default_rows(time_of_day, label)
  where not exists (
    select 1
    from public.reminder_settings
    where reminder_settings.user_id = new.id
  );

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

create index if not exists idx_meals_user_time
on public.meals(user_id, meal_time desc);

create index if not exists idx_meal_items_meal
on public.meal_items(meal_id);

create index if not exists idx_exercise_user_time
on public.exercise_logs(user_id, exercise_time desc);

create index if not exists idx_glucose_user_time
on public.blood_glucose_logs(user_id, record_time desc);

create index if not exists idx_status_user_time
on public.wellness_status(user_id, record_time desc);

create index if not exists idx_body_metrics_user_time
on public.user_body_metrics(user_id, record_time desc);

create index if not exists idx_reminders_user_time
on public.reminder_settings(user_id, time_of_day);

insert into public.exercise_catalog (id, name, met_value, category, description)
values
  ('10000000-0000-4000-8000-000000000001', '缓慢步行 (<4km/h)', 2.0, '低强度', '散步、逛街等非常轻松的走动'),
  ('10000000-0000-4000-8000-000000000002', '做家务 (轻度)', 2.5, '低强度', '擦桌子、整理杂物、洗碗'),
  ('10000000-0000-4000-8000-000000000003', '做家务 (重度)', 3.5, '中等强度', '拖地、搬动家具、擦窗户'),
  ('10000000-0000-4000-8000-000000000004', '园艺/种花', 3.8, '中等强度', '修剪植物、除草'),
  ('10000000-0000-4000-8000-000000000005', '站立办公/工作', 1.8, '低强度', '不需要大幅度移动的站立工作'),
  ('10000000-0000-4000-8000-000000000006', '快走 (6km/h)', 4.5, '中等强度', '有一定节奏的快速步行'),
  ('10000000-0000-4000-8000-000000000007', '慢跑 (8km/h)', 7.0, '中等强度', '初学者常见的跑步速度'),
  ('10000000-0000-4000-8000-000000000008', '中速跑 (10km/h)', 9.8, '高强度', '标准的健身跑步速度'),
  ('10000000-0000-4000-8000-000000000009', '快速跑 (12km/h)', 11.5, '高强度', '较高强度的长跑'),
  ('10000000-0000-4000-8000-000000000010', '极速冲刺 (16km/h)', 14.5, '高强度', '短距离冲刺或间歇跑'),
  ('10000000-0000-4000-8000-000000000011', '上下楼梯', 8.0, '高强度', '爬楼梯锻炼'),
  ('10000000-0000-4000-8000-000000000012', '休闲骑行 (<16km/h)', 4.0, '中等强度', '慢速骑车去超市或兜风'),
  ('10000000-0000-4000-8000-000000000013', '健身房动感单车', 8.5, '高强度', '高频率、有节奏的室内单车'),
  ('10000000-0000-4000-8000-000000000014', '竞技骑行 (>20km/h)', 10.5, '高强度', '公路车快速骑行'),
  ('10000000-0000-4000-8000-000000000015', '休闲游泳 (蛙泳/慢速)', 5.8, '中等强度', '不间断的轻松游泳'),
  ('10000000-0000-4000-8000-000000000016', '竞速游泳 (自由泳/快速)', 9.5, '高强度', '高频率的往返游泳'),
  ('10000000-0000-4000-8000-000000000017', '羽毛球 (休闲)', 4.5, '中等强度', '公园里的双打或练习'),
  ('10000000-0000-4000-8000-000000000018', '羽毛球 (竞技)', 7.0, '中等强度', '有强度的比赛'),
  ('10000000-0000-4000-8000-000000000019', '乒乓球', 4.0, '中等强度', '持续的对练'),
  ('10000000-0000-4000-8000-000000000020', '网球 (单打)', 8.0, '高强度', '全场跑动的竞技'),
  ('10000000-0000-4000-8000-000000000021', '篮球 (投篮练习)', 4.5, '中等强度', '半场定点投篮'),
  ('10000000-0000-4000-8000-000000000022', '篮球 (正式比赛)', 9.0, '高强度', '全场高强度的对抗'),
  ('10000000-0000-4000-8000-000000000023', '足球 (正式比赛)', 10.0, '高强度', '大面积跑动的竞技'),
  ('10000000-0000-4000-8000-000000000024', '基础瑜伽/普拉提', 3.0, '低强度', '拉伸与呼吸训练'),
  ('10000000-0000-4000-8000-000000000025', '力量训练 (轻重量)', 3.5, '中等强度', '哑铃操或小重量塑形'),
  ('10000000-0000-4000-8000-000000000026', '力量训练 (大重量)', 6.0, '中等强度', '深蹲、硬拉等核心力量训练'),
  ('10000000-0000-4000-8000-000000000027', 'HIIT/波比跳', 11.0, '高强度', '高强度间歇训练'),
  ('10000000-0000-4000-8000-000000000028', '跳绳 (慢速)', 8.0, '高强度', '约 100 次/分钟'),
  ('10000000-0000-4000-8000-000000000029', '跳绳 (快速)', 12.0, '高强度', '约 120-160 次/分钟'),
  ('10000000-0000-4000-8000-000000000030', '划船机 (中等强度)', 7.0, '中等强度', '全身协调有氧训练')
on conflict (id) do update set
  name = excluded.name,
  met_value = excluded.met_value,
  category = excluded.category,
  description = excluded.description;

alter table public.user_profile enable row level security;
alter table public.user_body_metrics enable row level security;
alter table public.exercise_catalog enable row level security;
alter table public.meals enable row level security;
alter table public.meal_items enable row level security;
alter table public.exercise_logs enable row level security;
alter table public.blood_glucose_logs enable row level security;
alter table public.wellness_status enable row level security;
alter table public.reminder_settings enable row level security;

drop policy if exists "profile_select_own" on public.user_profile;
create policy "profile_select_own" on public.user_profile
  for select using (auth.uid() = id);

drop policy if exists "profile_insert_own" on public.user_profile;
create policy "profile_insert_own" on public.user_profile
  for insert with check (auth.uid() = id);

drop policy if exists "profile_update_own" on public.user_profile;
create policy "profile_update_own" on public.user_profile
  for update using (auth.uid() = id)
  with check (auth.uid() = id);

drop policy if exists "profile_delete_own" on public.user_profile;
create policy "profile_delete_own" on public.user_profile
  for delete using (auth.uid() = id);

drop policy if exists "metrics_own_rows" on public.user_body_metrics;
create policy "metrics_own_rows" on public.user_body_metrics
  for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "meals_own_rows" on public.meals;
create policy "meals_own_rows" on public.meals
  for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "meal_items_own_rows" on public.meal_items;
create policy "meal_items_own_rows" on public.meal_items
  for all using (
    exists (
      select 1 from public.meals
      where meals.id = meal_items.meal_id
      and meals.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.meals
      where meals.id = meal_items.meal_id
      and meals.user_id = auth.uid()
    )
  );

drop policy if exists "glucose_own_rows" on public.blood_glucose_logs;
create policy "glucose_own_rows" on public.blood_glucose_logs
  for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "status_own_rows" on public.wellness_status;
create policy "status_own_rows" on public.wellness_status
  for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "exercise_logs_own_rows" on public.exercise_logs;
create policy "exercise_logs_own_rows" on public.exercise_logs
  for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "reminders_own_rows" on public.reminder_settings;
create policy "reminders_own_rows" on public.reminder_settings
  for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "catalog_read_authenticated" on public.exercise_catalog;
create policy "catalog_read_authenticated" on public.exercise_catalog
  for select using (auth.role() = 'authenticated');

drop policy if exists "catalog_no_insert" on public.exercise_catalog;
create policy "catalog_no_insert" on public.exercise_catalog
  for insert with check (false);

drop policy if exists "catalog_no_update" on public.exercise_catalog;
create policy "catalog_no_update" on public.exercise_catalog
  for update using (false)
  with check (false);

drop policy if exists "catalog_no_delete" on public.exercise_catalog;
create policy "catalog_no_delete" on public.exercise_catalog
  for delete using (false);

insert into storage.buckets (id, name, public)
values ('meal-images', 'meal-images', false)
on conflict (id) do update set public = false;

drop policy if exists "meal_images_select_own" on storage.objects;
create policy "meal_images_select_own" on storage.objects
  for select using (
    bucket_id = 'meal-images'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "meal_images_insert_own" on storage.objects;
create policy "meal_images_insert_own" on storage.objects
  for insert with check (
    bucket_id = 'meal-images'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "meal_images_update_own" on storage.objects;
create policy "meal_images_update_own" on storage.objects
  for update using (
    bucket_id = 'meal-images'
    and auth.uid()::text = (storage.foldername(name))[1]
  )
  with check (
    bucket_id = 'meal-images'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "meal_images_delete_own" on storage.objects;
create policy "meal_images_delete_own" on storage.objects
  for delete using (
    bucket_id = 'meal-images'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
