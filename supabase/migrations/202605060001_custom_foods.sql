create table if not exists public.custom_foods (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  calories_per_100g numeric not null check (calories_per_100g >= 0),
  carbs_per_100g numeric check (carbs_per_100g is null or carbs_per_100g >= 0),
  protein_per_100g numeric check (protein_per_100g is null or protein_per_100g >= 0),
  fat_per_100g numeric check (fat_per_100g is null or fat_per_100g >= 0),
  gi_value numeric check (gi_value is null or gi_value between 0 and 100),
  serving_options jsonb not null default '{}'::jsonb,
  source text not null default 'custom',
  is_ai_generated boolean not null default false,
  confidence numeric check (confidence is null or confidence between 0 and 1),
  created_at timestamptz not null default now()
);

alter table public.custom_foods
  add column if not exists carbs_per_100g numeric check (carbs_per_100g is null or carbs_per_100g >= 0),
  add column if not exists protein_per_100g numeric check (protein_per_100g is null or protein_per_100g >= 0),
  add column if not exists fat_per_100g numeric check (fat_per_100g is null or fat_per_100g >= 0),
  add column if not exists gi_value numeric check (gi_value is null or gi_value between 0 and 100),
  add column if not exists serving_options jsonb not null default '{}'::jsonb,
  add column if not exists source text not null default 'custom',
  add column if not exists is_ai_generated boolean not null default false,
  add column if not exists confidence numeric check (confidence is null or confidence between 0 and 1);

create index if not exists idx_custom_foods_user_created
on public.custom_foods(user_id, created_at desc);

create index if not exists idx_custom_foods_user_name
on public.custom_foods(user_id, name);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'custom_foods_user_name_key'
      and conrelid = 'public.custom_foods'::regclass
  ) then
    alter table public.custom_foods
      add constraint custom_foods_user_name_key unique (user_id, name);
  end if;
end $$;

alter table public.custom_foods enable row level security;

drop policy if exists "custom_foods_own_rows" on public.custom_foods;
create policy "custom_foods_own_rows" on public.custom_foods
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant select, insert, update, delete on public.custom_foods to authenticated;

notify pgrst, 'reload schema';
