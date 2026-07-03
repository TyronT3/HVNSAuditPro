-- ============================================================================
-- NORMALIZE ALL STORED EMAILS TO LOWERCASE + prevent recurrence.
--
-- SAFETY: this runs in a single transaction. If you have TRUE duplicate
-- profiles (diagnostics query A returned rows), the users UPDATE below will
-- fail on the unique email index and the WHOLE script rolls back — nothing
-- changes. In that case, merge the duplicates first, then re-run this.
--
-- Does NOT touch auth.users (managed by Supabase Auth; login is unaffected).
-- ============================================================================

begin;

-- Prevention: force every future users.email write to lowercase.
create or replace function public.lowercase_user_email()
returns trigger
language plpgsql
as $$
begin
  if new.email is not null then
    new.email := lower(new.email);
  end if;
  return new;
end;
$$;

drop trigger if exists lowercase_user_email on public.users;
create trigger lowercase_user_email
  before insert or update on public.users
  for each row execute function public.lowercase_user_email();

-- Prevention: force assignee emails on subsections/sections to lowercase too
-- (covers CSV imports that store typed-case emails).
create or replace function public.lowercase_assignee_email()
returns trigger
language plpgsql
as $$
begin
  if new.assignee_email is not null then
    new.assignee_email := lower(new.assignee_email);
  end if;
  return new;
end;
$$;

drop trigger if exists lowercase_assignee_email_sub on public.subsections;
create trigger lowercase_assignee_email_sub
  before insert or update on public.subsections
  for each row execute function public.lowercase_assignee_email();

drop trigger if exists lowercase_assignee_email_sec on public.sections;
create trigger lowercase_assignee_email_sec
  before insert or update on public.sections
  for each row execute function public.lowercase_assignee_email();

-- Backfill existing data.
update public.users
  set email = lower(email)
  where email <> lower(email);

update public.sections
  set assignee_email = lower(assignee_email)
  where assignee_email is not null and assignee_email <> lower(assignee_email);

update public.subsections
  set assignee_email = lower(assignee_email)
  where assignee_email is not null and assignee_email <> lower(assignee_email);

update public.subsections
  set co_assignees = (select array_agg(lower(e)) from unnest(co_assignees) as e)
  where co_assignees is not null and array_length(co_assignees, 1) > 0;

update public.step_logs
  set logged_by_email = lower(logged_by_email)
  where logged_by_email is not null and logged_by_email <> lower(logged_by_email);

update public.timesheet_entries
  set submitted_by_email = lower(submitted_by_email)
  where submitted_by_email is not null and submitted_by_email <> lower(submitted_by_email);

commit;
