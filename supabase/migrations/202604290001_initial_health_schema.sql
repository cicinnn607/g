create extension if not exists pgcrypto;

create table if not exists public.user_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '稳稳',
  gender text,
  height double precision,
  birth_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_body_metrics (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  weight double precision not null check (weight > 0),
  record_time timestamptz not null,
  created_at timestamptz not null default now()
);

create table if not exists public.blood_glucose (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  record_time timestamptz not null,
  time_period text not null check (time_period in ('空腹', '早餐后', '午餐前', '午餐后', '晚餐前', '晚餐后', '睡前', '凌晨', '随机')),
  value double precision not null check (value between 0.6 and 33.3),
  unit text not null default 'mmol/L' check (unit in ('mmol/L', 'mg/dL')),
  source text not null default 'manual' check (source in ('manual', 'cgm')),
  created_at timestamptz not null default now()
);

create table if not exists public.meals (
  meal_id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  meal_type text not null check (meal_type in ('早餐', '午餐', '晚餐', '加餐')),
  meal_time timestamptz not null,
  created_at timestamptz not null default now()
);

create table if not exists public.meal_items (
  id uuid primary key default gen_random_uuid(),
  meal_id uuid not null references public.meals(meal_id) on delete cascade,
  food_name_raw text,
  food_name_confirmed text not null,
  calories_raw double precision not null default 0,
  portion_size double precision not null default 1.0 check (portion_size between 0.5 and 2.0),
  calories_final double precision not null default 0,
  image_url text,
  created_at timestamptz not null default now()
);

create table if not exists public.exercise_catalog (
  id text primary key,
  name text not null,
  met_value double precision not null check (met_value > 0),
  category text,
  description text
);

create table if not exists public.exercise_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  exercise_time timestamptz not null,
  motion_id text not null references public.exercise_catalog(id),
  duration integer not null check (duration > 0),
  mets double precision not null check (mets > 0),
  calories_burned double precision not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.wellness_status (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  status_level text not null check (status_level in ('极度疲劳', '略感疲惫', '状态平稳', '感觉不错', '精力充沛')),
  record_time timestamptz not null,
  notes text,
  related_meal_id uuid references public.meals(meal_id) on delete set null,
  related_exercise_id uuid references public.exercise_logs(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.reminder_settings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  time_of_day text not null,
  enabled boolean not null default true,
  label text,
  created_at timestamptz not null default now()
);

insert into public.exercise_catalog (id, name, met_value, category, description)
values
  ('walk_slow', '慢走', 2.8, '低强度', '饭后轻松走一走'),
  ('walk_fast', '快走', 4.3, '中等强度', '能说话但略喘'),
  ('jog', '慢跑', 7.0, '有氧', '稳定节奏跑步'),
  ('bike', '骑行', 6.0, '有氧', '中等速度骑行'),
  ('yoga', '瑜伽', 3.0, '舒缓', '轻柔拉伸和呼吸'),
  ('strength', '力量训练', 5.0, '抗阻', '自重或器械训练'),
  ('swim', '游泳', 7.0, '有氧', '连续游泳'),
  ('hiit', 'HIIT', 8.0, '高强度', '间歇训练')
on conflict (id) do update set
  name = excluded.name,
  met_value = excluded.met_value,
  category = excluded.category,
  description = excluded.description;

alter table public.user_profiles enable row level security;
alter table public.user_body_metrics enable row level security;
alter table public.blood_glucose enable row level security;
alter table public.meals enable row level security;
alter table public.meal_items enable row level security;
alter table public.exercise_catalog enable row level security;
alter table public.exercise_logs enable row level security;
alter table public.wellness_status enable row level security;
alter table public.reminder_settings enable row level security;

drop policy if exists "profiles own rows" on public.user_profiles;
create policy "profiles own rows" on public.user_profiles
  for all using (auth.uid() = id)
  with check (auth.uid() = id);

drop policy if exists "body metrics own rows" on public.user_body_metrics;
create policy "body metrics own rows" on public.user_body_metrics
  for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "blood glucose own rows" on public.blood_glucose;
create policy "blood glucose own rows" on public.blood_glucose
  for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "meals own rows" on public.meals;
create policy "meals own rows" on public.meals
  for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "meal items own rows" on public.meal_items;
create policy "meal items own rows" on public.meal_items
  for all using (
    exists (
      select 1 from public.meals
      where meals.meal_id = meal_items.meal_id
      and meals.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.meals
      where meals.meal_id = meal_items.meal_id
      and meals.user_id = auth.uid()
    )
  );

drop policy if exists "exercise catalog readable" on public.exercise_catalog;
create policy "exercise catalog readable" on public.exercise_catalog
  for select using (auth.role() = 'authenticated');

drop policy if exists "exercise logs own rows" on public.exercise_logs;
create policy "exercise logs own rows" on public.exercise_logs
  for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "wellness own rows" on public.wellness_status;
create policy "wellness own rows" on public.wellness_status
  for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "reminders own rows" on public.reminder_settings;
create policy "reminders own rows" on public.reminder_settings
  for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

insert into storage.buckets (id, name, public)
values ('meal-images', 'meal-images', false)
on conflict (id) do update set public = false;

drop policy if exists "meal images select own" on storage.objects;
create policy "meal images select own" on storage.objects
  for select using (
    bucket_id = 'meal-images'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "meal images insert own" on storage.objects;
create policy "meal images insert own" on storage.objects
  for insert with check (
    bucket_id = 'meal-images'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "meal images update own" on storage.objects;
create policy "meal images update own" on storage.objects
  for update using (
    bucket_id = 'meal-images'
    and auth.uid()::text = (storage.foldername(name))[1]
  )
  with check (
    bucket_id = 'meal-images'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "meal images delete own" on storage.objects;
create policy "meal images delete own" on storage.objects
  for delete using (
    bucket_id = 'meal-images'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
