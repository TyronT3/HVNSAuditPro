# Project Review Memory

Last updated: 2026-07-16 (Step 6 complete)

## Review scope

- Review the entire project before deleting any potentially unused code.
- Identify UI/UX changes that make the product feel deliberate, professional, and easier to use.
- Identify security concerns that can realistically be addressed while remaining on Supabase's free tier.
- Do not delete uncertain code during the review.

## Working rules

- Update this file after every completed review step.
- Record evidence and distinguish confirmed findings from candidates requiring manual verification.
- Preserve the single-file `index.html` architecture and additive-only migration strategy unless explicitly instructed otherwise.
- Never record credentials, tokens, personal data, or sensitive customer data here.

## Progress

- [x] Step 1 — Repository inventory and applicable guidance
- [x] Step 2 — Potentially unused code trace
- [x] Step 3 — UI/UX review
- [x] Step 4 — Security review
- [x] Step 5 — Low-risk implementation
- [x] Step 6 — Verification and handoff

## Findings

### Step 1 — Repository inventory and guidance

- The product surface is a static single-file SPA (`index.html`, approximately 2,700 lines), six shared/edge TypeScript files, and 21 chronological SQL migrations.
- Other tracked surfaces are documentation, one GreatSoft API reference, one reference screenshot, `_headers`, `.claude/launch.json`, and Supabase link metadata.
- Existing-site guidance applies: preserve the current architecture and dependencies, improve the real audit workflow rather than rebuilding the site around generic dashboard chrome, and validate changes in the existing local flow.
- The worktree already contained untracked `AGENTS.md` and `PROJECT_CONTEXT.md`; these belong to the user and must be preserved. This review added only this journal at this stage.
- Ignored local files include real client spreadsheets/CSVs and `local-sql/ohlhorst_backfill.sql`. They were inventoried by filename only and intentionally not opened because they contain company/client data and are not application source.
- The deployment documentation is inconsistent: `PROJECT_CONTEXT.md` says all migrations through `20260707000000_client_groups.sql` are applied, while `AGENTS.md`/`CLAUDE.md` still describe `20260706000000_subsection_hidden_flag.sql` and Tax TB as pending. Production state must be confirmed before applying any new migration.
- `_headers` uses a Netlify-style header file, but the declared deployment target is GitHub Pages. Treat it as a likely inactive deployment artifact pending platform verification; do not delete it yet.

### Step 2 — Potentially unused code trace

Confirmed unused:

- `REAL_R` in `index.html` is assigned during app initialization and never read. It is the only confirmed dead named frontend state found by reference tracing.
- `cachedToken` in `_shared/greatsoftClient.ts` is read but never assigned. The token-cache branch is therefore dead and the documentation claiming token caching is inaccurate; this is better treated as a bug to fix than code to delete.

Unreachable or dormant — review product intent before deleting:

- The weekly timesheet reconciliation route is effectively unreachable. `renderView()` supports `CV === 'timesheet'`, but `buildNav()` never links it. `openTs()` is only exposed from inside `vTs()`, while the only programmatic `goView('timesheet')` occurs after `submitTs()`. From a fresh session there is no normal path to start the workflow. Prefer adding a deliberate entry point if the feature is wanted; otherwise remove the whole feature as one unit after sign-off.
- Product decision received 2026-07-16: the pilot weekly reconciliation feature is no longer used and must not be visible to any role. The current workflow is tracker time logging → Excel export → manual entry in GreatSoft, with direct Tracker-to-GreatSoft posting planned later. Keep the reconciliation code dormant during this pass and propose it as a reviewed whole-unit deletion; do not add it to navigation.
- `greatsoft-test-connection` and `greatsoft-generate-time-entries` have no frontend caller. They are deliberately deployed/scaffolded backend capabilities and may be invoked manually; do not delete while the GreatSoft rollout remains planned.
- `gs_employee_map`, `gs_audit_map`, and `gs_section_map` have no application caller. They are integration scaffolding, while `gs_activity_codes` and `gs_subsection_activity_map` are actively used by the Edit and rollover flows.
- `security_audit_log` is intentionally dormant: the table and read policy exist, but no application or edge function writes to it.
- `notifications-daily` and `notification_log` are not called by the frontend; they are a cron/manual digest scaffold and should be kept or retired together based on notification plans.
- `supabase/security/rls_hardening_staging.sql` is superseded by migrations and differs from current production policies. It is documentation/reference code, not executable current policy. Move to an archive or clearly mark obsolete before considering deletion.
- `screenshot - gs tax codes.png` has no repository reference. It appears to be historical source evidence for seed data; archive it rather than deleting until the tax-code source is confirmed elsewhere.
- `_headers` is probably ignored by GitHub Pages, but platform behavior must be verified before deletion.

Active or intentionally duplicated — do not delete casually:

- Every named frontend function has at least one caller, including inline event handlers; every static modal and UI ID is either referenced or directly event-driven.
- CSS classes `rm`, `rd`, and `rs` appear unreferenced to a text counter but are generated dynamically as `r` + role initial.
- Pairs such as `delSub`/`delSubE`, `updBud`/`updSubB`, and dashboard/edit add-subsection flows duplicate behavior across different screens. They can be consolidated later, but they are all active.
- Permanent `delAudit()` is active from the Dashboard despite the newer Archive flow. This is a product-risk inconsistency, not dead code; decide whether permanent deletion should remain available.
- `CLAUDE.md`, `AGENTS.md`, and `PROJECT_CONTEXT.md` overlap heavily and contain contradictory deployment/migration status. They are maintenance candidates, not runtime code.

### Step 3 — UI/UX review

What creates the generic/AI-generated feel:

- Navigation exposes roughly 14 peer-level destinations with emoji labels and no task-based grouping. Managers face a feature inventory rather than a clear work hierarchy.
- Nearly every surface is a rounded white card, colored pill, emoji label, or left-accent metric. Repeating the same visual emphasis removes hierarchy instead of creating it.
- Calibri and Trebuchet MS are mixed throughout; much of the typography is set inline. The UI feels assembled screen-by-screen rather than governed by one product system.
- There are approximately 780 inline `style` attributes, 36 direct `innerHTML` writes, 17 native `alert()` calls, and 10 native `confirm()` calls. This creates inconsistent spacing, feedback, and interaction behavior.
- Labels are inconsistent and terse (`New`, `Edit`, `My Updates`, `Pwd`), while many actions use icon-only buttons. Users must infer whether an action navigates, mutates immediately, opens a dialog, or is destructive.

Usability and accessibility issues:

- Several interactive `div`, `span`, and `label` elements are mouse-only (hamburger, forgot-password link, dashboard accordions, calendar days, group rows). They have no keyboard semantics, focus style, or state attributes.
- Dialogs have no focus trap, Escape handling, focus restoration, or `aria-modal`/labelling. Close buttons have no accessible labels.
- Desktop edit/detail grids use fixed four- and six-column layouts. The only mobile breakpoint adjusts a few global classes; many screen-specific grids therefore squeeze or rely on horizontal scrolling.
- Most mutations do not inspect Supabase errors and still show success toasts or refresh. This is both confusing and a data-integrity risk on slow or RLS-rejected writes.
- Destructive actions rely on browser confirms and are visually inconsistent. Dashboard permanent deletion competes with the safer archive workflow.
- The weekly timesheet reconciliation workflow was later confirmed as retired from the pilot and must remain hidden; the active export-for-GreatSoft workflow needs the clear entry point instead.

Recommended design direction:

- Use a restrained professional audit-workbench style: system UI typography, warm neutral canvas, navy as the primary action/navigation color, and orange only for focus/current-state accents.
- Move from a wrapped top tab strip to a grouped desktop sidebar with concise text labels: Work, Planning, Reports, Administration. Preserve a compact mobile menu.
- Make the first viewport role-specific: `Overview` for managers/directors and `My work` emphasis for staff, with one clear page title and supporting context before metrics.
- Reduce emoji to rare status signals; replace decorative emoji in navigation, headings, and primary buttons with text labels. Keep red/amber/green for actual risk/status only.
- Standardize controls and spacing through reusable CSS classes, then gradually remove inline styling screen by screen instead of attempting a risky one-shot rewrite.
- Add an accessible interaction baseline now: real buttons for toggles, visible focus rings, labelled dialog close buttons, Escape-to-close, and reduced-motion handling.
- Add common mutation helpers/loading states so saves cannot silently fail and double-submits are less likely.

Implementation scope judged safe for this pass:

- Refresh the global visual system and app shell without changing business logic.
- Group and rename navigation; keep the retired timesheet route hidden and make the Excel export-for-GreatSoft action explicit.
- Add page-level headings/context to the highest-traffic Dashboard and My Work views.
- Add keyboard/focus basics and reduce decorative emoji in the shell/navigation.
- Do not attempt to convert all 780 inline styles or replace every native confirmation in one pass; stage those changes by workflow.

### Step 4 — Security review

Production-state limitation:

- The repository contains contradictory statements about applied migrations. The local Supabase CLI is not installed, so production schema/policy state could not be verified read-only. Confirm the live migration list and current policies in the Supabase Dashboard before applying the migration produced by this review.

High-priority, free-tier-fixable findings:

1. Stored XSS and inline-handler injection risk in `index.html`.
   - The SPA renders trusted and user-controlled database values through string-built `innerHTML` in many places.
   - Some paths escape correctly, but others render raw section/subsection/audit/client/user/status values. Important examples include `staffOpts()`, CSV preview, My Work cards/groups, timesheet options, report rows, settings values, and status labels.
   - Database values are also interpolated into inline JavaScript event attributes with ad-hoc apostrophe removal. This is not a safe JavaScript-string encoding strategy.
   - The printable report writes an audit name unescaped inside the new document's `<title>`.
   - A staff member may be able to set an arbitrary `subsections.step` through the Data API if the live database lacks a step check constraint; several views then render `step` as raw HTML. Verify the live constraint and add a defensive allow-list constraint.
   - Fix with consistent HTML escaping, a dedicated inline-JavaScript argument encoder while handlers remain inline, and database allow-list constraints. Longer term, remove inline handlers and use DOM APIs/event delegation.

2. Staff can obtain fee/rate information despite the role model saying staff cannot view reports.
   - `settings_select_authenticated` exposes `firm_rate` to every authenticated user.
   - `subsection_summary`, `section_summary`, and `audit_summary` expose `fee_value`/`budget_fee` to staff for rows visible through RLS.
   - The Dashboard's fourth metric shows `Total Fee Value` unconditionally, even though per-row fee badges are hidden for staff.
   - Fix with staff-safe work-summary views that omit fee columns, restrict report-summary views to report viewers, restrict settings reads to report viewers, and point the staff Dashboard at the safe views.

3. Manager time-log identity can be forged through the Data API.
   - `step_logs_insert_own_or_manager` currently accepts any `logged_by` and `logged_by_email` whenever `public.is_manager()` is true.
   - The actual frontend always logs the current manager's identity, including the “on behalf” action, so there is no product need for arbitrary identity spoofing.
   - Require the caller identity fields to match for every insert; let manager status bypass only the assignment check.

4. Public SECURITY DEFINER helper RPCs can disclose assignment relationships.
   - `section_has_assignee_subsection(section_id, email)` and `subsection_parent_section_assignee(section_id, email)` accept caller-supplied email values and bypass RLS.
   - An authenticated caller can invoke them via RPC to test another person's assignment if they know/guess identifiers.
   - Minimal fix: require the supplied email to equal `current_user_email()` inside each existing function. Stronger future fix: move SECURITY DEFINER RLS helpers into an unexposed private schema, as current Supabase guidance recommends.

5. The subsection column guard is out of sync with product behavior.
   - `protect_subsection_columns()` allows non-managers to update `notes`, although project documentation describes notes as manager-authored.
   - It does not allow `hidden_from_worklist`, so the staff “remove from my list” feature is rejected after the hidden-column migration is applied.
   - Update the allow-list to `step`, `comment`, `hidden_from_worklist`, and `updated_at`; keep `notes` manager-only.

6. CSV/Excel exports need formula-injection protection.
   - User-controlled names, notes, and explanations can begin with `=`, `+`, `-`, or `@`. Quoting a CSV field does not reliably stop spreadsheet applications interpreting it as a formula.
   - Prefix risky exported text cells with an apostrophe before CSV generation. Keep XLSX cells explicitly typed as strings where relevant.

Important before enabling dormant integrations:

- GreatSoft's duplicate-push check is not atomic. Two concurrent live invocations can both observe “not pushed” and call GreatSoft before the unique local upsert detects the collision. Claim/reserve each `step_log_id` in the database before the external POST, and require manual reconciliation for failed claims.
- `_shared/greatsoftClient.ts` never assigns `cachedToken`, so every API call requests a new OAuth token. Fix the cache and avoid returning raw OAuth error payloads to clients.
- `greatsoft-test-connection` returns the raw `/api/Info` body. Keep this manager-only and confirm the body contains no configuration secrets before enabling it in UI.

Free-tier hardening options:

- Supabase confirms that browser Data API access with a publishable/anon key is appropriate when RLS and least-privilege grants are correct: https://supabase.com/docs/guides/database/secure-data
- RLS and `security_invoker` views are standard PostgreSQL/Supabase capabilities and do not require a paid plan: https://supabase.com/docs/guides/database/postgres/row-level-security
- TOTP MFA is free and enabled on all Supabase projects. Add enrollment/challenge UI, then enforce AAL2 for managers/directors in RLS and edge functions: https://supabase.com/docs/guides/auth/auth-mfa/totp
- Supabase supports hCaptcha and Cloudflare Turnstile for sign-in/reset abuse protection: https://supabase.com/docs/guides/auth/auth-captcha
- Raise the project minimum password length to at least 8 (prefer 12 for this internal system) and match the UI. Leaked-password protection is paid-only: https://supabase.com/docs/guides/auth/password-security
- The Free plan currently has only short auth/platform log retention and no automatic backups, single-session enforcement, or configurable session timeouts. Use the existing database audit-log table for durable application events and maintain a documented manual export/backup routine: https://supabase.com/pricing

Lower-priority or operational findings:

- The CDN scripts are not integrity-pinned and the Supabase script uses the moving `@2` major tag. Pin exact versions and add SRI when the release process can maintain hashes.
- A strong CSP is difficult while the app relies on hundreds of inline styles and inline event handlers. The current `_headers` file is likely inactive on GitHub Pages. Consider a free static host that supports real response headers once inline handlers are reduced.
- Ignored client spreadsheets/CSVs and `local-sql/` remain an accidental-commit risk. Add a CI check that fails if sensitive extensions or `local-sql/` ever become tracked.
- Many writes ignore Supabase errors, creating false success messages and partial multi-step operations. Add common mutation/error handling and eventually move multi-row audit creation/rollover into transactional database functions after security review.
- The dormant `security_audit_log` should capture sensitive actions (role/active changes, audit deletion/archive, time-log deletion/correction, settings changes, GreatSoft live pushes). Implementing trusted trigger-based writes needs explicit review because it requires a tightly scoped SECURITY DEFINER trigger function or equivalent trusted backend path.

### Step 5 — Implemented changes

No reviewed deletion candidate was removed.

Frontend/UI (`index.html`):

- Reworked the app shell into a calmer desktop sidebar and compact mobile drawer with grouped navigation: Work, Engagements, Insights, and Administration.
- Replaced shell/navigation emoji labels and terse names with task-based labels such as Overview, My work, New engagement, Manage engagements, and Client groups.
- Added a consistent system-font visual foundation, neutral canvas/surfaces, restrained navy/orange use, flatter cards/metrics, visible focus rings, and reduced-motion support.
- Added a clear `Engagement overview` page heading and a task-focused `My work` heading.
- Retired pilot reconciliation decision implemented: no Timesheets navigation item, route guarded by `TS_RECONCILIATION_ENABLED=false`, and the dormant code remains in place pending explicit whole-feature deletion approval.
- Renamed the active workflow action and modal to `Export for GreatSoft` / `Create Excel export` to reflect tracker logging → Excel → manual GreatSoft entry.
- Converted the hamburger and forgot-password control to real buttons; added navigation expanded state, dialog semantics, labelled close buttons, focus return, Escape-to-close, and global focus-visible styling.
- Added staff Dashboard routing to new fee-free work-summary views, with a temporary fallback to the legacy views until the migration is applied. Staff now see Actual Hours instead of Total Fee Value in the fourth metric.
- Added consistent `esc()`, `jsa()`, `safeCell()`, and `csvCell()` helpers. Patched high-risk raw HTML/event-argument paths in Dashboard, CSV preview, Edit, My Work, calendar, timesheets, users, settings, reports, print title, co-assignees, TB options, and exports.
- Added spreadsheet formula-injection protection for CSV report/timesheet exports and text cells in the XLSX time export.
- Raised the change-password UI minimum from 6 to 8 characters; the Supabase Auth project setting must also be raised in the Dashboard for server-side enforcement.
- Added error feedback to several high-use mutations (work-list hide, user updates, and subsection comments) that previously showed success after failed writes.

Database migration (`20260716000000_security_and_work_summary_views.sql`):

- Adds `subsection_work_summary`, `section_work_summary`, and `audit_work_summary` with no rate/fee columns for staff operational use.
- Restricts fee-bearing summary views and the timesheet report view to report viewers or trusted service/database roles.
- Restricts `settings` reads to report viewers.
- Hardens the two assignment helper functions so callers can test only their own email identity.
- Requires real caller identity on every `step_logs` insert; managers retain assignment bypass but cannot forge another user's identity.
- Updates the subsection column guard so staff can change step/comment/work-list visibility but cannot edit manager-authored notes.
- Adds NOT VALID allow-list constraints for subsection/log steps and timesheet statuses, protecting new/updated rows without failing on unknown legacy data.
- Explicitly revokes anonymous access to summary views.
- This migration has not been applied. Apply all earlier pending migrations first and test the role matrix in staging or a controlled production window.

Edge function:

- `_shared/greatsoftClient.ts` now actually stores OAuth tokens in the existing in-memory cache using the provider expiry (or a short fallback TTL). The concurrency-safe live-push claim remains a required future fix before enabling live GreatSoft pushes.

### Step 6 — Verification and handoff

Completed checks:

- Extracted the inline application script and parsed it with `node --check`: passed.
- Checked static markup opening/closing balance for `div`, `button`, `main`, and `nav`: passed.
- Ran `git diff --check`: passed (only the existing Windows LF→CRLF warning was reported).
- Confirmed the navigation contains no Timesheets entry, `TS_RECONCILIATION_ENABLED` is false, and the GreatSoft export wording is present.
- Confirmed staff Dashboard wiring references the three work-summary views and the migration contains the identity/column-guard changes.
- Checked the SQL migration's dollar-quoted blocks and conflict markers structurally: 8 balanced dollar-quote markers (three functions plus one DO block), no conflict markers.
- No local Deno, PostgreSQL, or Supabase CLI is installed. Edge-function type-checking, SQL execution, and live policy verification could not be performed locally.

Required rollout order and manual checks:

1. Confirm the live migration list in Supabase. Apply any missing migrations before `20260716000000_security_and_work_summary_views.sql` in filename order.
2. Deploy the frontend first if a no-downtime sequence is needed; it temporarily falls back to legacy summary views when the new work views do not exist. Then apply the security migration promptly.
3. Set Supabase Auth's minimum password length to at least 8 (prefer 12) so the server matches the updated UI.
4. Test as staff: Overview loads assigned audits only, fourth metric is Actual Hours, no fee/rate values are returned, My Work hide/comment/log/export work, and Timesheets is absent.
5. Test as manager/director: fee reports still load, settings access is correct, user changes report errors, and report/print output safely displays punctuation and special characters.
6. Verify direct Data API behavior: staff cannot query fee-bearing report views/settings, cannot forge `step_logs` identity, cannot edit subsection notes/budget/due/assignee, and cannot call assignment helpers for another email.
7. Run legacy diagnostics before validating the three NOT VALID constraints; then validate them in a follow-up migration.
8. Keep `GREATSOFT_PUSH_ENABLED` false until an atomic push-claim mechanism is implemented and dry-run output is approved.

Deletion decision queue:

- Approved product direction, deletion not yet performed: remove the retired weekly reconciliation feature as one unit (`tsModal`, `openTs`/`onTsChange`/`calcVar`/`submitTs`/`vTs`/table/export helpers, route branch, and `timesheet_variance_summary` only after confirming no historical report need).
- Safe tiny cleanup after approval: remove unused `REAL_R`.
- Archive/clarify before deleting: superseded staging RLS SQL, inactive `_headers`, unreferenced tax-code screenshot, duplicated/stale context documents.
- Keep: GreatSoft edge functions/mapping scaffold, notification scaffold, and audit-log table while those roadmap items remain active.
