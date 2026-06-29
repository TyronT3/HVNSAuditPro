-- Add co-assignee support to subsections.
--
-- The primary assignee (assignee_email) remains the owner for budget
-- attribution. Co-assignees see the subsection in My Work and can
-- log time / advance the step, just like the primary assignee.
--
-- Also covered: audit workload distribution view is frontend-only (no DB
-- changes needed), using existing subsections + step_logs data.

-- ── Schema ────────────────────────────────────────────────────────────────────
alter table public.subsections
  add column if not exists co_assignees text[] not null default '{}'::text[];

-- ── section_has_assignee_subsection ──────────────────────────────────────────
-- Now checks co_assignees too so sections stay visible when a user is only
-- listed as a co-assignee (not primary) on a subsection within that section.
create or replace function public.section_has_assignee_subsection(p_section_id uuid, p_email text)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.subsections
    where section_id = p_section_id
      and (assignee_email = p_email or p_email = any(co_assignees))
  )
$$;

-- ── subsections_select_visible ────────────────────────────────────────────────
drop policy if exists "subsections_select_visible" on public.subsections;
create policy "subsections_select_visible"
on public.subsections for select
using (
  public.can_view_reports()
  or assignee_email = public.current_user_email()
  or public.current_user_email() = any(co_assignees)
  or public.subsection_parent_section_assignee(subsections.section_id, public.current_user_email())
);

-- ── subsections_update_manager_or_assignee_progress ──────────────────────────
-- Co-assignees can advance the step and update progress just like the
-- primary assignee.
drop policy if exists "subsections_update_manager_or_assignee_progress" on public.subsections;
create policy "subsections_update_manager_or_assignee_progress"
on public.subsections for update
using (
  public.is_manager()
  or assignee_email = public.current_user_email()
  or public.current_user_email() = any(co_assignees)
  or exists (
    select 1 from public.sections s
    where s.id = subsections.section_id
      and s.assignee_email = public.current_user_email()
  )
)
with check (
  public.is_manager()
  or assignee_email = public.current_user_email()
  or public.current_user_email() = any(co_assignees)
  or exists (
    select 1 from public.sections s
    where s.id = subsections.section_id
      and s.assignee_email = public.current_user_email()
  )
);

-- ── step_logs_select_visible ──────────────────────────────────────────────────
-- Co-assignees can see step logs for subsections they are assigned to.
drop policy if exists "step_logs_select_visible" on public.step_logs;
create policy "step_logs_select_visible"
on public.step_logs for select
using (
  public.can_view_reports()
  or logged_by = auth.uid()
  or logged_by_email = public.current_user_email()
  or exists (
    select 1 from public.subsections ss
    join public.sections s on s.id = ss.section_id
    where ss.id = step_logs.subsection_id
      and (ss.assignee_email = public.current_user_email()
           or s.assignee_email = public.current_user_email()
           or public.current_user_email() = any(ss.co_assignees))
  )
);
