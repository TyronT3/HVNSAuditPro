-- RLS policies for main app tables.
-- Tested against all roles before applying to production (2026-06-20).
-- Safe to re-run: all policies use DROP IF EXISTS before CREATE.

alter table public.users             enable row level security;
alter table public.settings          enable row level security;
alter table public.audits            enable row level security;
alter table public.sections          enable row level security;
alter table public.subsections       enable row level security;
alter table public.step_logs         enable row level security;
alter table public.timesheet_entries enable row level security;

-- ─── USERS ────────────────────────────────────────────────────────────────────

drop policy if exists "users_select_self_or_report_viewers" on public.users;
create policy "users_select_self_or_report_viewers"
on public.users for select
using (id = auth.uid() or public.can_view_reports());

drop policy if exists "users_insert_manager_only" on public.users;
create policy "users_insert_manager_only"
on public.users for insert
with check (public.is_manager());

drop policy if exists "users_update_manager_only" on public.users;
create policy "users_update_manager_only"
on public.users for update
using (public.is_manager()) with check (public.is_manager());

-- ─── SETTINGS ─────────────────────────────────────────────────────────────────

drop policy if exists "settings_select_authenticated" on public.settings;
create policy "settings_select_authenticated"
on public.settings for select
using (auth.uid() is not null);

drop policy if exists "settings_write_manager_only" on public.settings;
create policy "settings_write_manager_only"
on public.settings for all
using (public.is_manager()) with check (public.is_manager());

-- ─── AUDITS ───────────────────────────────────────────────────────────────────

drop policy if exists "audits_select_visible" on public.audits;
create policy "audits_select_visible"
on public.audits for select
using (
  public.can_view_reports()
  or exists (
    select 1 from public.sections s
    left join public.subsections ss on ss.section_id = s.id
    where s.audit_id = audits.id
      and (s.assignee_email = public.current_user_email()
           or ss.assignee_email = public.current_user_email())
  )
);

drop policy if exists "audits_write_manager_only" on public.audits;
create policy "audits_write_manager_only"
on public.audits for all
using (public.is_manager()) with check (public.is_manager());

-- ─── SECTIONS ─────────────────────────────────────────────────────────────────

drop policy if exists "sections_select_visible" on public.sections;
create policy "sections_select_visible"
on public.sections for select
using (
  public.can_view_reports()
  or assignee_email = public.current_user_email()
  or exists (
    select 1 from public.subsections ss
    where ss.section_id = sections.id
      and ss.assignee_email = public.current_user_email()
  )
);

drop policy if exists "sections_write_manager_only" on public.sections;
create policy "sections_write_manager_only"
on public.sections for all
using (public.is_manager()) with check (public.is_manager());

-- ─── SUBSECTIONS ──────────────────────────────────────────────────────────────

drop policy if exists "subsections_select_visible" on public.subsections;
create policy "subsections_select_visible"
on public.subsections for select
using (
  public.can_view_reports()
  or assignee_email = public.current_user_email()
  or exists (
    select 1 from public.sections s
    where s.id = subsections.section_id
      and s.assignee_email = public.current_user_email()
  )
);

drop policy if exists "subsections_update_manager_or_assignee_progress" on public.subsections;
create policy "subsections_update_manager_or_assignee_progress"
on public.subsections for update
using (
  public.is_manager()
  or assignee_email = public.current_user_email()
  or exists (
    select 1 from public.sections s
    where s.id = subsections.section_id
      and s.assignee_email = public.current_user_email()
  )
)
with check (
  public.is_manager()
  or assignee_email = public.current_user_email()
  or exists (
    select 1 from public.sections s
    where s.id = subsections.section_id
      and s.assignee_email = public.current_user_email()
  )
);

drop policy if exists "subsections_insert_delete_manager_only" on public.subsections;
create policy "subsections_insert_delete_manager_only"
on public.subsections for all
using (public.is_manager()) with check (public.is_manager());

-- ─── STEP LOGS ────────────────────────────────────────────────────────────────

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
           or s.assignee_email = public.current_user_email())
  )
);

drop policy if exists "step_logs_insert_own_or_manager" on public.step_logs;
create policy "step_logs_insert_own_or_manager"
on public.step_logs for insert
with check (
  public.is_manager()
  or logged_by = auth.uid()
  or logged_by_email = public.current_user_email()
);

drop policy if exists "step_logs_update_manager_only" on public.step_logs;
create policy "step_logs_update_manager_only"
on public.step_logs for update
using (public.is_manager()) with check (public.is_manager());

-- ─── TIMESHEET ENTRIES ────────────────────────────────────────────────────────

drop policy if exists "timesheet_entries_select_visible" on public.timesheet_entries;
create policy "timesheet_entries_select_visible"
on public.timesheet_entries for select
using (
  public.can_view_reports()
  or submitted_by = auth.uid()
  or submitted_by_email = public.current_user_email()
);

drop policy if exists "timesheet_entries_insert_own" on public.timesheet_entries;
create policy "timesheet_entries_insert_own"
on public.timesheet_entries for insert
with check (
  submitted_by = auth.uid()
  or submitted_by_email = public.current_user_email()
);

drop policy if exists "timesheet_entries_review_manager_only" on public.timesheet_entries;
create policy "timesheet_entries_review_manager_only"
on public.timesheet_entries for update
using (public.is_manager()) with check (public.is_manager());
