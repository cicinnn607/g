grant usage on schema public to authenticated;

grant select, insert, update, delete on table
  public.user_profile,
  public.user_body_metrics,
  public.meals,
  public.meal_items,
  public.exercise_logs,
  public.blood_glucose_logs,
  public.wellness_status,
  public.reminder_settings
to authenticated;

grant select on table public.exercise_catalog to authenticated;

grant usage, select on all sequences in schema public to authenticated;

alter default privileges in schema public
grant usage, select on sequences to authenticated;

notify pgrst, 'reload schema';
