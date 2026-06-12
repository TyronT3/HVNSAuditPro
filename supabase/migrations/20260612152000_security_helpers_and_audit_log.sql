-- Low-risk security foundation.
-- This does not enable RLS on existing app tables and should not change the
-- current sign-in flow. It provides helper functions for later policies and an
-- audit log table for sensitive actions.

create or replace function public.current_user_email()
returns text
language sql
security definer
stable
set search_path = public
as $$
  select coalesce(
    (select email from public.users where id = auth.uid() and active = true),
    ''
  )
$$;

create or replace function public.current_user_role()
returns text
language sql
security definer
stable
set search_path = public
as $$
  select coalesce(
    (select role from public.users where id = auth.uid() and active = true),
    ''
  )
$$;

create or replace function public.is_tyron()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select lower(public.current_user_email()) = 'tyron@hvns.co.za'
$$;

create or replace function public.is_manager()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select public.is_tyron() or public.current_user_role() = 'manager'
$$;

create or replace function public.is_director()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select public.current_user_role() = 'director'
$$;

create or replace function public.can_view_reports()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select public.is_tyron() or public.current_user_role() in ('manager', 'director')
$$;

create table if not exists public.security_audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid,
  actor_email text,
  action text not null,
  target_table text,
  target_id uuid,
  details jsonb,
  created_at timestamptz not null default now()
);

alter table public.security_audit_log enable row level security;

drop policy if exists "Managers can read security audit log"
  on public.security_audit_log;
create policy "Managers can read security audit log"
on public.security_audit_log
for select
using (public.is_manager());

create index if not exists security_audit_log_actor_id_idx
  on public.security_audit_log(actor_id);

create index if not exists security_audit_log_created_at_idx
  on public.security_audit_log(created_at desc);

