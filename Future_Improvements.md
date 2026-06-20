# Future Improvements

## Status Key
- ✅ Done — fully implemented and working
- 🟡 Partial — scaffolded or partially working; detail noted
- ❌ Not built — not yet started

## Planned Enhancements

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 1 | **Audit Log** | 🟡 Partial | `security_audit_log` table exists in DB migration but nothing in the frontend writes to it yet |
| 2 | **Audit Templates** | 🟡 Partial | Default section templates work on new-audit creation (`STPLS` array). Rollover to Next Year is ✅ built. No saved custom templates yet. |
| 3 | **Subsection Comments** | ❌ Not built | No comment field or UI at subsection level |
| 4 | **Archive Completed Audits** | ✅ Done | Archive button in Edit view; `archived=true` flag; archived audits hidden from all active views |
| 5 | **Client Facing Report** | ❌ Not built | Internal CSV export exists but no branded client-facing report |
| 6 | **Utilisation Report** | 🟡 Partial | Workload view (`vWorkload`) shows staff loading across audits; no dedicated utilisation % / target report |
| 7 | **Undo Delete** | ❌ Not built | |
| 8 | **Manager Summary Email** | ❌ Not built | |
| 9 | **Dark Mode** | ❌ Not built | |
| 10 | **Proper RLS Security** | ✅ Done | All tables have RLS live in production as of 2026-06-20. Migration: `20260620000002_rls_main_tables.sql`. Tested against all roles. |
| 11 | **Refined Status/Step Options** | 🟡 Partial | 7 steps in use: Not Started / Client Requested / Client Received / Processing / Finalising / Review / Signed Off. Detail spec below is still blank. |
| 12 | **Accounting Project Type** | 🟡 Partial | Accounting type selector, icons, and department-based filtering exist. Detail spec below is still blank. |

---

## Detail: Refined Status/Step Options

> *(To be completed — add refined status and step option details here.)*

---

## Detail: Accounting Project Type

> *(To be completed — add accounting project type details here.)*

---

## Tax TB Feature (new — not in original list)

| Sub-feature | Status | Notes |
|-------------|--------|-------|
| CaseWare TB Excel upload + parse | ✅ Done | SheetJS; `parseCWTB()` extracts map number, description, consolidated amount |
| Year-end date cross-check vs TB file | ✅ Done | Scans first 25 rows for Date objects / text date patterns; warns on mismatch |
| GS tax code mapping UI | ✅ Done | Per-line code selector; `gs_tb_mapping` global dictionary auto-applies |
| DB tables (gs_tax_codes, gs_tb_mapping, tax_tb_imports, tax_tb_lines) | 🟡 Partial | Migration written (`20260620000001_tax_tb_tables.sql`) but **NOT YET APPLIED** to Supabase production |
| GS TB push edge function | ❌ Not built | Blocked on `TBImportDTO` structure from GreatSoft |
| Full ITR14 GS tax code seed data | 🟡 Partial | Micro Business codes seeded; full ITR14 list pending screenshot from GS |
