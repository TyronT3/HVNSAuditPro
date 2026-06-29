-- Re-enable RLS on public.users and remove stale pre-migration policies.
--
-- Root cause: RLS was enabled by migration 20260620000002 but was subsequently
-- disabled (likely via Supabase Table Editor toggle). Stale policies from before
-- the migration system also remain alongside the current migration-created ones.
--
-- Safe to re-run: DROP IF EXISTS + ALTER TABLE is idempotent.

-- Drop old pre-migration policies that predate the current naming convention.
-- These are either too permissive ("Read all users when authenticated") or
-- duplicated by the migration-created policies below.
drop policy if exists "Managers can insert users"      on public.users;
drop policy if exists "Managers can update users"      on public.users;
drop policy if exists "Read all users when authenticated" on public.users;
drop policy if exists "Read own profile"               on public.users;
drop policy if exists "Users can update own record"    on public.users;

-- Re-enable RLS. The three migration-created policies remain in place:
--   users_select_self_or_report_viewers  (id = auth.uid() OR can_view_reports())
--   users_insert_manager_only            (is_manager())
--   users_update_manager_only            (is_manager())
alter table public.users enable row level security;
