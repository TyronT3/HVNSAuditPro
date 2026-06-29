-- The previous migration revoked EXECUTE from the anon and authenticated roles
-- directly, but the warnings persisted. Supabase grants EXECUTE on public functions
-- to PUBLIC (all roles) by default, so revoking from a specific role is overridden
-- by the PUBLIC grant. This migration revokes from PUBLIC, which covers all roles,
-- then re-grants to authenticated for functions required by RLS policy evaluation.

-- ── Trigger function: revoke from PUBLIC, no re-grant needed ────────────────
-- handle_new_auth_user is called only by the on_auth_user_created trigger, which
-- fires as postgres (SECURITY DEFINER). No user session ever needs to call it.
revoke execute on function public.handle_new_auth_user() from public;

-- ── RLS helper functions: revoke from PUBLIC, re-grant to authenticated ─────
-- These functions are called inside RLS USING clauses on every table query.
-- authenticated must retain EXECUTE or all table access fails.
-- anon is not re-granted: unauthenticated sessions have no tables to query.

revoke execute on function public.can_view_reports()    from public;
revoke execute on function public.current_user_email()  from public;
revoke execute on function public.current_user_role()   from public;
revoke execute on function public.is_director()         from public;
revoke execute on function public.is_manager()          from public;
revoke execute on function public.is_tyron()            from public;
revoke execute on function public.section_has_assignee_subsection(uuid, text)    from public;
revoke execute on function public.subsection_parent_section_assignee(uuid, text) from public;

grant execute on function public.can_view_reports()    to authenticated;
grant execute on function public.current_user_email()  to authenticated;
grant execute on function public.current_user_role()   to authenticated;
grant execute on function public.is_director()         to authenticated;
grant execute on function public.is_manager()          to authenticated;
grant execute on function public.is_tyron()            to authenticated;
grant execute on function public.section_has_assignee_subsection(uuid, text)    to authenticated;
grant execute on function public.subsection_parent_section_assignee(uuid, text) to authenticated;
