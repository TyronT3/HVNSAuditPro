-- Recreate RLS policies for all Tax TB tables.
--
-- Root cause: when 20260620000001_tax_tb_tables.sql was applied via the
-- Supabase SQL Editor, individual CREATE POLICY statements may have failed
-- (e.g. if public.is_manager() was not yet available in that session).
-- The result is RLS enabled on the table but no policies — all non-superuser
-- inserts are blocked with a row-level security policy violation.
--
-- Safe to re-run: DROP IF EXISTS before every CREATE POLICY.

-- ── gs_tax_codes ─────────────────────────────────────────────────────────────
drop policy if exists "gs_tax_codes_mgr"  on public.gs_tax_codes;
drop policy if exists "gs_tax_codes_read" on public.gs_tax_codes;

alter table public.gs_tax_codes enable row level security;

create policy "gs_tax_codes_mgr"
  on public.gs_tax_codes for all
  using (public.is_manager())
  with check (public.is_manager());

create policy "gs_tax_codes_read"
  on public.gs_tax_codes for select
  using (auth.uid() is not null);

-- ── gs_tb_mapping ─────────────────────────────────────────────────────────────
drop policy if exists "gs_tb_map_mgr"  on public.gs_tb_mapping;
drop policy if exists "gs_tb_map_read" on public.gs_tb_mapping;

alter table public.gs_tb_mapping enable row level security;

create policy "gs_tb_map_mgr"
  on public.gs_tb_mapping for all
  using (public.is_manager())
  with check (public.is_manager());

create policy "gs_tb_map_read"
  on public.gs_tb_mapping for select
  using (auth.uid() is not null);

-- ── tax_tb_imports ────────────────────────────────────────────────────────────
drop policy if exists "tb_imports_mgr" on public.tax_tb_imports;
drop policy if exists "tb_imports_dir" on public.tax_tb_imports;

alter table public.tax_tb_imports enable row level security;

create policy "tb_imports_mgr"
  on public.tax_tb_imports for all
  using (public.is_manager())
  with check (public.is_manager());

create policy "tb_imports_dir"
  on public.tax_tb_imports for select
  using (public.is_director());

-- ── tax_tb_lines ──────────────────────────────────────────────────────────────
drop policy if exists "tb_lines_mgr" on public.tax_tb_lines;
drop policy if exists "tb_lines_dir" on public.tax_tb_lines;

alter table public.tax_tb_lines enable row level security;

create policy "tb_lines_mgr"
  on public.tax_tb_lines for all
  using (public.is_manager())
  with check (public.is_manager());

create policy "tb_lines_dir"
  on public.tax_tb_lines for select
  using (public.is_director());
