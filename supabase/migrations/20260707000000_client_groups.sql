-- Client groups: lets a manager cluster related audits (e.g. a group of
-- companies under one holding entity) for a combined dashboard view.
-- Additive only: new table + nullable FK column on audits, no existing
-- columns touched. Safe to re-run: create-if-not-exists / drop-if-exists
-- guards throughout.

create table if not exists public.client_groups (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create unique index if not exists client_groups_name_uidx
  on public.client_groups (lower(name));

alter table public.audits
  add column if not exists group_id uuid references public.client_groups(id) on delete set null;

-- ─── RLS ───────────────────────────────────────────────────────────────────
alter table public.client_groups enable row level security;

drop policy if exists "client_groups_write_manager_only" on public.client_groups;
create policy "client_groups_write_manager_only"
on public.client_groups for all
using (public.is_manager()) with check (public.is_manager());

drop policy if exists "client_groups_select_authenticated" on public.client_groups;
create policy "client_groups_select_authenticated"
on public.client_groups for select
using (auth.uid() is not null);

-- ─── audit_summary: add group_id so the Groups dashboard can filter/aggregate ──
-- Trailing column addition — safe with CREATE OR REPLACE VIEW (no existing
-- columns removed or reordered). Mirrors the view defined in
-- 20260624000001_fix_security_definer_views.sql.
create or replace view public.audit_summary with (security_invoker = true) as
select
  a.id,
  a.name,
  a.client,
  a.due_date,
  a.firm_rate,
  coalesce(a.type, 'audit')                      as type,
  a.created_at,
  count(distinct sec.id)                         as section_count,
  coalesce(sum(ss2.budget_hours),  0::numeric)   as budget_hours,
  coalesce(sum(ss2.actual_hours),  0::numeric)   as actual_hours,
  coalesce(sum(ss2.hours_variance),0::numeric)   as hours_variance,
  coalesce(sum(ss2.fee_value),     0::numeric)   as fee_value,
  coalesce(sum(ss2.budget_fee),    0::numeric)   as budget_fee,
  round(coalesce(avg(ss2.progress_pct), 0::numeric)) as progress_pct,
  a.group_id
from audits a
left join sections        sec on sec.audit_id = a.id
left join section_summary ss2 on ss2.id       = sec.id
where a.archived = false
group by a.id, a.name, a.client, a.due_date, a.firm_rate, a.type, a.created_at, a.group_id;
