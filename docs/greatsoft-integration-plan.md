# GreatSoft time-entry integration plan

This integration is designed to be added without changing the existing live
single-page app flow until the backend has been tested.

## Scope

The app will create time entries in GreatSoft, but it will not submit the weekly
timesheet for approval.

GreatSoft manual weekly submission stays inside GreatSoft. This app only calls:

- `POST /api/V2/Timesheet/TimeTran`

This app must not call:

- `POST /api/V2/Timesheet/Submit`

## Mapping model

The intended mapping is:

| HVNSAuditPro | GreatSoft |
| --- | --- |
| `audits` | Client |
| `sections` | Task / job |
| `subsections` | Activity |
| `step_logs.hours` | Time entry hours |

The migration adds nullable GreatSoft columns to the current tables. Because
they are nullable and unused by the existing frontend, applying the migration
should not affect the current live app.

## Safe rollout

1. Apply the database migration in a staging Supabase project first.
2. Deploy the Edge Functions to staging.
3. Set GreatSoft secrets in staging only.
4. Use `greatsoft-test-connection` to verify credentials and API access.
5. Use `greatsoft-generate-time-entries` with `dryRun: true`.
6. Confirm that mapping errors and payloads look right.
7. Enable actual pushes only by setting `GREATSOFT_PUSH_ENABLED=true`.
8. Test with one staff member and one week.
9. Only after the backend is trusted, wire a button into `index.html`.

## Required Supabase secrets

```text
SUPABASE_URL
SUPABASE_ANON_KEY
SUPABASE_SERVICE_ROLE_KEY
GREATSOFT_BASE_URL
GREATSOFT_TOKEN_URL
GREATSOFT_CLIENT_ID
GREATSOFT_CLIENT_SECRET
GREATSOFT_SCOPE
GREATSOFT_PUSH_ENABLED
```

Recommended initial values:

```text
GREATSOFT_BASE_URL=https://crm.gscloud.co.za/rest
GREATSOFT_SCOPE=INT.Payroll PM.Time PM.Read
GREATSOFT_PUSH_ENABLED=false
```

## Backend functions

### `greatsoft-test-connection`

Checks that the backend can obtain a GreatSoft OAuth access token and call the
open API info endpoint. This does not create time entries.

### `greatsoft-generate-time-entries`

Builds GreatSoft time-entry payloads from `step_logs`.

By default it runs as a dry run and returns payload previews. Actual GreatSoft
POST calls are blocked unless:

```json
{
  "dryRun": false
}
```

and the deployed function has:

```text
GREATSOFT_PUSH_ENABLED=true
```

This double lock is intentional so the backend can be tested without touching
live GreatSoft time records.

