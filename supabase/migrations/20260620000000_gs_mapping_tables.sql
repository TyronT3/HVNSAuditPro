-- GreatSoft mapping tables + activity code seed data
-- Generated with reference to:
--   ActivityList.xlsx  — all GS activity/overhead codes
--   StdTasksList.xlsx  — GS standard task (service-type) codes
--   TSPeriodList.xlsx  — financial year period structure
--   TSEntries.xlsx     — real timesheet entry format
--
-- HOW THE GS STRUCTURE MAPS TO OUR APP:
--   Our audit      → GS Client (by client code) + GS Task (e.g. AUD, COM, TAX)
--   Our section    → GS Task override (if an audit spans multiple service types)
--   Our subsection → GS Activity/Overhead code (e.g. AAE15, ACC01)
--   Our step_log   → TimeTranDTO (TranDate = Friday of the week, WIPHrQty = hours)
--
-- GS PERIOD LOGIC:
--   Periods are weekly, Mon–Sun, grouped by month. Period code format: YYYYMMWW
--   (year 4 digits, month 2 digits, week-within-month 2 digits, e.g. 20260502 = May 2026 Week 2)
--   For each push, TranDate drives the period assignment automatically — we just pass the date.
--   For weekly timesheet pushes we use the Friday date as TranDate.

-- ─── 1. Employee map ───────────────────────────────────────────────────────
create table if not exists public.gs_employee_map (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null unique references public.users(id) on delete cascade,
  gs_emp_id     uuid,              -- GreatSoft EmpID (uuid) — filled from GET /api/Employees
  gs_emp_code   text,              -- e.g. "TTrut" — human-readable, shown in reports
  gs_emp_login  text,              -- Windows login (for EmployeeWinLogon auto-match)
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
comment on column public.gs_employee_map.gs_emp_id is 'Populated by calling GET /api/Employees and matching on name or login. Required before time entries can be pushed.';

-- ─── 2. Audit → GreatSoft client + task map ───────────────────────────────
-- A GS "Task" is a specific client engagement of a given service type.
-- e.g. client GRA002 has task AUD (Auditing) with a unique TaskID uuid.
-- Both gs_client_code and gs_task_code are needed to look up the TaskID via the API.
-- Source: GET /api/V2/TsLookup/ClientList → GET /api/V2/TsLookup/TaskList?clientCode=&taskID=
create table if not exists public.gs_audit_map (
  id              uuid primary key default gen_random_uuid(),
  audit_id        uuid not null unique references public.audits(id) on delete cascade,
  gs_client_id    uuid,            -- GreatSoft ClientID (uuid) — from ClientList
  gs_client_code  text,            -- e.g. "GRA002" — used as query param in TaskList
  gs_task_id      uuid,            -- GreatSoft TaskID (uuid) — primary FK for TimeTranDTO
  gs_task_code    text,            -- e.g. "AUD", "COM", "TAX" — from StdTasksList
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
comment on column public.gs_audit_map.gs_task_code is 'Standard task codes: AUD=Auditing, COM=Compilation, ACC=Accounting, MON=Monthly Retainer, TAX=Taxation, CON=Consulting, IR=Independent Review, SEC=Secretarial';

-- ─── 3. Section → GreatSoft task override ─────────────────────────────────
-- Use ONLY when a section within an audit bills to a different GS task than the parent audit.
-- Example: an audit engagement that also has a TAX section billed to a separate tax task.
-- Falls back to gs_audit_map for the parent audit if no row exists here.
create table if not exists public.gs_section_map (
  id             uuid primary key default gen_random_uuid(),
  section_id     uuid not null unique references public.sections(id) on delete cascade,
  gs_task_id     uuid not null,    -- GreatSoft TaskID override for this section
  gs_task_code   text,             -- e.g. "TAX"
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- ─── 4. Activity / overhead reference ─────────────────────────────────────
-- Master list of all known GreatSoft activity and overhead codes.
-- Pre-seeded with codes from ActivityList.xlsx.
-- gs_act_ovh_id (the uuid used in TimeTranDTO) is populated by calling:
--   GET /api/V2/TsLookup/ActivityList?taskID=   (chargeable)
--   GET /api/V2/TsLookup/OverheadList            (non-chargeable overhead)
-- Re-sync periodically — GS can add/change codes.
create table if not exists public.gs_activity_codes (
  id              uuid primary key default gen_random_uuid(),
  code            text not null unique,    -- GS activity code, e.g. "AAE15" — human key used for setup
  name            text not null,           -- display name, e.g. "Bank & Cash"
  activity_type   text,                    -- Audit | Accounting | Admin | Compilation | Consulting | CoSec | Taxation | Overhead
  is_overhead     boolean not null default false,
  gs_act_ovh_id   uuid unique,             -- GreatSoft ActOvhID (uuid) — nullable until API sync
  created_at      timestamptz not null default now()
);
comment on column public.gs_activity_codes.gs_act_ovh_id is 'Populated by calling ActivityList or OverheadList API and matching on code. Required at push time.';

-- ─── 5. Subsection → activity map ─────────────────────────────────────────
-- Maps each subsection to the GS activity code used when posting time for it.
-- Multiple subsections can share the same activity code (many-to-one is expected and normal).
create table if not exists public.gs_subsection_activity_map (
  id                    uuid primary key default gen_random_uuid(),
  subsection_id         uuid not null unique references public.subsections(id) on delete cascade,
  gs_activity_code_id   uuid not null references public.gs_activity_codes(id),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

-- ─── RLS ───────────────────────────────────────────────────────────────────
alter table public.gs_employee_map            enable row level security;
alter table public.gs_audit_map               enable row level security;
alter table public.gs_section_map             enable row level security;
alter table public.gs_activity_codes          enable row level security;
alter table public.gs_subsection_activity_map enable row level security;

create policy "gs_emp_map_manager_all"       on public.gs_employee_map            for all     using (public.is_manager());
create policy "gs_audit_map_manager_all"     on public.gs_audit_map               for all     using (public.is_manager());
create policy "gs_sec_map_manager_all"       on public.gs_section_map             for all     using (public.is_manager());
create policy "gs_act_codes_manager_all"     on public.gs_activity_codes          for all     using (public.is_manager());
create policy "gs_sub_act_map_manager_all"   on public.gs_subsection_activity_map for all     using (public.is_manager());

-- All authenticated users can read mapping tables (needed for push lookups)
create policy "gs_emp_map_auth_read"         on public.gs_employee_map            for select  using (auth.uid() is not null);
create policy "gs_audit_map_auth_read"       on public.gs_audit_map               for select  using (auth.uid() is not null);
create policy "gs_sec_map_auth_read"         on public.gs_section_map             for select  using (auth.uid() is not null);
create policy "gs_act_codes_auth_read"       on public.gs_activity_codes          for select  using (auth.uid() is not null);
create policy "gs_sub_act_map_auth_read"     on public.gs_subsection_activity_map for select  using (auth.uid() is not null);


-- ─── SEED: Activity codes from ActivityList.xlsx ───────────────────────────
-- gs_act_ovh_id is intentionally null here — populate by syncing from the GS API.
-- Overhead codes (TR001, PM001, IT001, etc.) seen in real timesheets but absent from
-- ActivityList are internal overhead codes — populate from GET /api/V2/TsLookup/OverheadList.

insert into public.gs_activity_codes (code, name, activity_type, is_overhead) values

-- Audit activities (task code: AUD)
('AAE1',  'Pre-engagement activities',                                                         'Audit', false),
('AAE2',  'Understanding of entity and its environment, including internal control',            'Audit', false),
('AAE3',  'Evaluates the risk of material misstatement',                                       'Audit', false),
('AAE4',  'Calculates and justifies planning materiality',                                     'Audit', false),
('AAE5',  'Designs or selects effective and efficient procedures',                             'Audit', false),
('AAE6',  'Executes the audit plan and documents and evaluates results',                       'Audit', false),
('AAE7',  'Completes the engagement',                                                          'Audit', false),
('AAE8',  'Prepares information for meetings with stakeholders',                               'Audit', false),
('AAE9',  'Evaluates potential reportable irregularities',                                     'Audit', false),
('AAE10', 'Property, plant and equipment / Investment prop.',                                  'Audit', false),
('AAE11', 'Investments/Goodwill',                                                              'Audit', false),
('AAE12', 'Inventory',                                                                         'Audit', false),
('AAE13', 'Accounts Receivable',                                                               'Audit', false),
('AAE14', 'Sundry Debtors & Other',                                                            'Audit', false),
('AAE15', 'Bank & Cash',                                                                       'Audit', false),
('AAE16', 'Other Financial Assets',                                                            'Audit', false),
('AAE17', 'Share Capital & Reserves',                                                          'Audit', false),
('AAE18', 'Long Term Liabilities - Shareholders',                                              'Audit', false),
('AAE19', 'Long Term Liabilities - Third Party',                                               'Audit', false),
('AAE20', 'Long Term Liabilities - Leases',                                                    'Audit', false),
('AAE21', 'Accounts Payable',                                                                  'Audit', false),
('AAE22', 'Accruals',                                                                          'Audit', false),
('AAE23', 'Provisions',                                                                        'Audit', false),
('AAE24', 'VAT Reconciliations',                                                               'Audit', false),
('AAE25', 'Other Financial Liabilities',                                                       'Audit', false),
('AAE26', 'Taxation',                                                                          'Audit', false),
('AAE27', 'Opening Balances',                                                                  'Audit', false),
('AAE28', 'Revenue',                                                                           'Audit', false),
('AAE29', 'Cost of Sales',                                                                     'Audit', false),
('AAE30', 'Employee Costs',                                                                    'Audit', false),
('AAE31', 'Expenditure',                                                                       'Audit', false),
('AAE32', 'Income Tax Returns - Completed',                                                    'Audit', false),
('AAE33', 'Interest paid',                                                                     'Audit', false),
('AAE34', 'Interest Received',                                                                 'Audit', false),
('AAE35', 'Other Income',                                                                      'Audit', false),
('AAE36', 'Right of Use Assets',                                                               'Audit', false),
('AAE37', 'Analytical Review',                                                                 'Audit', false),
('AAE38', 'Reviewing of Working Papers Performed',                                             'Audit', false),

-- Accounting activities (task code: ACC / MON / COM)
('ACC01', 'Bookkeeping',                                                                       'Accounting', false),
('ACC02', 'Payroll',                                                                           'Accounting', false),
('ACC03', 'EMP501 reconciliations',                                                            'Accounting', false),
('ACC04', 'Forecasts/Budgets & Reporting',                                                     'Accounting', false),
('ACC06', 'VAT201 - Submission and review',                                                    'Accounting', false),
('ACC07', 'EMP201 - Submission and review',                                                    'Accounting', false),
('ACC08', 'UIF Department of Labour registration/Deregistration',                             'Accounting', false),
('ACC09', 'Compensation Commissioner - Return of Earnings',                                   'Accounting', false),
('ACC10', 'Compensation Commissioner - Registrations',                                        'Accounting', false),
('ACC11', 'Compensation Commissioner - Deregistration',                                       'Accounting', false),
('ACC12', 'Compensation Commissioner - Queries',                                              'Accounting', false),
('ACC13', 'Employment Equity activities (WSP/ATR)',                                            'Accounting', false),
('ACC14', 'Covid-19 assistance with Submission UIF claims',                                   'Accounting', false),

-- Compilation activities (task code: COM)
('AEC1',  'Evaluates appropriate accounting frameworks and policies',                          'Compilation', false),
('AEC2',  'Evaluates or accounts for entity transactions, including non-routine',              'Compilation', false),
('AEC3',  'Drafting of Annual Financial Statements',                                           'Compilation', false),
('AEC5',  'Income Tax Returns - Submitted',                                                    'Taxation',   false),

-- Admin activities (task code: ADM)
('ADM05',   'Client Training',                                                                 'Admin', false),
('Admin01',  'Personal time',                                                                  'Admin', true),
('Admin02',  'Office Administration',                                                          'Admin', true),
('Admin03',  'Training - External',                                                            'Admin', true),
('Admin04',  'Training - Internal',                                                            'Admin', true),
('Admin05',  'IT Admin',                                                                       'Admin', true),
('Admin06',  'Client onboarding',                                                              'Admin', false),
('ADMIN07',  'Tax Administration',                                                             'Admin', false),

-- Consulting activities (task code: CON)
('CON01', 'Valuation of entities',                                                             'Consulting', false),
('CON02', 'Consultations',                                                                     'Consulting', false),
('CON03', 'BBBEE Activities',                                                                  'Consulting', false),
('FMR1',  'Due Diligence',                                                                     'Consulting', false),
('FMR2',  'Cash Flow Forecasting and Analysis',                                                'Consulting', false),
('FMR3',  'Evaluates the entitys working capital',                                             'Consulting', false),
('FMR4',  'Evaluates capital investment decisions',                                            'Consulting', false),
('MDR1',  'KPI Analysis',                                                                      'Consulting', false),
('RMR1',  'Risk Management',                                                                   'Consulting', false),
('RMR2',  'Key Internal controls',                                                             'Consulting', false),
('RMR3',  'Evaluates internal control',                                                        'Consulting', false),
('RMR4',  'Conducts governance reviews in accordance with governance standards',               'Consulting', false),

-- Company Secretarial activities (task code: SEC / SECAR)
('SEC01',   'Adopt new Memorandum of Incorporation',                                           'CoSec', false),
('SEC02',   'AGM Minutes or Written Resolution of AGM',                                        'CoSec', false),
('SEC03',   'Allotment / Issue of Shares',                                                     'CoSec', false),
('SEC04',   'Amend Memorandum of Incorporation',                                               'CoSec', false),
('SEC05',   'Annual Return Administration',                                                    'CoSec', false),
('SEC06',   'Annual Return Submissions including AFS in XBRL format',                          'CoSec', false),
('SEC07',   'Annual Return Submissions including Financial Accountability Supplement',          'CoSec', false),
('SEC08',   'Appoint HVNS as Auditors or Accounting Officer',                                  'CoSec', false),
('SEC09',   'Buyback/Acquisition of Shares',                                                   'CoSec', false),
('SEC10',   'Change Accounting Officer - CC',                                                  'CoSec', false),
('SEC11',   'Change address of Location of Statutory Documents',                               'CoSec', false),
('SEC12',   'Change Financial Year End',                                                       'CoSec', false),
('SEC13',   'Change of Registered Office',                                                     'CoSec', false),
('SEC14',   'Changes to Public Officer',                                                       'CoSec', false),
('SEC15',   'Company Secretary Changes',                                                       'CoSec', false),
('SEC16',   'Company/CC Name Change',                                                          'CoSec', false),
('SEC17',   'Confirmation of Directors and/or Shareholders',                                   'CoSec', false),
('SEC18',   'Convert CC to a Company',                                                         'CoSec', false),
('SEC19',   'Convert PV Shares to NPV shares',                                                 'CoSec', false),
('SEC20',   'Deregister Company or CC',                                                        'CoSec', false),
('SEC21',   'Deregister Trust',                                                                'CoSec', false),
('SEC22',   'Restoration of a deregistered entity',                                            'CoSec', false),
('SEC23',   'Directors Amendments',                                                            'CoSec', false),
('SEC24',   'Directors Declaration of Interest in Contracts',                                  'CoSec', false),
('SEC25',   'Financial Assistance/Intercompany Loans',                                         'CoSec', false),
('SEC26',   'New Company Registration',                                                        'CoSec', false),
('SEC27',   'New Trust Registration',                                                          'CoSec', false),
('SEC28',   'Increase of Authorised Share Capital',                                            'CoSec', false),
('SEC29',   'Transfer of Members Interest in a CC',                                            'CoSec', false),
('SEC30',   'Transfer of Shares and payment of eSTT (transfer duty)',                          'CoSec', false),
('SEC31',   'Trustee Amendments',                                                              'CoSec', false),
('SEC32',   'Attendance of Client Meeting',                                                    'CoSec', false),
('SEC33',   'Non resident endorsement of share certificate',                                   'CoSec', false),
('SEC34',   'Notice of meeting — Preparation and sending',                                     'CoSec', false),
('SEC35',   'Request CIPC Disclosure Certificates',                                            'CoSec', false),
('SEC36',   'Request copies of statutory documents from CIPC',                                 'CoSec', false),
('SEC37',   'Resign HVNS as Auditors or Accounting Officer',                                   'CoSec', false),
('SEC38',   'Minutes, Drafting of general minutes',                                            'CoSec', false),
('SECSUB',  'Submission of Annual Returns',                                                    'CoSec', false),

-- Taxation activities (task code: TAX)
('TAX01', 'Income tax registration/Deregistration',                                            'Taxation', false),
('TAX02', 'VAT Registration/Deregistration',                                                   'Taxation', false),
('TAX03', 'Payroll taxes registration/Deregistration',                                         'Taxation', false),
('TAX04', 'Customs/Import & Export Registration/Deregistration',                               'Taxation', false),
('TAX5',  'Income tax - Compute, complete, submit & review',                                   'Taxation', false),
('TAX06', 'Income tax - Complete, submit & review of ITR12R',                                  'Taxation', false),
('TAX07', 'Income tax - Complete, submit & review of ITR14',                                   'Taxation', false),
('TAX08', 'Income tax - Verification of income tax return',                                    'Taxation', false),
('TAX9',  'Income tax - Complete, submit & review of ITR14SD',                                 'Taxation', false),
('TAX10', 'Provisional tax - Compute, complete, submit & review IRP6 (1st)',                   'Taxation', false),
('TAX11', 'Provisional tax - Compute, complete, submit & review IRP6 (2nd)',                   'Taxation', false),
('TAX12', 'Provisional tax - Compute, complete, submit & review IRP6 (3rd)',                   'Taxation', false),
('TAX13', 'Objections and appeals',                                                            'Taxation', false),
('TAX14', 'SARS Account maintenance',                                                          'Taxation', false),
('TAX15', 'DWT - Dividend Withholding Tax submission',                                         'Taxation', false),
('TAX16', 'Directives - Application and administration',                                       'Taxation', false),
('TAX17', 'Tax clearance - Obtain tax clearance certificate',                                  'Taxation', false),
('TAX18', 'VAT103 - Obtaining VAT 103 Certificate',                                            'Taxation', false),
('TAX19', 'PAYE103 - Obtaining PAYE 103 Certificate',                                         'Taxation', false),
('TAX20', 'IT103 - Obtaining IT 103 Certificate',                                              'Taxation', false),
('TAX21', 'Banking details - Update SARS banking details',                                     'Taxation', false),
('TAX22', 'STT - Payment of SARS eSTT',                                                       'Taxation', false),
('TAX23', 'SARS Deferred payment arrangements',                                                'Taxation', false),
('TAX24', 'Provisional tax - Compute (1st)',                                                   'Taxation', false),
('TAX25', 'Provisional tax - Compute (2nd)',                                                   'Taxation', false),
('TAX26', 'Provisional tax - Compute (3rd)',                                                   'Taxation', false),
('TAX27', 'Upload of information',                                                             'Taxation', false),
('TAX28', 'Customs Administration',                                                            'Taxation', false),
('TAX29', 'Other',                                                                             'Taxation', false),
('TXR4',  'Income Tax Returns - Completed',                                                    'Taxation', false),
('ESTFEE','Estimated',                                                                         'Taxation', false),
('REF001','Refund',                                                                            'Taxation', false),

-- Travel (used across service types)
('TRA01', 'Travel time',                                                                       'Compilation', false)

on conflict (code) do nothing;

-- NOTE — overhead codes seen in real timesheets but NOT in ActivityList.xlsx:
--   TR001  (Training)
--   PM001  (Partner Meeting)
--   TE001  (Training Office)
--   IT001  (IT)
--   ADM01  (Admin)
--   FR001  (unknown)
-- These are likely from GET /api/V2/TsLookup/OverheadList (non-chargeable overheads).
-- Add them manually after calling OverheadList, or via an admin sync function.
