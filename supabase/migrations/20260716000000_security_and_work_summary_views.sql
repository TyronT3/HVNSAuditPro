-- Security and data-separation hardening from the 2026-07-16 project review.
-- Confirm all prior migrations are applied before running this file.

-- Staff work views omit firm rates and fee values while preserving the
-- operational fields used by the Dashboard.
create or replace view public.subsection_work_summary with (security_invoker = true) as
select
  sub.id,
  sub.section_id,
  sub.name,
  sub.assignee_email,
  sub.due_date,
  sub.budget_hours,
  sub.step,
  sub.sort_order,
  coalesce(sum(sl.hours), 0::numeric) as actual_hours,
  sub.budget_hours - coalesce(sum(sl.hours), 0::numeric) as hours_variance,
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
from public.subsections sub
left join public.step_logs sl on sl.subsection_id = sub.id
group by
  sub.id, sub.section_id, sub.name, sub.assignee_email,
  sub.due_date, sub.budget_hours, sub.step, sub.sort_order, sub.notes;

create or replace view public.section_work_summary with (security_invoker = true) as
select
  sec.id,
  sec.audit_id,
  sec.name,
  sec.assignee_email,
  sec.due_date,
  count(sub.id) as subsection_count,
  coalesce(sum(ss.budget_hours), 0::numeric) as budget_hours,
  coalesce(sum(ss.actual_hours), 0::numeric) as actual_hours,
  coalesce(sum(ss.hours_variance), 0::numeric) as hours_variance,
  round(coalesce(avg(ss.progress_pct), 0::numeric)) as progress_pct
from public.sections sec
left join public.subsections sub on sub.section_id = sec.id
left join public.subsection_work_summary ss on ss.id = sub.id
group by sec.id, sec.audit_id, sec.name, sec.assignee_email, sec.due_date;

create or replace view public.audit_work_summary with (security_invoker = true) as
select
  a.id,
  a.name,
  a.client,
  a.due_date,
  coalesce(a.type, 'audit') as type,
  a.created_at,
  count(distinct sec.id) as section_count,
  coalesce(sum(ss.budget_hours), 0::numeric) as budget_hours,
  coalesce(sum(ss.actual_hours), 0::numeric) as actual_hours,
  coalesce(sum(ss.hours_variance), 0::numeric) as hours_variance,
  round(coalesce(avg(ss.progress_pct), 0::numeric)) as progress_pct,
  a.group_id
from public.audits a
left join public.sections sec on sec.audit_id = a.id
left join public.section_work_summary ss on ss.id = sec.id
where a.archived = false
group by a.id, a.name, a.client, a.due_date, a.type, a.created_at, a.group_id;

revoke all on public.subsection_work_summary from anon;
revoke all on public.section_work_summary from anon;
revoke all on public.audit_work_summary from anon;
grant select on public.subsection_work_summary to authenticated;
grant select on public.section_work_summary to authenticated;
grant select on public.audit_work_summary to authenticated;

-- Report views retain their existing columns but return rows only to report
-- viewers and trusted database/service roles. Staff use the work views above.
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
  coalesce(sum(sl.hours), 0::numeric) as actual_hours,
  sub.budget_hours - coalesce(sum(sl.hours), 0::numeric) as hours_variance,
  coalesce(sum(sl.hours), 0::numeric) * coalesce(s_rate.firm_rate, 1000::numeric) as fee_value,
  sub.budget_hours * coalesce(s_rate.firm_rate, 1000::numeric) as budget_fee,
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
from public.subsections sub
left join public.step_logs sl on sl.subsection_id = sub.id
cross join (
  select value::numeric as firm_rate
  from public.settings
  where key = 'firm_rate'
) s_rate
where current_user in ('postgres', 'service_role') or public.can_view_reports()
group by
  sub.id, sub.section_id, sub.name, sub.assignee_email,
  sub.due_date, sub.budget_hours, sub.step, sub.sort_order,
  sub.notes, s_rate.firm_rate;

create or replace view public.section_summary with (security_invoker = true) as
select
  sec.id,
  sec.audit_id,
  sec.name,
  sec.assignee_email,
  sec.due_date,
  count(sub.id) as subsection_count,
  coalesce(sum(ss.budget_hours), 0::numeric) as budget_hours,
  coalesce(sum(ss.actual_hours), 0::numeric) as actual_hours,
  coalesce(sum(ss.hours_variance), 0::numeric) as hours_variance,
  coalesce(sum(ss.fee_value), 0::numeric) as fee_value,
  coalesce(sum(ss.budget_fee), 0::numeric) as budget_fee,
  round(coalesce(avg(ss.progress_pct), 0::numeric)) as progress_pct
from public.sections sec
left join public.subsections sub on sub.section_id = sec.id
left join public.subsection_summary ss on ss.id = sub.id
where current_user in ('postgres', 'service_role') or public.can_view_reports()
group by sec.id, sec.audit_id, sec.name, sec.assignee_email, sec.due_date;

create or replace view public.audit_summary with (security_invoker = true) as
select
  a.id,
  a.name,
  a.client,
  a.due_date,
  a.firm_rate,
  coalesce(a.type, 'audit') as type,
  a.created_at,
  count(distinct sec.id) as section_count,
  coalesce(sum(ss.budget_hours), 0::numeric) as budget_hours,
  coalesce(sum(ss.actual_hours), 0::numeric) as actual_hours,
  coalesce(sum(ss.hours_variance), 0::numeric) as hours_variance,
  coalesce(sum(ss.fee_value), 0::numeric) as fee_value,
  coalesce(sum(ss.budget_fee), 0::numeric) as budget_fee,
  round(coalesce(avg(ss.progress_pct), 0::numeric)) as progress_pct,
  a.group_id
from public.audits a
left join public.sections sec on sec.audit_id = a.id
left join public.section_summary ss on ss.id = sec.id
where a.archived = false
  and (current_user in ('postgres', 'service_role') or public.can_view_reports())
group by a.id, a.name, a.client, a.due_date, a.firm_rate, a.type, a.created_at, a.group_id;

create or replace view public.timesheet_variance_summary with (security_invoker = true) as
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
  a.name as audit_name,
  a.client
from public.timesheet_entries te
join public.subsections sub on sub.id = te.subsection_id
join public.sections sec on sec.id = sub.section_id
join public.audits a on a.id = sec.audit_id
where current_user in ('postgres', 'service_role') or public.can_view_reports()
order by te.submitted_at desc;

revoke all on public.subsection_summary from anon;
revoke all on public.section_summary from anon;
revoke all on public.audit_summary from anon;
revoke all on public.timesheet_variance_summary from anon;
grant select on public.subsection_summary to authenticated;
grant select on public.section_summary to authenticated;
grant select on public.audit_summary to authenticated;
grant select on public.timesheet_variance_summary to authenticated;

drop policy if exists "settings_select_authenticated" on public.settings;
drop policy if exists "settings_select_report_viewers" on public.settings;
create policy "settings_select_report_viewers"
on public.settings for select
to authenticated
using (public.can_view_reports());

-- RLS helper callers may only ask about their own assignment identity.
create or replace function public.section_has_assignee_subsection(p_section_id uuid, p_email text)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select p_email = public.current_user_email()
    and exists (
      select 1 from public.subsections
      where section_id = p_section_id
        and (assignee_email = p_email or p_email = any(co_assignees))
    )
$$;

create or replace function public.subsection_parent_section_assignee(p_section_id uuid, p_email text)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select p_email = public.current_user_email()
    and exists (
      select 1 from public.sections
      where id = p_section_id
        and assignee_email = p_email
    )
$$;

revoke execute on function public.section_has_assignee_subsection(uuid, text) from public;
revoke execute on function public.subsection_parent_section_assignee(uuid, text) from public;
grant execute on function public.section_has_assignee_subsection(uuid, text) to authenticated;
grant execute on function public.subsection_parent_section_assignee(uuid, text) to authenticated;

-- Every time-log row records the real caller identity. Managers may log against
-- any subsection, but may not impersonate another user in the audit trail.
drop policy if exists "step_logs_insert_own_or_manager" on public.step_logs;
create policy "step_logs_insert_own_or_manager"
on public.step_logs for insert
to authenticated
with check (
  logged_by = auth.uid()
  and logged_by_email = public.current_user_email()
  and (
    public.is_manager()
    or exists (
      select 1 from public.subsections ss
      join public.sections s on s.id = ss.section_id
      where ss.id = step_logs.subsection_id
        and (ss.assignee_email = public.current_user_email()
             or public.current_user_email() = any(coalesce(ss.co_assignees, '{}'))
             or s.assignee_email = public.current_user_email())
    )
  )
);

-- Staff can update progress/comments and their personal work-list visibility.
-- Manager-authored notes remain protected.
create or replace function public.protect_subsection_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  allowed text[] := array['step', 'comment', 'hidden_from_worklist', 'updated_at'];
begin
  if auth.uid() is null or public.is_manager() then
    return new;
  end if;
  if (to_jsonb(new) - allowed) is distinct from (to_jsonb(old) - allowed) then
    raise exception 'Assignees may only update step, comment and work-list visibility';
  end if;
  return new;
end;
$$;
revoke execute on function public.protect_subsection_columns() from public;

-- NOT VALID avoids failing the migration on legacy rows while protecting all
-- new and updated rows. Validate after running a legacy-data diagnostic.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.subsections'::regclass
      and conname = 'subsections_step_allowlist'
  ) then
    alter table public.subsections
      add constraint subsections_step_allowlist
      check (step in ('Not Started','Client Requested','Client Received','Processing','Finalising','Review','Signed Off'))
      not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.step_logs'::regclass
      and conname = 'step_logs_step_allowlist'
  ) then
    alter table public.step_logs
      add constraint step_logs_step_allowlist
      check (step in ('Not Started','Client Requested','Client Received','Processing','Finalising','Review','Signed Off'))
      not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.timesheet_entries'::regclass
      and conname = 'timesheet_entries_status_allowlist'
  ) then
    alter table public.timesheet_entries
      add constraint timesheet_entries_status_allowlist
      check (status in ('pending','reviewed','flagged'))
      not valid;
  end if;
end
$$;
