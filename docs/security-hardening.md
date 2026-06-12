# Security hardening plan

This project currently signs users in with Supabase Auth from a static
`index.html` page. That can be secure, but only if Row Level Security protects
the data behind the public anon key.

## Access model

| User type | Access |
| --- | --- |
| `tyron@hvns.co.za` | Full unrestricted app data access |
| Manager | Full operational access |
| Director | Reports/read access; update only jobs assigned directly to them |
| Staff | Assigned jobs and own time entries only |

Tyron's full access is implemented by email through `public.is_tyron()`, not
only by role. This means he remains unrestricted even if role data is edited.

## What has been added

### Safe migration

`supabase/migrations/20260612152000_security_helpers_and_audit_log.sql`

Adds:

- `public.current_user_email()`
- `public.current_user_role()`
- `public.is_tyron()`
- `public.is_manager()`
- `public.is_director()`
- `public.can_view_reports()`
- `public.security_audit_log`

This migration does not enable RLS on the current app tables and should not
change sign-in.

### Staging-only RLS script

`supabase/security/rls_hardening_staging.sql`

This is intentionally not in the migrations folder. It should be tested in a
staging Supabase project before being converted into a production migration.

## What still needs confirmation

Before applying the RLS script to production, confirm:

1. The exact two director user emails.
2. Whether directors should see all client/audit reports or only final report
   dashboards.
3. Whether managers other than Tyron should be allowed to edit user roles.
4. Whether staff should be able to move a subsection backward, or only forward.
5. Whether staff should see other users assigned to the same section.

## Test checklist

Run this in staging first:

1. Tyron can sign in and access every tab.
2. Tyron can add/edit/delete audits, users, settings, sections, subsections, and
   timesheets.
3. A director can sign in and see reports.
4. A director cannot access manager-only edit screens.
5. A director assigned to a subsection can update that job.
6. A normal staff user sees assigned work and can log time.
7. A normal staff user cannot update roles, settings, or other users.
8. Existing password reset and normal sign-in still work.

