-- Fix infinite recursion in sections / subsections RLS SELECT policies.
--
-- Root cause: sections_select_visible has an exists(subsections...) subquery, and
-- subsections_select_visible has an exists(sections...) subquery. PostgreSQL does NOT
-- guarantee short-circuit evaluation of OR in USING clauses, so the planner evaluates
-- both branches and the mutual reference loops forever.
--
-- Fix: replace each cross-table exists with a SECURITY DEFINER helper function.
-- SECURITY DEFINER bypasses RLS on the referenced table, breaking the cycle cleanly.

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
      and assignee_email = p_email
  )
$$;

create or replace function public.subsection_parent_section_assignee(p_section_id uuid, p_email text)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.sections
    where id = p_section_id
      and assignee_email = p_email
  )
$$;

drop policy if exists "sections_select_visible" on public.sections;
create policy "sections_select_visible"
on public.sections for select
using (
  public.can_view_reports()
  or assignee_email = public.current_user_email()
  or public.section_has_assignee_subsection(sections.id, public.current_user_email())
);

drop policy if exists "subsections_select_visible" on public.subsections;
create policy "subsections_select_visible"
on public.subsections for select
using (
  public.can_view_reports()
  or assignee_email = public.current_user_email()
  or public.subsection_parent_section_assignee(subsections.section_id, public.current_user_email())
);
