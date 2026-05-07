grant usage on schema public to service_role;

grant select on table
  public.user_profile,
  public.user_body_metrics,
  public.meals,
  public.meal_items,
  public.exercise_catalog,
  public.exercise_logs,
  public.blood_glucose_logs,
  public.wellness_status,
  public.glucose_normalized
to service_role;

do $$
begin
  if to_regprocedure('public.get_daily_glucose_stats(date,date,text)') is not null then
    grant execute on function public.get_daily_glucose_stats(date, date, text) to service_role;
  end if;

  if to_regprocedure('public.get_weekly_glucose_summary(date,date,text)') is not null then
    grant execute on function public.get_weekly_glucose_summary(date, date, text) to service_role;
  end if;

  if to_regprocedure('public.get_meal_glucose_response(date,date,text)') is not null then
    grant execute on function public.get_meal_glucose_response(date, date, text) to service_role;
  end if;

  if to_regprocedure('public.get_food_impact_stats(date,date,text)') is not null then
    grant execute on function public.get_food_impact_stats(date, date, text) to service_role;
  end if;

  if to_regprocedure('public.get_energy_correlation(date,date,text)') is not null then
    grant execute on function public.get_energy_correlation(date, date, text) to service_role;
  end if;
end $$;

notify pgrst, 'reload schema';
