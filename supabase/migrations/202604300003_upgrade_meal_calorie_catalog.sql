create extension if not exists "pg_trgm";

create table if not exists public.food_calorie_catalog (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  aliases text[] not null default '{}',
  calories_per_100g numeric not null check (calories_per_100g >= 0),
  serving_options jsonb not null default '{}'::jsonb,
  category text,
  source text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create unique index if not exists food_calorie_catalog_name_key
on public.food_calorie_catalog(name);

create index if not exists idx_food_catalog_name_trgm
on public.food_calorie_catalog
using gin (name gin_trgm_ops);

create index if not exists idx_food_catalog_aliases_gin
on public.food_calorie_catalog
using gin (aliases);

alter table public.food_calorie_catalog enable row level security;

drop policy if exists "food_catalog_read_authenticated" on public.food_calorie_catalog;
create policy "food_catalog_read_authenticated" on public.food_calorie_catalog
  for select using (auth.role() = 'authenticated');

drop policy if exists "food_catalog_no_insert" on public.food_calorie_catalog;
create policy "food_catalog_no_insert" on public.food_calorie_catalog
  for insert with check (false);

drop policy if exists "food_catalog_no_update" on public.food_calorie_catalog;
create policy "food_catalog_no_update" on public.food_calorie_catalog
  for update using (false)
  with check (false);

drop policy if exists "food_catalog_no_delete" on public.food_calorie_catalog;
create policy "food_catalog_no_delete" on public.food_calorie_catalog
  for delete using (false);

grant select on public.food_calorie_catalog to authenticated;

create or replace function public.search_food_calorie_catalog(
  query_text text,
  result_limit integer default 8
)
returns table (
  id uuid,
  name text,
  aliases text[],
  calories_per_100g numeric,
  serving_options jsonb,
  category text,
  source text,
  similarity_score real
)
language sql
stable
security invoker
set search_path = public
as $$
  with normalized as (
    select nullif(trim(query_text), '') as q
  ),
  candidates as (
    select
      catalog.id,
      catalog.name,
      catalog.aliases,
      catalog.calories_per_100g,
      catalog.serving_options,
      catalog.category,
      catalog.source,
      greatest(
        similarity(catalog.name, normalized.q),
        coalesce((
          select max(similarity(alias_value, normalized.q))
          from unnest(catalog.aliases) as alias_value
        ), 0)
      ) as similarity_score
    from public.food_calorie_catalog as catalog
    cross join normalized
    where normalized.q is not null
      and (
        catalog.name ilike '%' || normalized.q || '%'
        or normalized.q ilike '%' || catalog.name || '%'
        or catalog.name % normalized.q
        or exists (
          select 1
          from unnest(catalog.aliases) as alias_value
          where alias_value ilike '%' || normalized.q || '%'
            or normalized.q ilike '%' || alias_value || '%'
            or alias_value % normalized.q
        )
      )
  )
  select *
  from candidates
  order by similarity_score desc, length(name), name
  limit greatest(1, least(coalesce(result_limit, 8), 20));
$$;

grant execute on function public.search_food_calorie_catalog(text, integer)
to authenticated;

insert into public.food_calorie_catalog (
  name,
  aliases,
  calories_per_100g,
  serving_options,
  category,
  source
)
values
  ('米饭', array['白米饭', '蒸米饭', '大米饭'], 116, '{"1标准碗":150,"半碗":75,"1口":15}'::jsonb, '主食', 'seed'),
  ('燕麦粥', array['燕麦', '麦片粥'], 68, '{"1碗":250,"半碗":125,"1勺":30}'::jsonb, '主食', 'seed'),
  ('全麦面包', array['全麦吐司', '吐司'], 246, '{"1片":35,"2片":70,"半片":18}'::jsonb, '主食', 'seed'),
  ('面条', array['汤面', '拌面', '挂面'], 110, '{"1碗":250,"半碗":125,"1小碗":180}'::jsonb, '主食', 'seed'),
  ('水煮蛋', array['煮鸡蛋', '鸡蛋', '白煮蛋'], 151, '{"1个":55,"半个":28,"2个":110}'::jsonb, '蛋白质', 'seed'),
  ('鸡胸肉', array['鸡胸', '鸡肉'], 133, '{"1掌心":100,"半掌心":50,"1块":120}'::jsonb, '蛋白质', 'seed'),
  ('煎牛排', array['牛排', '牛肉排', '煎牛肉'], 180, '{"1掌心":100,"半掌心":50,"1块":150}'::jsonb, '蛋白质', 'seed'),
  ('豆腐', array['嫩豆腐', '老豆腐'], 84, '{"半盒":150,"1块":100,"1口":20}'::jsonb, '蛋白质', 'seed'),
  ('西兰花', array[' broccoli ', '绿花菜'], 34, '{"1小碗":100,"半碗":50,"1朵":20}'::jsonb, '蔬菜', 'seed'),
  ('苹果', array['红苹果', '青苹果'], 53, '{"1个":180,"半个":90,"1片":30}'::jsonb, '水果', 'seed'),
  ('香蕉', array['蕉'], 93, '{"1根":120,"半根":60,"1口":20}'::jsonb, '水果', 'seed'),
  ('奶茶', array['珍珠奶茶', '甜奶茶'], 52, '{"1杯":500,"半杯":250,"1口":30}'::jsonb, '饮品', 'seed')
on conflict (name) do update set
  aliases = excluded.aliases,
  calories_per_100g = excluded.calories_per_100g,
  serving_options = excluded.serving_options,
  category = excluded.category,
  source = excluded.source,
  updated_at = now();

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'meal_items'
      and column_name = 'calories_final'
      and is_generated = 'ALWAYS'
  ) then
    alter table public.meal_items
      add column if not exists grams numeric default 0 check (grams >= 0),
      add column if not exists serving_unit text default 'g',
      add column if not exists calories_user_override numeric check (calories_user_override >= 0);

    execute 'update public.meal_items
      set calories_user_override = calories_final
      where calories_user_override is null
        and calories_final is not null';

    alter table public.meal_items drop column calories_final;
    alter table public.meal_items
      add column calories_final numeric generated always as (
        coalesce(
          calories_user_override,
          coalesce(calories_raw, 0) * coalesce(grams, 0) / 100,
          0
        )
      ) stored;
  else
    alter table public.meal_items
      add column if not exists grams numeric default 0 check (grams >= 0),
      add column if not exists serving_unit text default 'g',
      add column if not exists calories_user_override numeric check (calories_user_override >= 0);
  end if;
end $$;

comment on column public.meal_items.calories_raw is 'Calories per 100g. Baidu dish recognition calorie maps directly here.';
comment on column public.meal_items.grams is 'Actual recorded food weight in grams.';
comment on column public.meal_items.serving_unit is 'Selected serving label such as 1标准碗, or g for manual grams.';
comment on column public.meal_items.calories_user_override is 'User-entered final calories. When set, calories_final uses this value.';

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

grant select, insert, update, delete on table
  public.meals,
  public.meal_items
to authenticated;

grant usage, select on all sequences in schema public to authenticated;

notify pgrst, 'reload schema';
