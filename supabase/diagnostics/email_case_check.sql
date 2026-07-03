-- ============================================================================
-- EMAIL CASE / DUPLICATE DIAGNOSTICS  (read-only — safe to run anytime)
-- Run each block in Supabase Dashboard -> SQL Editor and read the results.
-- ============================================================================

-- A) TRUE DUPLICATE PROFILES: two+ users rows that are the same email
--    ignoring case (e.g. "Bob@hvns.co.za" AND "bob@hvns.co.za").
--    If this returns ANY rows, you must MERGE them (see notes) BEFORE
--    running the fix script.
select lower(email)          as normalized_email,
       count(*)              as copies,
       array_agg(email)      as email_variants,
       array_agg(id::text)   as user_ids,
       array_agg(active)     as active_flags
from public.users
group by lower(email)
having count(*) > 1
order by copies desc;

-- B) PROFILE vs LOGIN mismatch: the profile email differs from the actual
--    Supabase Auth login email for the same person (usually a case diff).
--    These people can log in but assignment matching may miss them.
select pu.id,
       pu.email as profile_email,
       au.email as login_email
from public.users pu
join auth.users au on au.id = pu.id
where pu.email is distinct from au.email
order by pu.email;

-- C) NON-LOWERCASE PROFILES: any users row whose email has capital letters.
select id, email, full_name, role, active
from public.users
where email <> lower(email)
order by email;

-- D) BROKEN ASSIGNMENTS: subsections assigned to an email whose case does not
--    exactly match an active profile, but a lowercase match DOES exist.
--    These are people silently not seeing their work.
select ss.id, ss.name, ss.assignee_email
from public.subsections ss
where ss.assignee_email is not null and ss.assignee_email <> ''
  and not exists (select 1 from public.users u where u.email = ss.assignee_email and u.active)
  and exists     (select 1 from public.users u where lower(u.email) = lower(ss.assignee_email))
order by ss.assignee_email;

-- E) Same check for section-level assignees.
select s.id, s.name, s.assignee_email
from public.sections s
where s.assignee_email is not null and s.assignee_email <> ''
  and not exists (select 1 from public.users u where u.email = s.assignee_email and u.active)
  and exists     (select 1 from public.users u where lower(u.email) = lower(s.assignee_email))
order by s.assignee_email;
