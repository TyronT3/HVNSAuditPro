-- Security fixes from 2026-07-03 review.
-- 1. step_logs INSERT: require own identity (AND, not OR) + assignment to the subsection
-- 2. users UPDATE guard: managers cannot change id/email or touch the super-admin row
-- 3. auth trigger: email collision or null email must not abort auth user creation
-- 4. missing DELETE policies on step_logs / timesheet_entries (manager only)
-- 5. timesheet_entries INSERT: identity spoof fix (AND, not OR)
-- 6. subsections UPDATE guard: assignees may only change step/comment/notes
-- 7. greatsoft_time_pushes: manager read/write via is_manager()

-- ─── 1. step_logs INSERT ─────────────────────────────────────────────────────
drop policy if exists "step_logs_insert_own_or_manager" on public.step_logs;
create policy "step_logs_insert_own_or_manager"
on public.step_logs for insert
with check (
  public.is_manager()
  or (
    logged_by = auth.uid()
    and logged_by_email = public.current_user_email()
    and exists (
      select 1 from public.subsections ss
      join public.sections s on s.id = ss.section_id
      where ss.id = step_logs.subsection_id
        and (ss.assignee_email = public.current_user_email()
             or public.current_user_email() = any(coalesce(ss.co_assignees, '{}'))
             or s.assignee_email = public.current_user_email())
    )
  )
);

-- NOT VALID: enforce for new rows without failing on any legacy negative rows.
alter table public.step_logs
  drop constraint if exists step_logs_hours_nonneg;
alter table public.step_logs
  add constraint step_logs_hours_nonneg check (hours >= 0) not valid;

-- ─── 2. users identity guard ─────────────────────────────────────────────────
-- auth.uid() is null for SQL-editor / service-role sessions, so the documented
-- "repair users.id" UPDATE keeps working.
create or replace function public.protect_user_identity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or public.is_tyron() then
    return new;
  end if;
  if new.id is distinct from old.id then
    raise exception 'users.id is immutable';
  end if;
  if new.email is distinct from old.email then
    raise exception 'email changes require super admin';
  end if;
  if lower(old.email) = 'tyron@hvns.co.za'
     and (new.active is distinct from old.active or new.role is distinct from old.role) then
    raise exception 'super admin row is protected';
  end if;
  return new;
end;
$$;
revoke execute on function public.protect_user_identity() from public;

drop trigger if exists protect_user_identity on public.users;
create trigger protect_user_identity
  before update on public.users
  for each row execute function public.protect_user_identity();

-- ─── 3. auth trigger resilience ──────────────────────────────────────────────
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.email is null then
    return new;
  end if;
  insert into public.users (id, email, role, active, full_name)
  values (
    new.id,
    lower(new.email),
    'staff',
    false,
    split_part(new.email, '@', 1)
  )
  on conflict (id) do nothing;
  return new;
exception when unique_violation then
  -- A profile with this email already exists under a different id (legacy row).
  -- Do not block auth user creation; repair with the documented id-sync UPDATE.
  return new;
end;
$$;

-- ─── 4. missing DELETE policies ──────────────────────────────────────────────
drop policy if exists "step_logs_delete_manager_only" on public.step_logs;
create policy "step_logs_delete_manager_only"
on public.step_logs for delete
using (public.is_manager());

drop policy if exists "timesheet_entries_delete_manager_only" on public.timesheet_entries;
create policy "timesheet_entries_delete_manager_only"
on public.timesheet_entries for delete
using (public.is_manager());

-- ─── 5. timesheet_entries INSERT identity fix ────────────────────────────────
drop policy if exists "timesheet_entries_insert_own" on public.timesheet_entries;
create policy "timesheet_entries_insert_own"
on public.timesheet_entries for insert
with check (
  submitted_by = auth.uid()
  and submitted_by_email = public.current_user_email()
);

-- ─── 6. subsections column guard for assignees ───────────────────────────────
-- Staff UI only edits step and comment; notes kept for safety. jsonb diff makes
-- this robust to columns added later.
create or replace function public.protect_subsection_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  allowed text[] := array['step', 'comment', 'notes', 'updated_at'];
begin
  if auth.uid() is null or public.is_manager() then
    return new;
  end if;
  if (to_jsonb(new) - allowed) is distinct from (to_jsonb(old) - allowed) then
    raise exception 'Assignees may only update step, comment and notes';
  end if;
  return new;
end;
$$;
revoke execute on function public.protect_subsection_columns() from public;

drop trigger if exists protect_subsection_columns on public.subsections;
create trigger protect_subsection_columns
  before update on public.subsections
  for each row execute function public.protect_subsection_columns();

-- ─── 7. greatsoft_time_pushes manager policies ───────────────────────────────
drop policy if exists "Managers can read all GreatSoft push rows" on public.greatsoft_time_pushes;
drop policy if exists "gtp_manager_all" on public.greatsoft_time_pushes;
create policy "gtp_manager_all"
on public.greatsoft_time_pushes for all
using (public.is_manager()) with check (public.is_manager());
