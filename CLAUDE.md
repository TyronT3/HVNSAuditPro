# HVNSAuditPro — CLAUDE.md

## Project Overview

**HVNSAuditPro** is a web-based audit engagement tracker for HVNS & Company (an audit and assurance firm). It lets managers create and assign audit engagements, track time logged against subsections, push time entries to GreatSoft (the firm's external time-billing system), and import CaseWare Trial Balance files for tax return preparation.

**Live URL:** `https://tyront3.github.io/HVNSAuditPro/`
**Branches:** `main` (production, auto-deploys to GitHub Pages), `backend_scaffold` (active dev)

---

## Architecture

### Frontend
- **Single file SPA:** `index.html` — all HTML, CSS, and JavaScript is inline in this one file (~1,400 lines). No build step, no framework. Do not split it into separate files without explicit instruction.
- **Auth:** Supabase Auth (email/password). Redirect URL points to the GitHub Pages URL.
- **Database client:** `@supabase/supabase-js@2` loaded via CDN.
- **Excel parsing:** `xlsx@0.18.5` (SheetJS) loaded via `cdn.jsdelivr.net` with `defer`. Do NOT switch back to `cdn.sheetjs.com` — that CDN changed and broke page load. Do NOT load it without `defer` — it blocks the page.
- The Supabase URL and anon key are hardcoded in `index.html` — they are public-safe (anon key, RLS-protected).

### Backend
- **Supabase** (cloud PostgreSQL + Auth + RLS)
- **Deno Edge Functions** in `supabase/functions/` — serverless TypeScript
- No traditional server; all backend logic lives in edge functions or Supabase RLS policies

### Deployment
- Frontend: Push to `main` → GitHub Pages auto-deploys
- Edge functions: Deployed manually to Supabase (`supabase functions deploy <name>`)
- DB migrations: Applied via Supabase dashboard or CLI (`supabase db push`)

### Local Development
- **Must serve from localhost**, not opened as `file://`. Supabase JS v2 uses an iframe for cross-tab session locking that the browser blocks under `file://` unique-origin rules — `signInWithPassword()` hangs indefinitely.
- Start a local server: `python -m http.server 8080` then open `http://localhost:8080`

---

## Key Files

| File | Purpose |
|------|---------|
| `index.html` | Entire frontend — UI, auth, all business logic |
| `supabase/functions/_shared/cors.ts` | CORS headers (origin-restricted) + JSON response helpers |
| `supabase/functions/_shared/auth.ts` | Shared caller JWT + profile/role verification for edge functions |
| `supabase/functions/_shared/greatsoftClient.ts` | GreatSoft OAuth 2.0 client + API wrapper (caches token) |
| `supabase/functions/greatsoft-test-connection/index.ts` | Edge fn: test GreatSoft credentials (manager+ only) |
| `supabase/functions/greatsoft-generate-time-entries/index.ts` | Edge fn: generate and push time entries (live push manager+ only) |
| `supabase/functions/notifications-daily/index.ts` | Edge fn: overdue/budget digest; requires `x-cron-secret` header or manager+ JWT |
| `supabase/migrations/` | Additive SQL migrations (never destructive) |
| `supabase/migrations/20260620000000_gs_mapping_tables.sql` | GS employee/audit/section/activity code tables + 127 activity code seed rows |
| `supabase/migrations/20260620000001_tax_tb_tables.sql` | Tax TB tables (gs_tax_codes, gs_tb_mapping, tax_tb_imports, tax_tb_lines) — **not yet applied to production** |
| `supabase/migrations/20260620000003_auth_user_trigger.sql` | Auth trigger: auto-creates `public.users` profile on auth user creation with correct `id`; unique index on `email` |
| `supabase/security/rls_hardening_staging.sql` | RLS policies — test in staging before applying to prod |
| `docs/security-hardening.md` | Role/access design and RLS test checklist |
| `docs/greatsoft-integration-plan.md` | GreatSoft mapping and rollout plan |
| `Future_Improvements.md` | Planned features with implementation status |
| `_headers` | CDN/Netlify cache-control headers |

---

## Database Schema

Core tables: `users`, `audits`, `sections`, `subsections`, `step_logs`, `timesheet_entries`, `settings`
Integration tables: `greatsoft_time_pushes`
GS mapping tables: `gs_employee_codes`, `gs_audit_codes`, `gs_section_codes`, `gs_activity_codes`, `gs_subsection_activity_map`
Tax TB tables: `gs_tax_codes`, `gs_tb_mapping`, `tax_tb_imports`, `tax_tb_lines` *(migration written, not yet applied to production)*
Audit logging: `security_audit_log`

**SQL helper functions** (defined in migration `20260612152000_*`):
- `public.current_user_email()` — logged-in user's email
- `public.current_user_role()` — logged-in user's role
- `public.is_tyron()` — checks for super-admin (tyron@hvns.co.za)
- `public.is_manager()` — true for manager or tyron
- `public.is_director()` — true for director role
- `public.can_view_reports()` — true for manager/director/tyron
- `public.handle_new_auth_user()` — SECURITY DEFINER trigger function; auto-inserts `public.users` row (id=auth.uid, role=staff, active=false) on Supabase Auth user creation
- `public.section_has_assignee_subsection(section_id, email)` — SECURITY DEFINER; used in `sections_select_visible` to check if any subsection of the section is assigned to the user, without triggering RLS on `subsections` (breaks mutual recursion)
- `public.subsection_parent_section_assignee(section_id, email)` — SECURITY DEFINER; used in `subsections_select_visible` to check if the parent section is assigned to the user, without triggering RLS on `sections` (breaks mutual recursion)

**Migration strategy:** Always additive — new nullable columns or new tables only. Never drop or rename columns without explicit sign-off.

**Pending migration:** `20260703000000_security_fixes.sql` (step_logs/timesheet identity + assignment checks, users identity-guard trigger, auth-trigger collision handling, missing DELETE policies, subsections column guard for assignees, greatsoft_time_pushes manager policies) — written 2026-07-03, not yet applied to production. All earlier migrations applied as of 2026-06-21.

To apply future migrations: Supabase Dashboard → SQL Editor → paste and run each file in order.

---

## User Roles & Permissions

| Role | Create Audits | Edit Audits | Manage Users | View Reports | Log Time |
|------|:---:|:---:|:---:|:---:|:---:|
| `tyron` (super admin) | ✓ | ✓ | ✓ | ✓ | ✓ |
| `manager` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `director` | ✗ | assigned only | ✗ | ✓ | ✓ |
| `staff` | ✗ | ✗ | ✗ | ✗ | own only |

`tyron@hvns.co.za` bypasses normal role restrictions in the frontend and in Supabase helper functions. Do not add other hardcoded email bypasses without a security review.

---

## GreatSoft Integration

GreatSoft is the firm's external time-billing system. Integration is via OAuth 2.0 + REST API.

**Time entries data mapping:**
- Audit → Client (code, name)
- Section → Task (id, code, name)
- Subsection → Activity (overhead id, code, name)
- `step_log` hours → Time entry (`WIPHrQty`)

**Tax TB data mapping (planned):**
- CaseWare map number → GS tax code (via global `gs_tb_mapping` dictionary)
- TB lines push via `POST /api/Tax/TBImport` (TBImportDTO — structure still needed from GreatSoft)

**Safety — double-lock:**  
The `greatsoft-generate-time-entries` edge function will only push live entries when **both** conditions are true:
1. The caller passes `{ dryRun: false }` in the request body
2. The `GREATSOFT_PUSH_ENABLED` environment secret is set to exactly `"true"`

Default behaviour is dry-run (preview only). Never change this default without explicit instruction. Live pushes additionally require the caller to have a manager-tier role (`manager`/`director`/`tyron`); staff can only dry-run their own entries. Live pushes additionally require a manager-tier caller role (`manager`/`director

---

## Tax TB Feature

CaseWare Trial Balance import workflow:
1. User selects audit + enters tax year-end date → uploads CW TB Excel file
2. `parseCWTB()` scans first 25 rows for a date (Date object or text pattern) and cross-checks it against the entered year-end; warns on mismatch
3. Lines with a dot-separated map number (e.g. `1.1.1.100.100.100.200.100`) are extracted with description + consolidated amount
4. Global `gs_tb_mapping` dictionary auto-matches CW map numbers to GS tax codes; user can override per line
5. Push to GreatSoft via edge function (not yet built — awaiting TBImportDTO from GreatSoft)

`gs_tb_mapping` is global — mapping a CW map number once applies it to ALL future clients automatically.

---

## Archive and Rollover

Both features live in the Edit view (Details card) alongside the Save button:

- **Archive** (`archiveAudit(id)`): sets `archived=true`; removes audit from all active views. Irreversible from the UI — user must confirm.
- **Rollover** (`rolloverAudit(id)` / `doRollover()`): creates a new audit copying all sections and subsections. Steps reset to "Not Started", logged hours cleared, dates shifted +1 year, GS activity mappings carried over. New audit opens immediately in Edit view.

---

## Environment Variables / Secrets

Stored as Supabase project secrets (never committed to git):

| Secret | Purpose |
|--------|---------|
| `SUPABASE_URL` | Project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Server-side DB access (edge functions only) |
| `GREATSOFT_BASE_URL` | GreatSoft API base (e.g. `https://crm.gscloud.co.za/rest`) |
| `GREATSOFT_TOKEN_URL` | OAuth token endpoint |
| `GREATSOFT_CLIENT_ID` | OAuth client ID |
| `GREATSOFT_CLIENT_SECRET` | OAuth client secret |
| `GREATSOFT_SCOPE` | OAuth scope string |
| `GREATSOFT_PUSH_ENABLED` | Must be `"true"` to allow live pushes |
| `NOTIFICATIONS_CRON_SECRET` | Shared secret for the `notifications-daily` cron caller (`x-cron-secret` header) |

The frontend uses the **anon key** only (`SKEY` in `index.html`) — this is safe to be public.

---

## Development Workflow

### Frontend changes
1. Edit `index.html`
2. Serve locally: `python -m http.server 8080` → open `http://localhost:8080` (never `file://`)
3. Test the changed feature manually — there are no automated tests
4. Commit and push to `main` to deploy

### Edge function changes
1. Edit files under `supabase/functions/`
2. Test locally with Supabase CLI: `supabase functions serve`
3. Deploy: `supabase functions deploy <function-name>`

### Database changes
1. Write a new additive migration SQL file in `supabase/migrations/` with timestamp prefix
2. Test on a staging Supabase project first using `supabase/security/rls_hardening_staging.sql` as a pattern
3. Apply to production: Supabase Dashboard → SQL Editor, or `supabase db push`

### Testing
No automated test suite. Manual testing checklist lives in `docs/security-hardening.md`. For GreatSoft, always run in dry-run mode first and verify the preview output before enabling live pushes.

---

## Code Conventions

- **Frontend:** Vanilla JS, no TypeScript, no bundler. Keep all code in `index.html`.
- **Edge functions:** Deno + TypeScript. Share utilities via `supabase/functions/_shared/`.
- **SQL:** Snake_case table and column names. All new tables need RLS enabled.
- **Variable names in `index.html`:** Short/minified style (e.g. `sb`, `SURL`, `SKEY`) — this is intentional, do not expand without asking.
- **No comments** unless the reason is non-obvious. Do not add JSDoc or block comment explanations.
- **No new dependencies** without discussion — frontend CDN scripts are: Supabase JS v2 and SheetJS xlsx@0.18.5 only.

---

## Security Notes

- RLS is **live in production** on all tables as of 2026-06-20. Migration: `20260620000002_rls_main_tables.sql`.
- The staging script `supabase/security/rls_hardening_staging.sql` is now superseded — use the migration file as the source of truth.
- All role checks rely on `public.current_user_email()` and `public.current_user_role()` in RLS policies (SECURITY DEFINER, bypass RLS safely).
- **Critical RLS invariant:** `public.users.id` must equal the user's `auth.uid()`. The `handle_new_auth_user` trigger enforces this for all new users. If a user can't log in (profile fetch returns 0 rows), check that their `public.users.id` matches their `auth.users.id`.
- The `security_audit_log` table exists but is not yet written to from the frontend.
- Do not introduce additional `SECURITY DEFINER` functions or bypass RLS without explicit review.
- Do not store PII beyond what's already in `users` (email, display name, role).
- `.gitignore` excludes `*.xlsx`, `*.xls`, `*.csv` — company-sensitive data must never be committed.
- Supabase client uses `storageKey: 'hvns-audit-pro'` to namespace session storage and avoid stale lock conflicts in development.

## User Management

**Adding a new user (in-app flow):**
1. Create user in **Supabase Auth → Users → Add user** — the `on_auth_user_created` trigger auto-creates a `public.users` profile (role=staff, active=false, name=email prefix)
2. Open **User Management → Add User** → enter email + full name + role + dept → Save Profile — this updates the trigger-created row with the correct details and activates the account
3. User can now log in — their `public.users.id` will correctly match `auth.uid()`

**Editing existing users:** Name is editable inline in the User Management table (`updName()`). Role and department have inline dropdowns (`updRole()`, `updDept()`). Activate/Deactivate toggles `active`.

**If a user can't log in:** Their `public.users.id` may not match `auth.uid()` (possible if created before the trigger was in place). Fix via Supabase SQL Editor:
```sql
UPDATE public.users pu SET id = au.id
FROM auth.users au WHERE au.email = pu.email AND pu.id != au.id;
```

## Workload View

`vWorkload()` queries `subsections` directly (not a view) with a separate `step_logs` fetch for actual hours. Do not replace this with a `subsection_summary` view dependency — that view had security/RLS issues after RLS was applied to the underlying tables and is no longer used.
