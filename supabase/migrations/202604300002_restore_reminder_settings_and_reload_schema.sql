create extension if not exists "pgcrypto";

create table if not exists public.reminder_settings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  time_of_day text not null,
  enabled boolean not null default true,
  label text,
  created_at timestamptz default now()
);

create index if not exists idx_reminders_user_time
on public.reminder_settings(user_id, time_of_day);

alter table public.reminder_settings enable row level security;

drop policy if exists "reminders_own_rows" on public.reminder_settings;
create policy "reminders_own_rows" on public.reminder_settings
  for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant select, insert, update, delete on public.reminder_settings to authenticated;
grant usage, select on all sequences in schema public to authenticated;

insert into public.reminder_settings (
  user_id,
  time_of_day,
  enabled,
  label
)
select users.id, default_rows.time_of_day, true, default_rows.label
from auth.users as users
cross join (
  values
    ('08:30', '早餐后记录'),
    ('13:30', '午餐后记录'),
    ('20:30', '晚间回看')
) as default_rows(time_of_day, label)
where not exists (
  select 1
  from public.reminder_settings
  where reminder_settings.user_id = users.id
);

notify pgrst, 'reload schema';
