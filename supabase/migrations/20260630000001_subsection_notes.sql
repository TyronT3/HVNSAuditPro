-- Add notes column to subsections.
-- Informational only — stores documents required, context, instructions, etc.
-- Has no effect on steps, progress percentage, hours, or fee calculations.
alter table public.subsections
  add column if not exists notes text;

-- Recreate subsection_summary to expose notes.
-- CREATE OR REPLACE is safe here: notes is added at the end of the column list,
-- which is the only structural change PostgreSQL allows in-place for a view.
-- Dependent views (section_summary, audit_summary) are unaffected.
create or replace view public.subsection_summary with (security_invoker = true) as
select
  sub.id,
  sub.section_id,
  sub.name,
  sub.assignee_email,
  sub.due_date,
  sub.budget_hours,
  sub.step,
  sub.sort_order,
  coalesce(sum(sl.hours), 0::numeric)                                                 as actual_hours,
  sub.budget_hours - coalesce(sum(sl.hours), 0::numeric)                              as hours_variance,
  coalesce(sum(sl.hours), 0::numeric) * coalesce(s_rate.firm_rate, 1000::numeric)     as fee_value,
  sub.budget_hours                    * coalesce(s_rate.firm_rate, 1000::numeric)     as budget_fee,
  case
    when sub.step = 'Signed Off' then 100::numeric
    else round(
      ((array_position(
          array['Not Started','Client Requested','Client Received',
                'Processing','Finalising','Review','Signed Off'],
          sub.step
        )::numeric - 1) / 6::numeric) * 100::numeric
    )
  end as progress_pct,
  sub.notes
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
  sub.notes, s_rate.firm_rate;

grant select on public.subsection_summary to authenticated;
