# HVNSAuditPro — Project Context

*A complete reference for what this project is, how it's built, and what it does. Last compiled 2026-07-10.*

---

## 1. What this is

**HVNSAuditPro** is a web-based audit engagement tracker built for **HVNS & Company**, a South African audit and assurance firm. It replaces spreadsheets for:

- Creating and structuring audit engagements and accounting projects (sections → subsections, each with an assignee, due date, and budget hours)
- Tracking work through a 7-step workflow per subsection, with time logged against each step
- Giving managers/directors live dashboards, capacity/workload views, calendars, Gantt timelines, budget-overrun alerts, and analytics
- Reconciling app-logged hours against the firm's external time-tracking system on a weekly basis
- (In progress) pushing time entries into **GreatSoft**, the firm's external billing/practice-management system
- (In progress) importing CaseWare Trial Balance exports for tax return (ITR14) preparation and mapping to GreatSoft tax codes

**Live URL:** `https://tyront3.github.io/HVNSAuditPro/`
**Branches:** `main` (production, auto-deploys to GitHub Pages), `backend_scaffold` (active dev)
**Owner/super-admin:** `tyron@hvns.co.za`

---

## 2. Architecture

### Frontend
- **Single file SPA**: `index.html` (~2,700 lines) — all HTML, CSS, and JavaScript inline. No build step, no framework, no bundler. All view rendering is done via string templating into a `#main` div (`setMain()`), dispatched from one big `renderView()` switch on the global `CV` (current view) variable.
- **Auth**: Supabase Auth (email/password), with a password-reset flow and in-app password change.
- **DB client**: `@supabase/supabase-js@2` via CDN, using the public anon key (safe — RLS-protected).
- **Excel/CSV**: `xlsx@0.18.5` (SheetJS) via `cdn.jsdelivr.net`, loaded with `defer`. Used for CSV audit-plan import/export, weekly timesheet Excel export, and CaseWare Trial Balance import.
- No-cache meta tags force the browser to always fetch the latest deployed `index.html`.
- Mobile-responsive: hamburger nav, collapsing stat grid, shrunk calendar cells.

### Backend
- **Supabase**: cloud PostgreSQL + Auth + Row-Level Security + Deno Edge Functions. No traditional server — all backend logic lives in RLS policies, SQL helper functions/views, and edge functions.
- Frontend never uses elevated privileges; all writes go through RLS-checked queries or auth-gated edge functions using a service-role client.

### Deployment
- Frontend: push to `main` → GitHub Pages auto-deploys (`_headers` disables all caching).
- Edge functions: deployed manually (`supabase functions deploy <name>`).
- DB migrations: applied manually via Supabase Dashboard → SQL Editor, in filename order (no CI/CD migration runner).

### Local development
- Must be served from `http://localhost` (not `file://`) — Supabase JS v2 uses a cross-tab session-lock iframe that browsers block under `file://` unique-origin rules, causing `signInWithPassword()` to hang.
- `python` is not usable on this machine (Windows Store stub) — use a Node-based static server instead (e.g. `npx serve` or similar).

---

## 3. Data model

Core tables (created before the migration system existed, via Supabase Table Editor):

| Table | Purpose |
|---|---|
| `users` | Profile row per person: `id` (must equal `auth.uid()`), `email`, `full_name`, `role` (`staff`/`manager`/`director`), `department` (`audit`/`accounting`/`both`), `active` |
| `settings` | Key/value store — `firm_rate` (hourly rate for fee calc), `firm_name` |
| `audits` | An engagement: `name`, `client`, `type` (`audit`/`accounting`), `group_id`, `due_date`, `firm_rate`, `archived`, `created_by` |
| `sections` | A phase/area of an audit: `audit_id`, `name`, `assignee_email`, `due_date`, `sort_order` |
| `subsections` | A work item: `section_id`, `name`, `assignee_email`, `co_assignees[]`, `due_date`, `budget_hours`, `step`, `notes`, `comment`, `hidden_from_worklist`, `sort_order` |
| `step_logs` | Append-only time ledger: `subsection_id`, `step`, `hours`, `note`, `logged_by`, `logged_by_email`, `logged_at`. **Actual hours are always derived by summing this table** — never stored directly on a subsection. |
| `timesheet_entries` | Weekly reconciliation: `subsection_id`, `week_ending`, `firm_system_hours`, `app_hours`, `explanation`, `submitted_by`, `status` (`pending`/`reviewed`/`flagged`) |
| `client_groups` | Parent grouping of related audits (e.g. companies under one holding structure) |

GreatSoft mapping tables: `gs_employee_codes`/`gs_employee_map`, `gs_audit_codes`/`gs_audit_map`, `gs_section_codes`/`gs_section_map`, `gs_activity_codes` (127 seeded activity codes), `gs_subsection_activity_map`, `greatsoft_time_pushes` (push log/status).

Tax TB tables (migration written, applied): `gs_tax_codes` (global tax code reference, ~11 seeded — Micro Business only, full ITR14 list still pending), `gs_tb_mapping` (global CaseWare map number → GS tax code, reusable across all clients), `tax_tb_imports`, `tax_tb_lines`.

Other: `security_audit_log` (exists, not yet written to), `notification_log` (daily digest run log, tyron-only read).

**Derived/summary views** (Postgres views with `security_invoker = true` so RLS applies correctly): `subsection_summary`, `section_summary`, `audit_summary`, `timesheet_variance_summary`. These pre-compute `actual_hours` (sum of `step_logs`), `hours_variance`, `fee_value`, and `progress_pct` — the frontend relies on these instead of joining/summing client-side.

**Relationships**: `audits 1—n sections 1—n subsections 1—n step_logs`. Assignee fields are plain email strings (not FKs) matched against `users.email` — the UI flags "unregistered assignee ⚠️" when an email doesn't match an active user. `audits.group_id` → `client_groups.id`.

**SQL helper functions** (all `SECURITY DEFINER`, used inside RLS policies): `current_user_email()`, `current_user_role()`, `is_tyron()` (hardcoded email check), `is_manager()`, `is_director()`, `can_view_reports()`, `handle_new_auth_user()` (auto-creates a `public.users` row on signup), `section_has_assignee_subsection()` / `subsection_parent_section_assignee()` (break mutual-recursion in RLS between `sections` and `subsections`).

---

## 4. The 7-step workflow

Every subsection moves through a fixed pipeline (`STEPS` array), color-coded consistently across every view:

`Not Started → Client Requested → Client Received → Processing → Finalising → Review → Signed Off`

- Staff/assignees can advance a step forward (`reqAdv`), log hours without advancing (`reqLogOnly`), or move back one step (`regressStep`).
- Only a **manager** can jump directly to any step (`jumpStep`) or **sign off** (`signOff`) — signing off requires the item be at `Review` and stamps a 0-hour audit-trail `step_logs` row.
- Time is logged per step-advance via a universal "Log Time" modal, which also warns about hours already logged at the current step and remaining budget.

---

## 5. Views / navigation

Nav items are built dynamically per role in `buildNav()`. Roughly:

| View | Who | What it does |
|---|---|---|
| **Dashboard** | everyone | Stat tiles (audits, overdue, at-risk, fee value); manager-only budget/actual detail toggle; manager/director "Today's Time Logging" roster; drill-down audit → section → subsection tree with progress bars, step badges, inline editing (manager) |
| **New** (Add) | manager | 2-step wizard: name/client/group/due date + optional CSV import, then tick standard sections from the `STPLS` template library or review CSV-imported structure, assign staff/dates/budget |
| **Edit** | manager | Full CRUD: details, distribution view, sync assignees, rollover, archive; per-section/subsection assignee/due/hours/GS-mapping/notes editing; add sections/subsections; auto-match GreatSoft activities |
| **My Updates** | everyone except director | Personal worklist grouped by audit (Active / 0-hours / Completed), search, step trail, start/stop timer, log hours, advance/regress step, Teams-message copy, notes, hide-from-worklist |
| **Calendar** | everyone | Month grid of due dates color-coded by step; click-a-day detail; grouped upcoming-deadline buckets (overdue/today/this week/next week/2–4 weeks) |
| **Timeline** (Gantt) | everyone | Custom-built Gantt: section rows, subsection bars sized from budget hours, "today" marker, "⟳ waiting" flag when a prior sequential item isn't signed off |
| **Capacity** | everyone (staff see own only) | Weekly heatmap; backward-fills each person's remaining hours from due date at a 40h/week ceiling so work compresses toward deadlines; flags un-placeable overflow |
| **Workload** | everyone (staff see own only) | Per-staff cards: totals, done/overdue/at-risk counts, actual vs budget, progress %, expandable item table |
| **Overruns** | manager/director | Over-budget items and "Near Limit" items (≥80%, <100% of budget used) |
| **Analytics** | manager/director | By-Audit (budget/actual/variance/completion) and By-Person (with All-Time/90-day/30-day filter) views |
| **Log History** | manager/director | Per-person, per-weekday hours-logged heatmap (7/14/30-day toggle), timesheet-submission markers |
| **Groups** | manager/director | Client Groups with combined budget/actual/fee/progress roll-ups; create/rename/delete (manager) |
| **Tax TB** | tyron only | CaseWare Trial Balance import/mapping workspace (see §7) |
| **Users** | manager | User management: inline name/role/department edit, activate/deactivate, add-user flow |
| **Settings** | manager | Firm hourly rate, firm name |
| *(orphaned)* Timesheet reconciliation | staff (own history) / manager+director (firm-wide) | Reachable only via `goView('timesheet')` after submitting a weekly reconciliation — not in the nav bar |

### Notable modals
Log Time, Workload Distribution, Time Log Entries (with delete), Assignment Changes (login-time diff alert), Time Logging Reminder (nags after ≥2 idle working days), Weekly Time Reconciliation (variance-explanation required), Reassign, Add Subsection, Teams Message (copy-paste status update), generic Report viewer (CSV export + printable client PDF report), Change Password, Add User Profile, Forgot Password, Export My Time (weekly Excel), Rollover to Next Year.

---

## 6. Roles & permissions

| Role | Create/Edit Audits | Manage Users | View Reports | Log Time |
|---|:---:|:---:|:---:|:---:|
| `tyron` (super admin) | ✓ | ✓ | ✓ | ✓ |
| `manager` | ✓ | ✓ | ✓ | ✓ |
| `director` | assigned only | ✗ | ✓ | ✓ |
| `staff` | ✗ | ✗ | ✗ | own only |

- **`tyron@hvns.co.za`** bypasses normal restrictions everywhere (frontend and DB helper functions via `is_tyron()`), and gets an exclusive **role-impersonation dropdown** in the header (👑 Admin/Manager, 👁 Director View, 👁 Staff View) to preview other roles' experiences without changing his actual DB role.
- **Director** has no "New"/"Edit"/"Users"/"Settings" access and — notably — no "My Updates" tab either (it's a pure oversight/reporting role with update rights only on directly assigned items).
- Every role-sensitive UI check has a matching RLS policy server-side — the frontend restrictions are UX convenience, not the security boundary.

---

## 7. Feature deep-dives

### GreatSoft integration (partially built, not yet functional)
GreatSoft is the firm's external OAuth2-based practice-management/billing API (`crm.gscloud.co.za`). Mapping: Audit→Client, Section→Task, Subsection→Activity, `step_logs.hours`→time entry (`WIPHrQty`).

- **Built**: `_shared/greatsoftClient.ts` (OAuth token caching, generic fetch wrapper), edge function `greatsoft-test-connection` (manager+ only, read-only connectivity check), edge function `greatsoft-generate-time-entries` (dry-run preview or live push of `step_logs` as GreatSoft time entries), GS activity-code catalogue + auto-matching UI in the Edit view.
- **Safety double-lock** on live pushes: the request must pass `{dryRun: false}` **and** the Supabase secret `GREATSOFT_PUSH_ENABLED` must be exactly `"true"`. Default is always dry-run. Live pushes additionally require a manager-tier caller.
- **Duplicate-billing guard**: if a GreatSoft push succeeds but the local `greatsoft_time_pushes` record fails to save, the function aborts the rest of the batch rather than risk re-pushing (and double-billing) that entry on retry.
- **Current blocker**: the firm has **not yet obtained working GreatSoft API credentials** — `GREATSOFT_*` secrets are unset in Supabase, so both edge functions will error if invoked. They're deployed but effectively dormant. The frontend does not yet call them (no `functions.invoke` wired up).

### Tax TB (CaseWare Trial Balance import — tyron only)
1. User picks an audit + enters tax year-end, uploads a CaseWare TB Excel export.
2. `parseCWTB()` scans the first 25 rows for an embedded date and cross-checks it against the entered year-end (warns on mismatch, with an override).
3. Lines with a dot-separated map number are extracted with description + consolidated amount.
4. A global `gs_tb_mapping` dictionary auto-suggests a GS tax code per CW map number (learned once, applies to all future clients); user can override per line.
5. Push to GreatSoft is UI-scaffolded but explicitly disabled — blocked on GreatSoft providing the `TBImportDTO` structure for `POST /api/Tax/TBImport`.
6. Only ~11 "Micro Business" GS tax codes are seeded; the full ITR14 code list is still pending (needs a screenshot from GreatSoft's TB import tool).

### Notifications
- `notifications-daily` edge function: dual-auth (either `x-cron-secret` header or a manager+ JWT), builds a digest of overdue subsections (grouped by assignee) and budget-status buckets (near-budget ≥80%, over-budget ≥100%, from the `audit_summary` view), logs a row to `notification_log`. **Email sending is not yet wired up** (payload is built as "the contract for the Resend integration step"; `emailsQueued: 0`).
- In-app equivalents run client-side at login: `checkAssignmentChanges()` (diffs newly-assigned/removed work vs a localStorage snapshot) and `checkOwnLoggingGap()` (nags if ≥2 working days have passed with no logged hours).

### Weekly timesheet reconciliation
Staff pick a subsection + week-ending Friday; the app auto-fills "App Hours" from summed `step_logs`; the user enters "Firm System Hours" from the external timekeeping tool; any variance forces a mandatory explanation before submit. One submission per subsection/week/user is enforced. Managers/directors see a firm-wide table with flag/approve actions.

### Capacity smoothing algorithm
Deliberately backward-fills each person's *remaining* hours (budget − logged) week-by-week from each item's due date, capped at 40h/week per person, so visible workload compresses toward deadlines rather than dumping everything into the assignment week. Un-placeable overflow (can't fit even filling every week back to today) is dumped into the current week and flagged.

### Archive & Rollover
- **Archive**: sets `audits.archived = true`; hides the audit from essentially every active view. Irreversible from the UI.
- **Rollover**: deep-copies an audit (sections, subsections, GS activity mappings) into a new audit, shifting all dates +1 year and resetting every step to `Not Started` with hours cleared (achieved by simply not copying `step_logs`).

### Other UX details
- Live floating timer widget (persists across views via `localStorage`, auto-stops at 16:30 daily).
- Skeleton loaders on every async view.
- Consistent step color-coding, due-date badges (overdue/due-today/days-left), risk flags (🔴 overdue / 🟡 at risk), toast notifications instead of blocking alerts.
- Client-facing printable PDF report, styled distinctly from the internal app UI (separate print window, letterhead-style CSS).
- Co-assignees: reassigning a section/subsection rolls the previous assignee into a `co_assignees[]` array so visibility/history isn't lost; a manager can bulk-sync a section's assignee down to all its subsections.
- Two distinct free-text fields per subsection: `notes` (manager-authored, visible to the whole team — "documents required") vs `comment` (either party — "visible to your manager").

---

## 8. Security posture

- **RLS is live in production on every table** (since 2026-06-20). All role logic is enforced server-side via the SQL helper functions above, not just in the frontend.
- Recent hardening (2026-07-03 batch): closed identity-spoofing gaps in `step_logs`/`timesheet_entries` inserts (own-identity checks tightened from OR to AND), added a `protect_user_identity()` trigger (prevents non-tyron changes to the tyron row or to `id`/`email`), added a `protect_subsection_columns()` trigger (non-managers can only touch `step`/`comment`/`notes`, not budget/due-date/assignee), added missing DELETE policies (previously implicitly denied to everyone).
- Email case normalization (2026-07-03): all emails lowercased on write via triggers, with a one-time backfill, to prevent assignment-visibility bugs from case mismatches.
- `security_audit_log` table exists but nothing writes to it yet — flagged as still-partial in `Future_Improvements.md`.
- `.gitignore` excludes `*.xlsx`/`*.xls`/`*.csv` (client financial data) and `/local-sql/` (one-off backfill scripts) — several such files exist locally in the repo root but should never be committed.
- `_headers` disables all caching for the GitHub Pages-hosted SPA.

---

## 9. Current status / known gaps (as of 2026-07-10)

- **Migrations**: everything through `20260707000000_client_groups.sql` is applied to production. Nothing currently pending (the earlier-pending `20260706000000_subsection_hidden_flag.sql` has since been applied).
- **GreatSoft**: edge functions deployed and hardened, but non-functional — the firm doesn't yet have working GreatSoft API credentials.
- **Tax TB**: import/mapping UI complete; push to GreatSoft blocked on GreatSoft providing the `TBImportDTO` structure; full ITR14 tax code list still needs to be sourced.
- **Not built** (per `Future_Improvements.md`): client-facing branded report beyond the existing internal CSV/PDF export, dedicated utilisation-% report, undo-delete, manager summary email, dark mode, audit-log writes, saved custom audit templates (beyond the built-in `STPLS` defaults + rollover).
- **No automated test suite** — all testing is manual; a checklist lives in `docs/security-hardening.md`.

---

## 10. Key files reference

| File | Purpose |
|---|---|
| `index.html` | Entire frontend |
| `supabase/functions/_shared/cors.ts` | Origin-restricted CORS headers + JSON response helper |
| `supabase/functions/_shared/auth.ts` | Shared caller JWT + profile/role verification |
| `supabase/functions/_shared/greatsoftClient.ts` | GreatSoft OAuth client + API wrapper |
| `supabase/functions/greatsoft-test-connection/` | Manager+ connectivity check |
| `supabase/functions/greatsoft-generate-time-entries/` | Dry-run/live time-entry push |
| `supabase/functions/notifications-daily/` | Overdue/budget digest (cron or manual) |
| `supabase/migrations/` | Chronological, additive SQL migrations |
| `supabase/security/rls_hardening_staging.sql` | Superseded RLS reference/pattern |
| `docs/security-hardening.md` | Role/access design + manual test checklist |
| `docs/greatsoft-integration-plan.md` | GreatSoft rollout plan |
| `GreatSoft_API_Integration_Reference.md` | Full GreatSoft API/Swagger reference notes |
| `Future_Improvements.md` | Feature backlog with status |
| `local-sql/` | One-off, uncommitted data-backfill scripts |
