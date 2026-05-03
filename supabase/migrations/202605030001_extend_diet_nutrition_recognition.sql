alter table public.food_calorie_catalog
  add column if not exists carbs_per_100g numeric check (carbs_per_100g is null or carbs_per_100g >= 0),
  add column if not exists protein_per_100g numeric check (protein_per_100g is null or protein_per_100g >= 0),
  add column if not exists fat_per_100g numeric check (fat_per_100g is null or fat_per_100g >= 0),
  add column if not exists gi_value numeric check (gi_value is null or gi_value between 0 and 100),
  add column if not exists is_ai_generated boolean not null default false,
  add column if not exists confidence numeric check (confidence is null or confidence between 0 and 1);

alter table public.food_calorie_catalog
  alter column source set default 'system';

update public.food_calorie_catalog
set source = 'seed'
where source is null;

alter table public.meal_items
  add column if not exists carbs_raw numeric check (carbs_raw is null or carbs_raw >= 0),
  add column if not exists protein_raw numeric check (protein_raw is null or protein_raw >= 0),
  add column if not exists fat_raw numeric check (fat_raw is null or fat_raw >= 0),
  add column if not exists gi_value_snapshot numeric check (
    gi_value_snapshot is null or gi_value_snapshot between 0 and 100
  );

alter table public.meal_items
  drop column if exists carbs_final;

alter table public.meal_items
  add column carbs_final numeric generated always as (
    coalesce(carbs_raw, 0) * coalesce(grams, 0) / 100
  ) stored;

drop function if exists public.search_food_calorie_catalog(text, integer);

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
  carbs_per_100g numeric,
  protein_per_100g numeric,
  fat_per_100g numeric,
  gi_value numeric,
  is_ai_generated boolean,
  confidence numeric,
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
      catalog.carbs_per_100g,
      catalog.protein_per_100g,
      catalog.fat_per_100g,
      catalog.gi_value,
      catalog.is_ai_generated,
      catalog.confidence,
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
to authenticated, service_role;

grant select, insert on public.food_calorie_catalog to service_role;

notify pgrst, 'reload schema';
