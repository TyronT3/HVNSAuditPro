-- GreatSoft time-entry integration scaffold.
-- Additive only: nullable columns and new tracking tables so the current app
-- continues to work unchanged until the frontend is deliberately wired in.

alter table public.users
  add column if not exists greatsoft_emp_id uuid,
  add column if not exists greatsoft_emp_code text,
  add column if not exists greatsoft_sync_enabled boolean not null default false;

alter table public.audits
  add column if not exists greatsoft_client_code text,
  add column if not exists greatsoft_client_name text;

alter table public.sections
  add column if not exists greatsoft_task_id uuid,
  add column if not exists greatsoft_task_code text,
  add column if not exists greatsoft_task_name text;

alter table public.subsections
  add column if not exists greatsoft_act_ovh_id uuid,
  add column if not exists greatsoft_activity_code text,
  add column if not exists greatsoft_activity_name text;

create table if not exists public.greatsoft_time_pushes (
  id uuid primary key default gen_random_uuid(),
  step_log_id uuid not null references public.step_logs(id) on delete cascade,
  submitted_by uuid references public.users(id),
  submitted_by_email text,
  greatsoft_wip_tran_det_id uuid,
  status text not null default 'pending',
  request_payload jsonb,
  response_payload jsonb,
  error_message text,
  pushed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint greatsoft_time_pushes_status_check
    check (status in ('pending', 'pushed', 'failed', 'skipped'))
);

create unique index if not exists greatsoft_time_pushes_step_log_id_uq
  on public.greatsoft_time_pushes(step_log_id);

create index if not exists greatsoft_time_pushes_status_idx
  on public.greatsoft_time_pushes(status);

create index if not exists greatsoft_time_pushes_submitted_by_idx
  on public.greatsoft_time_pushes(submitted_by);

create or replace function public.set_greatsoft_time_pushes_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_greatsoft_time_pushes_updated_at
  on public.greatsoft_time_pushes;

create trigger set_greatsoft_time_pushes_updated_at
before update on public.greatsoft_time_pushes
for each row
execute function public.set_greatsoft_time_pushes_updated_at();

alter table public.greatsoft_time_pushes enable row level security;

drop policy if exists "Managers can read all GreatSoft push rows"
  on public.greatsoft_time_pushes;
create policy "Managers can read all GreatSoft push rows"
on public.greatsoft_time_pushes
for select
using (
  exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.role in ('manager', 'director')
      and u.active = true
  )
);

drop policy if exists "Users can read own GreatSoft push rows"
  on public.greatsoft_time_pushes;
create policy "Users can read own GreatSoft push rows"
on public.greatsoft_time_pushes
for select
using (submitted_by = auth.uid());

