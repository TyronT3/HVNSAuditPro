# HVNSAuditPro — CLAUDE.md

## Project Overview

**HVNSAuditPro** is a web-based audit engagement tracker for HVNS & Company (an audit and assurance firm). It lets managers create and assign audit engagements, track time logged against subsections, and push time entries to GreatSoft (the firm's external time-billing system).

**Live URL:** `https://tyront3.github.io/HVNSAuditPro/`
**Branches:** `main` (production, auto-deploys to GitHub Pages), `backend_scaffold` (active dev)

---

## Architecture

### Frontend
- **Single file SPA:** `index.html` — all HTML, CSS, and JavaScript is inline in this one file (~1,100 lines). No build step, no framework. Do not split it into separate files without explicit instruction.
- **Auth:** Supabase Auth (email/password). Redirect URL points to the GitHub Pages URL.
- **Database client:** `@supabase/supabase-js@2` loaded via CDN.
- The Supabase URL and anon key are hardcoded in `index.html` — they are public-safe (anon key, RLS-protected).

### Backend
- **Supabase** (cloud PostgreSQL + Auth + RLS)
- **Deno Edge Functions** in `supabase/functions/` — serverless TypeScript
- No traditional server; all backend logic lives in edge functions or Supabase RLS policies

### Deployment
- Frontend: Push to `main` → GitHub Pages auto-deploys
- Edge functions: Deployed manually to Supabase (`supabase functions deploy <name>`)
- DB migrations: Applied via Supabase dashboard or CLI (`supabase db push`)

---

## Key Files

| File | Purpose |
|------|---------|
| `index.html` | Entire frontend — UI, auth, all business logic |
| `supabase/functions/_shared/cors.ts` | CORS headers + JSON response helpers |
| `supabase/functions/_shared/greatsoftClient.ts` | GreatSoft OAuth 2.0 client + API wrapper |
| `supabase/functions/greatsoft-test-connection/index.ts` | Edge fn: test GreatSoft credentials |
| `supabase/functions/greatsoft-generate-time-entries/index.ts` | Edge fn: generate and push time entries |
| `supabase/migrations/` | Additive SQL migrations (never destructive) |
| `supabase/security/rls_hardening_staging.sql` | RLS policies — test in staging before applying to prod |
| `docs/security-hardening.md` | Role/access design and RLS test checklist |
| `docs/greatsoft-integration-plan.md` | GreatSoft mapping and rollout plan |
| `_headers` | CDN/Netlify cache-control headers |

---

## Database Schema

Core tables: `users`, `audits`, `sections`, `subsections`, `step_logs`, `timesheet_entries`, `settings`
Integration tables: `greatsoft_time_pushes`
Audit logging: `security_audit_log`

**SQL helper functions** (defined in migration `20260612152000_*`):
- `public.current_user_email()` — logged-in user's email
- `public.current_user_role()` — logged-in user's role
- `public.is_tyron()` — checks for super-admin (tyron@hvns.co.za)
- `public.is_manager()` — true for manager or tyron
- `public.is_director()` — true for director role
- `public.can_view_reports()` — true for manager/director/tyron

**Migration strategy:** Always additive — new nullable columns or new tables only. Never drop or rename columns without explicit sign-off.

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

**Data mapping:**
- Audit → Client (code, name)
- Section → Task (id, code, name)
- Subsection → Activity (overhead id, code, name)
- `step_log` hours → Time entry (`WIPHrQty`)

**Safety — double-lock:**  
The `greatsoft-generate-time-entries` edge function will only push live entries when **both** conditions are true:
1. The caller passes `{ dryRun: false }` in the request body
2. The `GREATSOFT_PUSH_ENABLED` environment secret is set to exactly `"true"`

Default behaviour is dry-run (preview only). Never change this default without explicit instruction.

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

The frontend uses the **anon key** only (`SKEY` in `index.html`) — this is safe to be public.

---

## Development Workflow

### Frontend changes
1. Edit `index.html`
2. Open directly in browser (or use a local static server)
3. Test the changed feature manually — there are no automated tests
4. Commit and push to `main` to deploy

### Edge function changes
1. Edit files under `supabase/functions/`
2. Test locally with Supabase CLI: `supabase functions serve`
3. Deploy: `supabase functions deploy <function-name>`

### Database changes
1. Write a new additive migration SQL file in `supabase/migrations/` with timestamp prefix
2. Test on a staging Supabase project first using `supabase/security/rls_hardening_staging.sql` as a pattern
3. Apply to production: `supabase db push`

### Testing
No automated test suite. Manual testing checklist lives in `docs/security-hardening.md`. For GreatSoft, always run in dry-run mode first and verify the preview output before enabling live pushes.

---

## Code Conventions

- **Frontend:** Vanilla JS, no TypeScript, no bundler. Keep all code in `index.html`.
- **Edge functions:** Deno + TypeScript. Share utilities via `supabase/functions/_shared/`.
- **SQL:** Snake_case table and column names. All new tables need RLS enabled.
- **Variable names in `index.html`:** Short/minified style (e.g. `sb`, `SURL`, `SKEY`) — this is intentional, do not expand without asking.
- **No comments** unless the reason is non-obvious. Do not add JSDoc or block comment explanations.
- **No new dependencies** without discussion — the frontend loads only the Supabase CDN script.

---

## Security Notes

- RLS is **not yet enabled** on main app tables in production (it's ready in `rls_hardening_staging.sql` — apply after staging validation).
- All role checks rely on `public.current_user_email()` and `public.current_user_role()` in RLS policies.
- The `security_audit_log` table records sensitive mutations.
- Do not introduce `SECURITY DEFINER` functions or bypass RLS without explicit review.
- Do not store PII beyond what's already in `users` (email, display name, role).
