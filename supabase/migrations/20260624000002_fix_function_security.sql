-- Fix function security warnings.
--
-- 1. Revoke EXECUTE from anon on all SECURITY DEFINER functions in public schema.
--    Unauthenticated callers have no legitimate reason to call any of these.
--    None are used in the sign-in flow (that lives in the auth schema).
--
-- 2. Revoke EXECUTE from authenticated on trigger functions.
--    Trigger functions are invoked by the DB engine as postgres, not by user calls.
--    Revoking from authenticated does not affect how triggers fire.
--
-- 3. Add set search_path = public to set_greatsoft_time_pushes_updated_at.
--    Without it, a search_path injection could redirect the function to a shadow schema.
--
-- NOTE — authenticated_security_definer_function_executable warnings for the RLS
-- helper functions (is_manager, is_director, can_view_reports, current_user_email,
-- current_user_role, section_has_assignee_subsection, subsection_parent_section_assignee)
-- cannot be resolved by revoking EXECUTE from authenticated: these functions are called
-- inside RLS USING clauses, so authenticated must have EXECUTE or every table query fails.
-- The clean fix is to move them to a non-PostgREST-exposed schema (e.g. util) and update
-- all RLS policies — a future refactor, not an emergency. The actual exposure is low:
-- calling them via /rpc/ returns only the caller's own role status or a boolean about
-- sections/subsections they can already query.

-- ── Revoke from anon ─────────────────────────────────────────────────────────
revoke execute on function public.can_view_reports()                               from anon;
revoke execute on function public.current_user_email()                             from anon;
revoke execute on function public.current_user_role()                              from anon;
revoke execute on function public.is_director()                                    from anon;
revoke execute on function public.is_manager()                                     from anon;
revoke execute on function public.is_tyron()                                       from anon;
revoke execute on function public.handle_new_auth_user()                           from anon;
revoke execute on function public.handle_new_user()                                from anon;
revoke execute on function public.section_has_assignee_subsection(uuid, text)      from anon;
revoke execute on function public.subsection_parent_section_assignee(uuid, text)   from anon;
revoke execute on function public.set_greatsoft_time_pushes_updated_at()           from anon;

-- ── Revoke trigger functions from authenticated ───────────────────────────────
revoke execute on function public.handle_new_auth_user()             from authenticated;
revoke execute on function public.handle_new_user()                  from authenticated;
revoke execute on function public.set_greatsoft_time_pushes_updated_at() from authenticated;

-- ── Fix set_greatsoft_time_pushes_updated_at search_path ────────────────────
create or replace function public.set_greatsoft_time_pushes_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
