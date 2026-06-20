-- Tax Trial Balance import tables
-- Workflow: upload CaseWare TB Excel → parse CW map lines → map to GS tax codes → push via TBImportDTO
--
-- KEY DESIGN: gs_tb_mapping is GLOBAL (not per-client).
-- CaseWare map numbers are IFRS taxonomy codes standardised across all clients using the same template.
-- Map "1.1.1.100.100.100.200.100.00000.000 → 4609" once, every future client inherits it automatically.

-- ─── 1. GS tax code reference ──────────────────────────────────────────────
-- Master list of GreatSoft TB import tax codes (e.g. 4609, 4613.1).
-- Seeded initially from the Micro Business screenshot; full ITR14 codes added when available.
-- gs_code matches the "To" column visible in the GS TB import UI.
create table if not exists public.gs_tax_codes (
  id           uuid primary key default gen_random_uuid(),
  gs_code      text not null unique,   -- e.g. "4609", "4613.1"
  name         text not null,          -- e.g. "Property, plant and equipment"
  section      text,                   -- e.g. "Balance Sheet > Assets"
  return_type  text not null default 'ITR14',  -- ITR14 | MicroBusiness | Both
  sort_order   int  not null default 0,
  created_at   timestamptz not null default now()
);
comment on column public.gs_tax_codes.gs_code is 'Matches the "To" code shown in the GreatSoft TB import UI. Confirm full ITR14 list with GreatSoft.';

-- ─── 2. CW map number → GS tax code (global, reusable) ────────────────────
-- One row per CaseWare map number. Applies to ALL clients — set up once, reused forever.
-- cw_map_number: the dot-separated taxonomy code, e.g. "1.1.1.100.100.100.200.100.00000.000"
-- cw_description: the label CaseWare shows next to the map number (stored for display only)
create table if not exists public.gs_tb_mapping (
  id              uuid primary key default gen_random_uuid(),
  cw_map_number   text not null unique,
  cw_description  text,
  gs_tax_code_id  uuid references public.gs_tax_codes(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
comment on table public.gs_tb_mapping is 'Global CW map number → GS tax code dictionary. Set up once, auto-applied to all future TB imports.';

-- ─── 3. TB import header (one per client per year) ─────────────────────────
create table if not exists public.tax_tb_imports (
  id              uuid primary key default gen_random_uuid(),
  audit_id        uuid references public.audits(id) on delete cascade not null,
  tax_year_end    date not null,
  return_type     text not null default 'ITR14',
  status          text not null default 'draft',  -- draft | mapped | pushed
  lines_total     int  not null default 0,
  lines_mapped    int  not null default 0,
  pushed_at       timestamptz,
  created_by      uuid references public.users(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique(audit_id, tax_year_end)
);

-- ─── 4. TB import lines (parsed CW map lines for one import) ───────────────
-- Each row is one CW map line from the uploaded Excel.
-- gs_tax_code_id here is the EFFECTIVE code for this specific import line.
-- It defaults from gs_tb_mapping but can be overridden per line if needed.
create table if not exists public.tax_tb_lines (
  id               uuid primary key default gen_random_uuid(),
  import_id        uuid references public.tax_tb_imports(id) on delete cascade not null,
  cw_map_number    text not null,
  cw_description   text,
  cons_amount      numeric(15,2) not null default 0,
  gs_tax_code_id   uuid references public.gs_tax_codes(id) on delete set null,
  created_at       timestamptz not null default now(),
  unique(import_id, cw_map_number)
);

-- ─── RLS ───────────────────────────────────────────────────────────────────
alter table public.gs_tax_codes    enable row level security;
alter table public.gs_tb_mapping   enable row level security;
alter table public.tax_tb_imports  enable row level security;
alter table public.tax_tb_lines    enable row level security;

-- Managers manage everything; all authenticated users can read reference tables
create policy "gs_tax_codes_mgr"   on public.gs_tax_codes    for all    using (public.is_manager());
create policy "gs_tax_codes_read"  on public.gs_tax_codes    for select using (auth.uid() is not null);
create policy "gs_tb_map_mgr"      on public.gs_tb_mapping   for all    using (public.is_manager());
create policy "gs_tb_map_read"     on public.gs_tb_mapping   for select using (auth.uid() is not null);
create policy "tb_imports_mgr"     on public.tax_tb_imports  for all    using (public.is_manager());
create policy "tb_imports_dir"     on public.tax_tb_imports  for select using (public.is_director());
create policy "tb_lines_mgr"       on public.tax_tb_lines    for all    using (public.is_manager());
create policy "tb_lines_dir"       on public.tax_tb_lines    for select using (public.is_director());

-- ─── SEED: GS tax codes visible in the Micro Business screenshot ───────────
-- Full ITR14 codes to be added once that screenshot / GreatSoft docs are available.
insert into public.gs_tax_codes (gs_code, name, section, return_type, sort_order) values
('4609',   'Property, plant and equipment (cost)',                         'Balance Sheet > Assets > Non-current', 'Both', 10),
('4611',   'Property, plant and equipment (accumulated depreciation)',      'Balance Sheet > Assets > Non-current', 'Both', 11),
('4632',   'Property, plant and equipment (net)',                          'Balance Sheet > Assets > Non-current', 'Both', 12),
('4613',   'Long term loans',                                              'Balance Sheet > Assets > Non-current', 'Both', 20),
('4613.1', 'Long term loans 1',                                            'Balance Sheet > Assets > Non-current', 'Both', 21),
('4613.2', 'Long term loans 2',                                            'Balance Sheet > Assets > Non-current', 'Both', 22),
('4613.3', 'Long term loans 3',                                            'Balance Sheet > Assets > Non-current', 'Both', 23),
('4614',   'Long term loans (other)',                                      'Balance Sheet > Assets > Non-current', 'Both', 24),
('4614.1', 'Long term loans (other) 1',                                    'Balance Sheet > Assets > Non-current', 'Both', 25),
('4614.2', 'Long term loans (other) 2',                                    'Balance Sheet > Assets > Non-current', 'Both', 26),
('4614.3', 'Long term loans (other) 3',                                    'Balance Sheet > Assets > Non-current', 'Both', 27),
('4636',   'Long term loans (other sub)',                                   'Balance Sheet > Assets > Non-current', 'Both', 28)
on conflict (gs_code) do nothing;

-- NOTE: Full ITR14 code list needed. Request from GreatSoft or export from the TB import UI
-- for a full ITR14 client (not Micro Business). Add codes here when available.
