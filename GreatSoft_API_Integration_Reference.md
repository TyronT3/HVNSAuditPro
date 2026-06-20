# GreatSoft GSCloud REST API — Integration Reference

> Source: GreatSoft Public API (Swagger 2.0, "all endpoint versions"). 163 endpoints, 203 DTOs.
> Prepared as a build-ready summary for the audit/timesheet tool integration.

---

## 1. Connection basics

| Item | Value |
|---|---|
| Host | `crm.gscloud.co.za` |
| Base path | `/rest` (full Swagger basePath: `crm.gscloud.co.za/rest`) |
| Scheme | `https` only |
| Spec version | Swagger 2.0 |
| Content type | `application/json` (also accepts `text/json`) |
| Endpoint root | `https://crm.gscloud.co.za/rest/api/...` |

**Important:** the spec lists `crm.gscloud.co.za` as the shared cloud host. Your firm may sit on a tenant-specific host — confirm your actual base URL with GreatSoft before going live. Treat the host as a config value, not a hardcoded constant.

---

## 2. Authentication & authorisation

The API is **OAuth2 scope-based** (Bearer token). The token-issuing endpoint itself is **not** in this spec — it lives on a separate identity/OAuth server. You authenticate, receive a Bearer access token, and send it on every call:

```
Authorization: Bearer <access_token>
```

The token must carry the **scope(s)** required by each endpoint (see scope table below). Issued tokens can be inspected/revoked via the PartnerInfo endpoints, and you can test that a scope is correctly granted using the `/api/ScopeTest/*` endpoints — useful during integration setup.

**Action item:** ask GreatSoft for (a) the OAuth token endpoint URL, (b) your `client_id`/`client_secret` or integration partner credentials, and (c) which scopes your integration key is approved for. You almost certainly need at minimum `INT.Payroll` + `PM.Time` for timesheets.

### Scopes reference

| Scope | Meaning / area | Endpoints using it |
|---|---|---|
| `PM.Write` | Practice management — create/update | 100 |
| `PM.Read` | Practice management — read | 81 |
| `INT.Payroll` | Integration partner / payroll context (time & expense) | 36 |
| `PM.Expense` | Expense capture | 22 |
| `PM.Time` | Timesheet capture | 16 |
| `Cosec.Read` / `Cosec.Write` | Company secretarial / Beneficial ownership / Trusts | 8 / 3 |
| `Tax.Read` / `Tax.Write` | Tax info & TB import | 5 / 4 |
| `PM.Read.Secure` | Sensitive reads (e.g. client tax numbers) | 3 |
| `ID.Read` | Identity (users & roles) | 3 |
| `IP.Token` | Integration partner token management | 5 |
| `Developer` | Developer/test endpoints | 3 |
| *(open)* | No scope (ApiInfo version endpoints) | 3 |

---

## 3. Integration-critical endpoints (timesheet auto-push)

This is the subset you'll wire up for the use case: link our users → GreatSoft employees, map our sections/tasks → GreatSoft tasks/activities, then post time.

### 3.1 Link users (our `users` table ↔ GreatSoft employees)

| Method | Path | Scope | Notes |
|---|---|---|---|
| GET | `/api/Employees` | `PM.Read`, `INT.Payroll` | List all employees — pull `EmpID` (uuid) + `EmpCode` to store the GreatSoft ID against each of our users |
| GET | `/api/Employees/{id}` | `PM.Read`, `INT.Payroll` | Single employee by `EmpID` |
| GET | `/api/CRMLookup/EmployeeWinLogon` | `PM.Read/Write` | Maps employees to their Windows login — handy if you want to auto-match users by network login rather than manually |

**Key linking field:** store `EmpID` (the uuid) on each of our users. `EmpCode` is the human-readable code; `EmpLogin` / WinLogon can drive auto-matching.

### 3.2 Map tasks & activities (our sections ↔ GreatSoft task/activity codes)

Time is posted against a **TaskID** (the client engagement/job) and an **ActOvhID** (the activity/overhead being performed). Use the V2 timesheet lookups:

| Method | Path | Scope | Returns |
|---|---|---|---|
| GET | `/api/V2/TsLookup/ClientList?searchText=&maxRows=&tranDate=` | `INT.Payroll`,`PM.Time`,`PM.Expense` | Searchable client list for the picker |
| GET | `/api/V2/TsLookup/TaskList?clientCode=&taskID=&includeClosed=` | `INT.Payroll`,`PM.Time`,`PM.Expense` | Tasks (jobs) for a client → gives you `TaskID` |
| GET | `/api/V2/TsLookup/ActivityList?taskID=` | `INT.Payroll`,`PM.Time` | Valid activities for a task → gives you `ActOvhID` |
| GET | `/api/V2/TsLookup/OverheadList` | `INT.Payroll`,`PM.Time` | Non-chargeable overhead activities |
| GET | `/api/V2/TsLookup/RateList?taskID=&actID=&tranDate=` | `INT.Payroll`,`PM.Time` | Standard rates → gives you `StdRateID` |
| GET | `/api/V2/TsLookup/ClientLastEntrySum/{clientCode}` | `INT.Payroll`,`PM.Time`,`PM.Expense` | Recent entries for a client (good for defaults) |

**Mapping strategy:** store a mapping of `our_section → {TaskID, ActOvhID}`. The `TaskID` ties to a client engagement; the `ActOvhID` is the work type. Pull `StdRateID` from `RateList` for the same task/activity/date.

### 3.3 Post time (the actual push) — `TimeSheetV2`

| Method | Path | Scope | Notes |
|---|---|---|---|
| POST | `/api/V2/Timesheet/TimeTran` | `INT.Payroll`,`PM.Time` | Create a time entry (body = `TimeTranDTO`) |
| GET | `/api/V2/Timesheet/TimeTran/{id}` | `INT.Payroll`,`PM.Time` | Read entry by id |
| PUT | `/api/V2/Timesheet/TimeTran/{id}` | `INT.Payroll`,`PM.Time` | Update entry |
| DELETE | `/api/V2/Timesheet/TimeTran/{id}` | `INT.Payroll`,`PM.Time` | Delete entry |
| GET | `/api/V2/Timesheet/TimeTranByDate?dateFrom=&dateTo=&actOvhId=` | `INT.Payroll`,`PM.Time` | Reconcile what's already pushed for a period (avoid duplicates) |
| POST | `/api/V2/Timesheet/Submit?approverID=` | `INT.Payroll`,`PM.Time` | Submit a captured timesheet for approval (body = `TimeExpSubmitDTO`) |

**`TimeTranDTO` — the body you POST:**

| Field | Type | Meaning |
|---|---|---|
| `WIPTranDetID` | uuid | Transaction id — leave empty/omit on create, GreatSoft assigns it; required on update |
| `TranStatus` | string | Status flag of the entry |
| `TranDate` | date-time | Date the work was done |
| `TimeStartUTC` | date-time | Start timestamp (UTC) |
| `TaskID` | uuid | **The job/engagement** (from `TaskList`) |
| `ActOvhID` | uuid | **The activity/overhead** (from `ActivityList` / `OverheadList`) |
| `WIPHrQty` | double | **Hours** logged |
| `StdRateID` | uuid | Standard rate (from `RateList`) |
| `Narration` | string | Free-text description |
| `ErrorLog` | string | Populated by API with validation errors — read it back |

**Suggested flow per timesheet line:**
1. Resolve our user → `EmpID` (token context usually fixes the employee, but confirm).
2. Resolve our section → `TaskID` + `ActOvhID`.
3. Fetch `StdRateID` from `RateList` for that task/activity/date.
4. POST `TimeTranDTO` to `/api/V2/Timesheet/TimeTran`.
5. (Optional, period-end) POST `/api/V2/Timesheet/Submit` with `TimeExpSubmitDTO` to push the captured period into approval.

**`TimeExpSubmitDTO` (submit body):** `PeriodRef` (int), `SubmitState` (string), `Status` (string), `AcceptHrs` (bool).

### 3.4 Expenses (parallel pattern, if needed later) — `ExpensesV2`

Same shape as timesheets: `POST /api/V2/Expenses/ExpenseTran` (body `ExpenseTranDTO`), plus document upload (`/UploadDocument`), and `POST /api/V2/Expenses/Submit`. DTO adds `ExpID`, `AllocID`, `Qty`, `ExpValue`, `CurrCodeIDCapt`. Lookups live under `/api/V2/TsLookup/Expense*`.

---

## 4. Conventions & patterns (apply across all endpoints)

- **`approverId` query param** appears on most create/update calls — the employee id who approves the change. Many writes go into a *pending approval* queue; check `.../PendingChanges` endpoints (Clients, Tasks) to see what's awaiting sign-off.
- **OData query extensions** are supported on ~28 read endpoints (filtering, `$expand`, paging via `?$skip={int}&$top={int}`). Many list endpoints also expose plain `skip`/`top` query params. Max `$top` is capped (e.g. 500 on AccessTokens).
- **`updatedSince` / `processedSince` / `invoicedSince`** params on many reads — use these for incremental sync rather than full pulls.
- **PATCH** endpoints (Clients, Employees) take a JSON Patch document (`JsonPatchDocument[...]`) for partial updates.
- **Common response codes:** `200` OK, `201` Created, `400` Bad Request (validation), `401` Unauthorized (token/scope), `500` Internal Server Error (returns a `ResourceServerException` body). Always read response bodies on non-2xx.
- **IDs come in pairs:** most entities have a uuid id (`ClientID`, `EmpID`, `TaskID`) *and* a legacy int (`ClientID1`, `EmpID1`) plus a human code (`ClientCode`, `EmpCode`, `TaskCode`). Persist the uuid for API calls; show the code to users.

---

## 5. Full endpoint catalogue (by area)

> `[scope]` shown per group. `?` = scope not declared in the spec for that endpoint (confirm with GreatSoft).

### ApiInfo *(open, no auth)*
- GET `/api/Info/PortalVersion` — GSPortal schema version
- GET `/api/Info/ApiVersion` — API assembly version
- GET `/api/Info` — all version/info

### Identity `[ID.Read]`
- GET `/api/Users` — all users
- GET `/api/User?userName=` — single user
- GET `/api/Roles` — all roles
- GET `/api/Role?roleName=` — single role

### Employee `[PM.Read/Write, INT.Payroll]`
- GET `/api/Employees` · POST `/api/Employees` · GET/PUT/PATCH `/api/Employees/{id}`
- GET `/api/Employees/{id}/PersonalList/{exportType}`
- GET `/api/SecurityGroups` — employee security groups (roles)
- POST `/api/AssignEmployeeSecurity?empId=&securityGroup=`

### Clients `[PM.Read/Write; secure reads = PM.Read.Secure]`
- GET `/api/Clients` · POST `/api/Clients` · GET/PUT/PATCH `/api/Clients/{id}`
- GET `/api/Clients/{id}/PendingChanges`
- GET `/api/Clients/ClientDetails?clientCode=`
- GET `/api/Clients/TaxNumberByCode?clientCode=` · GET `/api/Clients/{id}/TaxNumber` · GET `/api/Clients/TaxNumbers` *(secure)*
- PUT `/api/Clients/{id}/ClientAddress`
- POST `/api/Clients/Note` (WebNoteDTO) · POST `/api/Clients/ClientService` · DELETE `/api/Clients/ClientService/client/{clientID}/status/{statusID}`
- GET `/api/Clients/UserDefinedServices` · GET `/api/Clients/ClientServicesAllocated` · GET `/api/Clients/ClientLinks/{clientCode}`

### Contacts `[PM.Read/Write]`
- GET `/api/Contacts` · POST `/api/Contacts` · GET/PUT `/api/Contacts/{id}`
- GET `/api/Contacts/ContactTypes` · PUT `/api/Contacts/{id}/ContactClients`

### Groups `[PM.Read/Write]`
- GET `/api/Groups` · POST `/api/Groups` · GET/PUT `/api/Groups/{id}` · PUT `/api/Groups/{id}/GroupAddress`

### Tasks `[PM.Read/Write]`
- GET `/api/Tasks` · POST `/api/Tasks` · GET/PUT `/api/Tasks/{id}`
- GET `/api/Tasks/{id}/PendingChanges` · POST `/api/Tasks/{id}/Provisions`

### TimeSheetV2 `[INT.Payroll, PM.Time]`
- POST/GET `/api/V2/Timesheet/TimeTran` · GET/PUT/DELETE `/api/V2/Timesheet/TimeTran/{id}`
- GET `/api/V2/Timesheet/TimeTranByDate` · POST `/api/V2/Timesheet/Submit`

### ExpensesV2 `[INT.Payroll, PM.Expense]`
- POST/GET/PUT/DELETE `/api/V2/Expenses/ExpenseTran[/{id}]`
- GET `/api/V2/Expenses/ExpenseTranByDate`
- POST `/api/V2/Expenses/UploadDocument` · GET `/api/V2/Expenses/GetDocument` · DELETE `/api/V2/Expenses/DeleteDocument`
- POST `/api/V2/Expenses/Submit`

### TsLookupV2 `[INT.Payroll, PM.Time/Expense]`
- ActivityList · ClientList · TaskList · OverheadList · RateList · ExpenseList · ExpenseRates · ExpenseAllocations · ExpenseCurrencies · ConvertCurr · DefaultKmExpense · TimeExpSummary · ClientLastEntrySum/{clientCode}

### CRMLookUps `[PM.Read/Write]` (32 reference lookups)
Client/Address/Group/Employee/Task/ServiceLine/Office general info; standard rates (Activity/Employee/EmpCat/Task/Std); Country, Currency, TypeCode, Bank, Tax Office, VAT-per-office; UDF lookups (Task/Client); Period lookups (`PeriodLookup/{yearStatus}`, `PeriodsByFinYear/{year}`, `CurrentPeriod`); NoteCategory; ClientServices.

### Debtors `[PM.Read/Write]`
- DrsAgeByOffice · DebtorsInfo · InvoiceInfo · ReceiptInfo · Movement/{periodRef} · Movement/Entries · Receipt/{recNumber}
- POST `/api/Debtors/Receipt` (single) · POST `/api/Debtors/Receipts` (batch)

### Invoices `[PM.Read/Write]`
- GET `/api/Invoices` · GET `/api/Invoices/{invNo}`
- Invoice UDFs: GET `/api/Invoices/{invNumber}/udf`, GET `/api/Invoices/udf/{udfId}`, POST/PUT udf
- GET `/api/InvoiceBatchLookup` · POST `/api/Fees/Batch` (BillBatchDTO)

### Wip `[PM.Read/Write]`
- EmployeeDisbursements/{periodRef} · EmployeeLeave/{periodRef} · WipByOfficeByServiceLine/{periodRef} · EmployeeWipDetails · ClientWipSummary

### DisbTranBatch `[scope: confirm]`
- GET/POST `/api/Wip/DisbTranBatch` · GET/PUT/DELETE `/api/Wip/DisbTranBatch/{batchKey}`
- Line items: GET/PUT/DELETE `/api/Wip/DisbTranBatch/{batchKey}/line/{tranID}` · POST `/api/Wip/DisbTranBatch/{batchKey}/line`

### SecureViews `[PM.Read/Write]`
- Office-secured lists of Clients / Employees / Tasks by `{contextEmpID}` and office code/id · OfficeDefaults/{contextEmpID}

### Tax & related
- TaxInfo `[Tax.Read]`: ITRInfo · TaxQueryInfo · ProvisionalInfo
- TaxTBImport `[Tax.Write]`: POST `/api/Tax/TBImport` (TBImportDTO)
- ClientVerifications `[PM.Read/Write]`: GET/POST `/api/ClientVerifications` · GET/PUT `/api/ClientVerifications/{id}`
- FICA: POST `/api/Fica`
- YearEnds `[PM.Read/Write]`: GET `/api/YearEnd/{clientCode}` · POST `/api/YearEnd` · PUT `/api/YearEnd/{id}/{clientCode}`

### Company Secretarial
- Secretarial `[Cosec.Read]`: Registers · Trust SARSRepresentative/Auditors/Trustees/Representatives by `{registerId}`
- BeneficialOwnership `[Cosec.Read]`: GET `/api/BeneficialOwnership?clientCode=&regNumber=` *(BETA)*

### SubServiceLines `[PM.Read/Write]`
- GET `/api/SubServiceLines`

### PartnerInfo `[IP.Token]`
- GET `/api/PartnerInfo/AccessTokens?scope=` — list issued tokens
- DELETE `/api/PartnerInfo/AccessTokens/{id}` — revoke a token

### Test / utility (use during setup, not in production)
- ScopeTest `[per-scope]`: GET/POST `/api/ScopeTest/*` — confirm your token holds a given scope (CosecRead, CosecWrite, Developer, IntPayroll, IpToken, PmExpense, PmTime, PmRead, PmWrite, TaxRead, TaxWrite)
- ValuesV1 / ValuesV2 *(no scope — echo/test endpoints only)*

---

## 6. Open questions to confirm with GreatSoft before building

1. **OAuth token endpoint URL** + credential type (client-credentials vs. user-delegated) and approved scopes.
2. **Tenant host** — is it `crm.gscloud.co.za` or a firm-specific host?
3. **Employee context** — does the token fix the employee (so `TimeTranDTO` doesn't need an employee field), or must time be posted on behalf of an `EmpID`?
4. **Approval workflow** — are pushed time entries auto-approved, or do they require `Submit` + an `approverId`? What `PeriodRef` scheme do they use?
5. **Rate handling** — must `StdRateID` always be supplied, or will GreatSoft default it from task/activity?
6. **Idempotency / duplicates** — preferred approach to avoid double-posting (use `TimeTranByDate` to reconcile, or store returned `WIPTranDetID` against each of our entries).
