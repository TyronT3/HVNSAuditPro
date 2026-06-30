-- Notification run log.
-- Records what each daily notification run found so runs can be audited
-- and emails can be tracked once Resend is wired up.
create table if not exists public.notification_log (
  id                  bigserial primary key,
  run_at              timestamptz not null default now(),
  overdue_count       int         not null default 0,
  near_budget_count   int         not null default 0,
  over_budget_count   int         not null default 0,
  payload             jsonb,
  emails_sent         boolean     not null default false,
  created_at          timestamptz not null default now()
);

alter table public.notification_log enable row level security;

create policy "notification_log_super_admin"
  on public.notification_log
  for all
  using (public.is_tyron());

-- To schedule this edge function run once Resend is integrated:
-- Supabase dashboard → Edge Functions → notifications-daily → Schedule
-- Cron: 0 6 * * *  (06:00 UTC = 08:00 SAST)
