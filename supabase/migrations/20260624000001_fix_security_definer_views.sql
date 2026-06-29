-- Recreate all four summary views with security_invoker=true.
--
-- Problem: views created without security_invoker run as the view owner (postgres),
-- which bypasses RLS on every table they touch. Any authenticated user could query
-- audit_summary / section_summary / subsection_summary / timesheet_variance_summary
-- and see ALL rows regardless of their role or assignment.
--
-- Fix: security_invoker=true makes the view execute with the caller's identity,
-- so all existing RLS policies on subsections, sections, audits, step_logs,
-- timesheet_entries, and settings are enforced as normal.
--
-- Drop order matters: audit_summary depends on section_summary, which depends on
-- subsection_summary. Drop from the top of the chain first.
-- Recreate from the bottom up.

drop view if exists public.audit_summary;
drop view if exists public.section_summary;
drop view if exists public.subsection_summary;
drop view if exists public.timesheet_variance_summary;

-- ── subsection_summary ───────────────────────────────────────────────────────
create view public.subsection_summary with (security_invoker = true) as
select
  sub.id,
  sub.section_id,
  sub.name,
  sub.assignee_email,
  sub.due_date,
  sub.budget_hours,
  sub.step,
  sub.sort_order,
  coalesce(sum(sl.hours), 0::numeric)                                       as actual_hours,
  sub.budget_hours - coalesce(sum(sl.hours), 0::numeric)                    as hours_variance,
  coalesce(sum(sl.hours), 0::numeric) * coalesce(s_rate.firm_rate, 1000::numeric) as fee_value,
  sub.budget_hours                    * coalesce(s_rate.firm_rate, 1000::numeric) as budget_fee,
  case
    when sub.step = 'Signed Off' then 100::numeric
    else round(
      ((array_position(
          array['Not Started','Client Requested','Client Received',
                'Processing','Finalising','Review','Signed Off'],
          sub.step
        )::numeric - 1) / 6::numeric) * 100::numeric
    )
  end as progress_pct
from subsections sub
left join step_logs sl on sl.subsection_id = sub.id
cross join (
  select value::numeric as firm_rate
  from settings
  where key = 'firm_rate'
) s_rate
group by
  sub.id, sub.section_id, sub.name, sub.assignee_email,
  sub.due_date, sub.budget_hours, sub.step, sub.sort_order,
  s_rate.firm_rate;

-- ── section_summary ──────────────────────────────────────────────────────────
create view public.section_summary with (security_invoker = true) as
select
  sec.id,
  sec.audit_id,
  sec.name,
  sec.assignee_email,
  sec.due_date,
  count(sub.id)                               as subsection_count,
  coalesce(sum(ss.budget_hours),  0::numeric) as budget_hours,
  coalesce(sum(ss.actual_hours),  0::numeric) as actual_hours,
  coalesce(sum(ss.hours_variance),0::numeric) as hours_variance,
  coalesce(sum(ss.fee_value),     0::numeric) as fee_value,
  coalesce(sum(ss.budget_fee),    0::numeric) as budget_fee,
  round(coalesce(avg(ss.progress_pct), 0::numeric)) as progress_pct
from sections sec
left join subsections       sub on sub.section_id = sec.id
left join subsection_summary ss  on ss.id          = sub.id
group by sec.id, sec.audit_id, sec.name, sec.assignee_email, sec.due_date;

-- ── audit_summary ────────────────────────────────────────────────────────────
create view public.audit_summary with (security_invoker = true) as
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
  round(coalesce(avg(ss2.progress_pct), 0::numeric)) as progress_pct
from audits a
left join sections        sec on sec.audit_id = a.id
left join section_summary ss2 on ss2.id       = sec.id
where a.archived = false
group by a.id, a.name, a.client, a.due_date, a.firm_rate, a.type, a.created_at;

-- ── timesheet_variance_summary ───────────────────────────────────────────────
create view public.timesheet_variance_summary with (security_invoker = true) as
select
  te.id,
  te.week_ending,
  te.firm_system_hours,
  te.app_hours,
  te.variance,
  te.explanation,
  te.status,
  te.submitted_at,
  te.submitted_by_email,
  sub.name as subsection_name,
  sec.name as section_name,
  a.name   as audit_name,
  a.client
from timesheet_entries te
join subsections sub on sub.id = te.subsection_id
join sections    sec on sec.id = sub.section_id
join audits      a   on a.id   = sec.audit_id
order by te.submitted_at desc;

-- Ensure the authenticated role can query all four views.
-- (Supabase default privileges usually cover this, but explicit grants are safer
--  after a DROP + CREATE cycle.)
grant select on public.subsection_summary          to authenticated;
grant select on public.section_summary             to authenticated;
grant select on public.audit_summary               to authenticated;
grant select on public.timesheet_variance_summary  to authenticated;
