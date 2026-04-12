---
agent: agent
description: |
  Verify a payment test run end-to-end: read today's physical API log plus browser UI telemetry
  captured through the API for local/docker runs, or App Insights KQL for azure runs,
  (azure runtime), extract charge IDs, run DB verification queries, and produce a correlated
  pass/fail report.

  Azure mode must derive a shared logical run prefix, narrow UI callback analysis to callback-only
  traces, and treat UI callbacks as required only for 3DS-enabled tenants. Docker/local mode uses
  the physical API log for backend evidence and browser-originated ui_payment telemetry instead of
  the legacy UI file log.

  Usage examples:
    /XYDataLabs-verify-db-logs "prod docker"
    /XYDataLabs-verify-db-logs "dev azure"
    /XYDataLabs-verify-db-logs "stg"
    /XYDataLabs-verify-db-logs "dev"
    /XYDataLabs-verify-db-logs                ← agent will ask
---

# Verify DB + Logs (Physical or App Insights)

The user wants to verify that a payment test run is fully consistent across log data and
the database. Cover **all three** of: API log → UI telemetry → DB.

Log source depends on **runtime**: `docker`/`local` read the physical API log plus browser-originated UI telemetry captured in that API log; `azure` queries App Insights KQL via Azure CLI.

> **Guardrail:** Any Azure-specific narrowing, parsing, or callback expectations in this prompt apply
> only to the `azure` runtime. Do not change the `docker` or `local` verification flow when updating
> the App Insights path.

---

## Step 1 — Resolve environment and profile

Parse the user's argument (e.g. `"prod https docker"`, `"stg http"`, `"dev"`).

- **env** — one of: `dev`, `stg`, `prod` (default: `dev` if omitted)
- **profile** — `http` or `https` (default: `https` for `azure`; `http` for `docker`/`local`)
- **runtime** — `docker`, `local`, or `azure` (default: `local` if omitted)

If the argument is omitted entirely, ask:
> "Which environment and profile did you run?  
> Examples: `prod docker` · `dev azure` · `stg` · `dev` · `local https`"

Accept shorthand — fill in the defaults for any part not specified.

Map their answer to the following table:

| Selection | Env tag | Log source | API log / KQL scope | Shared DB | TenantC DB |
|---|---|---|---|---|---|
| dev http docker | `dev` | API log + browser UI telemetry | `webapi-dev-dock-http-{DATE}.log` | `OrderProcessingSystem_Dev` | `OrderProcessingSystem_TenantC_Dev` |
| dev https docker | `dev` | API log + browser UI telemetry | `webapi-dev-dock-https-{DATE}.log` | `OrderProcessingSystem_Dev` | `OrderProcessingSystem_TenantC_Dev` |
| dev http azure | `dev` | App Insights KQL | `ai-orderprocessing-dev` / `rg-orderprocessing-dev` | `orderprocessing-sql-dev` → `OrderProcessingSystem_Dev` | `OrderProcessingSystem_TenantC_Dev` |
| dev https azure | `dev` | App Insights KQL | same as `dev http azure` — profile does not affect log source | `orderprocessing-sql-dev` → `OrderProcessingSystem_Dev` | `OrderProcessingSystem_TenantC_Dev` |
| stg http docker | `stg` | API log + browser UI telemetry | `webapi-stg-dock-http-{DATE}.log` | `OrderProcessingSystem_Stg` | `OrderProcessingSystem_TenantC_Stg` |
| stg https docker | `stg` | API log + browser UI telemetry | `webapi-stg-dock-https-{DATE}.log` | `OrderProcessingSystem_Stg` | `OrderProcessingSystem_TenantC_Stg` |
| stg http azure | `stg` | App Insights KQL | `ai-orderprocessing-stg` / `rg-orderprocessing-stg` | `orderprocessing-sql-stg` → `OrderProcessingSystem_Staging` | `OrderProcessingSystem_TenantC_Staging` |
| stg https azure | `stg` | App Insights KQL | same as `stg http azure` — profile does not affect log source | `orderprocessing-sql-stg` → `OrderProcessingSystem_Staging` | `OrderProcessingSystem_TenantC_Staging` |
| prod http docker | `prod` | API log + browser UI telemetry | `webapi-prod-dock-http-{DATE}.log` | `OrderProcessingSystem_Prod` | `OrderProcessingSystem_TenantC_Prod` |
| prod https docker | `prod` | API log + browser UI telemetry | `webapi-prod-dock-https-{DATE}.log` | `OrderProcessingSystem_Prod` | `OrderProcessingSystem_TenantC_Prod` |
| prod http azure | `prod` | App Insights KQL | `ai-orderprocessing-prod` / `rg-orderprocessing-prod` | `orderprocessing-sql-prod` → `OrderProcessingSystem_Prod` | `OrderProcessingSystem_TenantC_Prod` |
| prod https azure | `prod` | App Insights KQL | same as `prod http azure` — profile does not affect log source | `orderprocessing-sql-prod` → `OrderProcessingSystem_Prod` | `OrderProcessingSystem_TenantC_Prod` |
| local dotnet run | `dev` | API log + browser UI telemetry | `webapi-dev-local-http-{DATE}.log` | `OrderProcessingSystem_Local` | `OrderProcessingSystem_TenantC` |

`{DATE}` = today as `YYYYMMDD` (e.g. `20260328`).  
Physical log files are in `Q:\GIT\TestAppXY_OrderProcessingSystem\logs\`.  
Azure resource names: `ai-orderprocessing-{envSuffix}` in `rg-orderprocessing-{envSuffix}` (`staging` → `stg`).

> **Staging Azure DB note:** Docker staging uses the local/container DB names `OrderProcessingSystem_Stg` and `OrderProcessingSystem_TenantC_Stg`, but Azure staging currently uses `OrderProcessingSystem_Staging` and `OrderProcessingSystem_TenantC_Staging` on `orderprocessing-sql-stg`. Be careful not to mix the Docker `stg` DB names with the Azure staging DB names.

> **Local TenantC DB note:** For `local dotnet run`, TenantC's dedicated DB is `OrderProcessingSystem_TenantC` (no environment suffix). Non-local environments do not all share the same suffixing convention, so use the table above instead of assuming `_Dev`, `_Stg`, or `_Prod`.

### Primary execution path — use the verifier scripts first

After resolving `env`, `profile`, and `runtime`, prefer the deterministic script path instead of rebuilding the verification flow manually inside chat.

- Default to the verifier's human-readable table output for the user-facing result.
- Do not use `-OutputFormat Json` unless the user explicitly asks for machine-readable output or you need temporary internal parsing.
- If you use JSON internally to disambiguate or inspect details, still present the final answer as the same formatted pass/fail table plus the key findings.

- If `runtime = docker` or `runtime = local`, run:
```powershell
.\scripts\verify-payment-run-physical.ps1 -Runtime <local|docker> -Environment <env> -Profile <profile>
```

- If `runtime = azure`, run:
```powershell
.\scripts\verify-payment-run-azure.ps1 -Environment <env>
```

Add `-RunPrefix <RUN_PREFIX>` when the user already knows the logical run prefix or when the script reports multiple run prefixes for the day.

Only fall back to the manual log/KQL/SQL steps below when:
- the user explicitly asks for the raw manual investigation flow
- the verifier script fails and you need to diagnose why
- you are auditing or changing the verifier itself

---

## Step 2 — Read the API log (first pass)

### If runtime = `docker` or `local` (physical log)

Read the SQL password:
```powershell
$pass = (Get-Content "Q:\GIT\TestAppXY_OrderProcessingSystem\Resources\Docker\.env.local" |
         Select-String "LOCAL_SQL_PASSWORD" |
         ForEach-Object { ($_ -split "=", 2)[1].Trim() } |
         Select-Object -First 1)
```

Determine today's date tag:
```powershell
$dateTag = (Get-Date).ToString("yyyyMMdd")   # e.g. 20260329
```

Read **API log only** in this step — local/docker UI telemetry is also sourced from this same API log in Step 3 after the PREFIX is confirmed:
```powershell
$apiLog  = "Q:\GIT\TestAppXY_OrderProcessingSystem\logs\webapi-{ENV_TAG}-{RUNTIME}-{PROFILE}-$dateTag.log"
Get-Content $apiLog |
  Select-String -Pattern "Generated payment|created charge|charge created|callback reconciliation completed|confirm-status responded|Response: 200.*OR-" |
  ForEach-Object { $_.Line.Trim() }
```

Replace `{ENV_TAG}` with the env tag, `{RUNTIME}` with `dock` or `local`, and `{PROFILE}` with `http` or `https` from Step 1.

For deterministic reruns outside chat, prefer the script path over rebuilding the log and SQL commands by hand:
```powershell
.\scripts\verify-payment-run-physical.ps1 -Runtime <local|docker> -Environment <env> -Profile <profile> -RunPrefix <RUN_PREFIX>
```

If the API log file does not exist, note this as a finding and stop — the UI telemetry and DB queries cannot be meaningfully scoped without it.

### If runtime = `azure` (App Insights KQL)

The SQL password comes from Key Vault — read it now so it is ready for Steps 4–5:
```powershell
$pass = az keyvault secret show --vault-name kv-orderprocessing-{ENV_TAG} --name sql-admin-password --query value -o tsv
```

> **First-time prerequisite:** If you get `Forbidden`, your CLI identity needs `secrets/get` on the KV. Grant it once:
> ```powershell
> $oid = az ad signed-in-user show --query id -o tsv
> az keyvault set-policy --name kv-orderprocessing-{ENV_TAG} --object-id $oid --secret-permissions get list
> ```
> Then retry the `az keyvault secret show` command above.

Also ensure the firewall is open before running sqlcmd in Steps 4–5:
```powershell
.\Resources\Azure-Deployment\open-local-sql-firewall.ps1 -Environment {env}
```

Replace `{ENV_TAG}` with the env suffix from Step 1 (`dev`, `stg`, `prod`).

Query App Insights for API-side payment events today with a **narrow payment-event query** (IST = UTC+5:30; `startofday(now() + 330m) - 330m` resolves to midnight IST in UTC, preventing missed payments when running before 05:30 UTC). Parse the JSON rows into PowerShell objects so the output is structured instead of a raw App Insights array dump:
```powershell
$apiQuery = @"
traces
| where timestamp >= startofday(now() + 330m) - 330m
| where message has_any('Generated payment attempt order id',
                        'Charge created with ID',
                        'Payment callback reconciliation completed',
                        'confirm-status responded')
| extend application = tostring(customDimensions['Application'])
| where cloud_RoleName has 'api' or application == 'API'
| extend tenant = tostring(customDimensions['TenantCode'])
| extend customerOrderId = coalesce(
    tostring(customDimensions['CustomerOrderId']),
    extract(@'customer order id\s+(\S+)', 1, message),
    extract(@'customer order\s+(\S+)', 1, message))
| extend runPrefix = extract(@'^(OR-\d+-[^-]+)', 1, customerOrderId)
| extend chargeId = coalesce(
    tostring(customDimensions['ChargeId']),
    extract(@'Charge created with ID:\s+(\S+)', 1, message),
    extract(@'payment\s+(\S+)\. Status', 1, message),
    extract(@'/payments/(\S+)/confirm-status', 1, message))
| project timestamp, tenant, customerOrderId, runPrefix, chargeId, message
| order by timestamp asc
"@

$api = az monitor app-insights query `
  --app ai-orderprocessing-{ENV_TAG} `
  --resource-group rg-orderprocessing-{ENV_TAG} `
  --analytics-query $apiQuery `
  --output json | ConvertFrom-Json

$apiRows = foreach ($row in $api.tables[0].rows) {
  [PSCustomObject]@{
    Timestamp       = $row[0]
    Tenant          = $row[1]
    CustomerOrderId = $row[2]
    RunPrefix       = $row[3]
    ChargeId        = $row[4]
    Message         = $row[5]
  }
}
```

> **Note:** `cloud_RoleName` for this project is `pavanthakur-orderprocessing-api-xyapp-{ENV_TAG}`, and the structured `customDimensions['Application']` property is `API` for API traces and `UI` for UI traces. Use OR logic (`cloud_RoleName has 'api' or application == 'API'`) rather than AND — either property may be absent on some traces, and OR ensures no data is silently dropped. `chargeId` is extracted from `customDimensions` when populated, otherwise parsed from the message text. `runPrefix` is the shared logical prefix (e.g. today's run would be scoped by the date portion of the prefix) and is what should scope the DB verification for a multi-tenant Azure test run.

Replace `{ENV_TAG}` with the env suffix from Step 1 (`dev`, `stg`, `prod`).

**From the API output, extract and record:**
- Distinct `RunPrefix` candidates (for example `OR-1-2ndApr`)
- Tenant-specific `CustomerOrderId` values seen
- All `ChargeId` values created
- All callback completion results

---

## Step 3 — Confirm the run prefix, then read the UI telemetry

**Determine the RUN_PREFIX:**

If more than one logical run prefix appears in the API output, find the first timestamp for each and ask the user:
> "Multiple payment run prefixes found today:
> - `OR-1-28Mar` — first entry at 14:23:05
> - `OR-3-28Mar` — first entry at 16:47:12
>
> Which one should I verify?"

Showing the timestamp of the first entry is more reliable than listing the prefix strings alone — the user can identify the correct run by time rather than by memory of the prefix counter.

Otherwise use the single prefix found. Use it as `<RUN_PREFIX>` for all queries below.

### If runtime = `docker` or `local` (physical API log + browser telemetry)

```powershell
$apiLog = "Q:\GIT\TestAppXY_OrderProcessingSystem\logs\webapi-{ENV_TAG}-{RUNTIME}-{PROFILE}-$dateTag.log"
Get-Content $apiLog |
  Select-String -Pattern "<RUN_PREFIX>" |
  ForEach-Object { $_.Line.Trim() } |
  Where-Object {
    $_ -match 'UI payment event' -or
    $_ -match 'OpenPay callback received' -or
    $_ -match 'payment/callback responded'
  }
```

Replace `<RUN_PREFIX>` with the confirmed prefix literal (e.g. `OR-4-28Mar`). Using the exact prefix rather than the broad `callback` keyword ensures that same-day retry runs earlier in the same API log do not contaminate the extraction.

These lines are browser-originated `ui_payment_*` events forwarded through `POST /payment/client-event`, so they represent SPA activity without depending on the legacy ASP.NET UI file log.

If no browser UI telemetry lines match the selected prefix, note this as a finding and proceed with DB queries.

### If runtime = `azure` (App Insights KQL)

> **Note:** Both the API (`pavanthakur-orderprocessing-api-xyapp-{ENV_TAG}`) and the UI (`pavanthakur-orderprocessing-ui-xyapp-{ENV_TAG}`) send Serilog traces to App Insights via the `Serilog.Sinks.ApplicationInsights` sink. Query the UI by `cloud_RoleName has 'ui'` and the API by `cloud_RoleName has 'api'`.

Query UI callback traces with a **callback-only** filter. Do not treat absence of a UI callback as failure for non-3DS tenants; callback evidence is required only when Step 4 shows `ThreeDSEnabled = 1` for that tenant.

Query UI callback traces with:
```powershell
az monitor app-insights query `
  --app ai-orderprocessing-{ENV_TAG} `
  --resource-group rg-orderprocessing-{ENV_TAG} `
  --analytics-query "
    traces
    | where timestamp >= startofday(now() + 330m) - 330m
    | where message has_any('OpenPay callback received', 'payment/callback responded')
    | extend application = tostring(customDimensions['Application'])
    | where cloud_RoleName has 'ui' or application == 'UI'
    | project timestamp, message,
              chargeId   = tostring(customDimensions['ChargeId']),
              statusCode = tostring(customDimensions['StatusCode'])
    | order by timestamp asc" `
  --output json
```

**From the UI output, extract and record:**
- All callback receipts (`OpenPay callback received … for payment <id>`)
- HTTP response status for each (`/payment/callback responded <N>`)
- Which `chargeId` values from Step 2 appear in the UI callback log

---

## Step 4 — Pre-flight (3DS state)

Use `$pass` from Step 2 for sqlcmd authentication against `<SQL_SERVER>.database.windows.net`.
- **docker/local**: `$pass` is from `.env.local`; SQL server is `localhost` (or connection string in compose)
- **azure**: `$pass` is from Key Vault; SQL server is `orderprocessing-sql-{ENV_TAG}.database.windows.net` (ensure firewall open via `open-local-sql-firewall.ps1 -Environment {env}` first)

Run on both DBs:

```sql
-- Shared DB (<SHARED_DB>)
SELECT t.Code AS Tenant, pp.Use3DSecure AS ThreeDSEnabled
FROM   dbo.PaymentProviders pp
JOIN   dbo.Tenants t ON t.Id = pp.TenantId
ORDER BY pp.TenantId;
```

```sql
-- TenantC DB (<TENANTC_DB>)
SELECT pp.TenantId, pp.Use3DSecure AS ThreeDSEnabled
FROM   dbo.PaymentProviders pp;
```

Note the `ThreeDSEnabled` per tenant — it controls expected row counts in Q2/Q5/Q2-B/Q5-B:

| `ThreeDSEnabled` | Q2 / Q2-B (CardTransactions) | Q5 / Q5-B (StatusHistories) |
|:---:|---|---|
| `1` | 2 rows; charge row has `ThreeDS=1`, `Stage=completed`, `Ref` populated | 4 rows: `tokenization_completed → redirect_issued → callback_received → completed` |
| `0` | 2 rows; charge row has `ThreeDS=0`, `Stage=not_applicable`, `Ref` populated | 2 rows: `tokenization_completed → not_applicable` |

> **Tokenization row `ThreeDS` field:** The tokenization row (`Stage=tokenization_completed`) always records `IsThreeDSecureEnabled=0` regardless of tenant configuration — 3DS determination happens after tokenization. This is expected data, not an inconsistency. Only the charge row (`Stage=completed` or `Stage=not_applicable`) reflects the actual 3DS outcome for the tenant.

> **If either query returns 0 rows or the expected tenants are missing:** the DB has not been seeded or the migration has not run for this environment. Do not proceed to Q2/Q5 — the expected row counts will be undefined. Fix the seeding or migration issue first, then restart the verification from Step 4.

---

## Step 5 — DB queries

The `<RUN_PREFIX>` is the logical run prefix extracted from the log. For a single-tenant physical-log run it may be the full customer-order prefix (for example `OR-1-28Mar-tA-http-dock-prod`). For a multi-tenant Azure run it is often the shared prefix before `-tA-/-tB-/-tC-` (for example `OR-1-2ndApr`). No date filter is applied — the prefix already scopes to the correct run and avoids UTC/IST timezone offset issues where IST payments before 05:30 land on the previous UTC date.

### Q2 — CardTransactions (shared DB)

```sql
SELECT t.Code AS Tenant, ct.CustomerOrderId, ct.TransactionId AS ChargeId,
       ct.TransactionStatus AS Status, ct.IsThreeDSecureEnabled AS ThreeDS,
       ct.ThreeDSecureStage, ct.TransactionReferenceId AS Ref,
       ct.IsTransactionSuccess AS OK, ct.CreatedDate
FROM   dbo.CardTransactions ct
JOIN   dbo.Tenants t ON t.Id = ct.TenantId
WHERE  ct.CustomerOrderId LIKE '<RUN_PREFIX>%'
ORDER BY ct.TenantId, ct.CustomerOrderId, ct.Id;
```

**Expected:** 2 rows per tenant per payment (tokenization + charge). Both `OK = 1`.

### Q5 — TransactionStatusHistories (shared DB)

```sql
SELECT t.Code AS Tenant, ct.CustomerOrderId, tsh.Status,
       tsh.ThreeDSecureStage AS Stage, tsh.IsThreeDSecureEnabled AS ThreeDS,
       tsh.TransactionReferenceId AS Ref
FROM   dbo.TransactionStatusHistories tsh
JOIN   dbo.CardTransactions ct ON ct.Id = tsh.TransactionId
JOIN   dbo.Tenants t ON t.Id = ct.TenantId
WHERE  ct.CustomerOrderId LIKE '<RUN_PREFIX>%'
ORDER BY ct.TenantId, ct.CustomerOrderId, ct.Id, tsh.Id;
```

**Expected:** 4 rows per payment (3DS=1) or 2 rows (3DS=0). See pre-flight table.

### Q8 — Cross-tenant bleed (shared DB)

```sql
SELECT ct.CustomerOrderId, ct.TenantId, t.Code
FROM   dbo.CardTransactions ct
JOIN   dbo.Tenants t ON t.Id = ct.TenantId
WHERE  ct.CustomerOrderId LIKE '<RUN_PREFIX>%'
  AND  ((ct.CustomerOrderId LIKE '%-tA-%' AND ct.TenantId <> 1)
     OR (ct.CustomerOrderId LIKE '%-tB-%' AND ct.TenantId <> 2));
```

**Expected: 0 rows.**

> **Maintenance note:** This query checks TenantA (`-tA-`) and TenantB (`-tB-`) identifiers only. TenantC bleed into the shared DB is caught separately by Q9-B. If a fourth tenant is added in future, extend this WHERE clause to include it — otherwise cross-tenant bleed for the new tenant will pass silently.

### Q2-B — CardTransactions (TenantC dedicated DB)

```sql
SELECT ct.CustomerOrderId, ct.TransactionId AS ChargeId,
       ct.TransactionStatus AS Status, ct.IsThreeDSecureEnabled AS ThreeDS,
       ct.ThreeDSecureStage, ct.TransactionReferenceId AS Ref,
       ct.IsTransactionSuccess AS OK, ct.CreatedDate
FROM   dbo.CardTransactions ct
WHERE  ct.TenantId = 3
  AND  ct.CustomerOrderId LIKE '<RUN_PREFIX>%'
ORDER BY ct.CustomerOrderId, ct.Id;
```

**Expected:** 2 rows (same logic as Q2 for TenantC's 3DS state).

### Q5-B — TransactionStatusHistories (TenantC dedicated DB)

```sql
SELECT ct.CustomerOrderId, tsh.Status, tsh.ThreeDSecureStage AS Stage,
       tsh.IsThreeDSecureEnabled AS ThreeDS, tsh.TransactionReferenceId AS Ref
FROM   dbo.TransactionStatusHistories tsh
JOIN   dbo.CardTransactions ct ON ct.Id = tsh.TransactionId
WHERE  ct.TenantId = 3
  AND  ct.CustomerOrderId LIKE '<RUN_PREFIX>%'
ORDER BY ct.CustomerOrderId, ct.Id, tsh.Id;
```

**Expected:** 4 rows (3DS=1) or 2 rows (3DS=0).

### Q9-B — No TenantC bleed into shared DB (run on shared DB)

```sql
SELECT ct.CustomerOrderId, ct.TenantId
FROM   dbo.CardTransactions ct
WHERE  ct.TenantId = 3
  AND  ct.CustomerOrderId LIKE '<RUN_PREFIX>%';
```

**Expected: 0 rows.**

> **Note:** This checks that TenantC records were never written to the shared DB at all (a DB router or connection-string misconfiguration bug), not just that they are isolated within it. TenantC's rows should only ever exist in `<TENANTC_DB>`. This is a different failure class from Q8, which checks cross-tenant bleed within the shared DB.

---

## Step 6 — Correlation check (log ↔ DB)

For each charge ID seen in the API log, confirm it also appears in the DB (Q2 / Q2-B).

| Charge ID (log) | Tenant (log) | In DB? | DB Status | DB Stage | Match |
|---|---|---|---|---|---|
| `<id>` | TenantA/B/C | ✅/❌ | completed/… | completed/… | ✅/❌ |

For each charge ID, confirm the UI telemetry received the callback **when a callback is expected**:

| Charge ID | Tenant | 3DS enabled? | UI callback expected? | UI callback logged? | HTTP status |
|---|---|---|---|---|---|
| `<id>` | TenantA/B/C | 1/0 | ✅ / N/A | ✅/❌/N/A | 200/… |

Flag any charge ID that:
- Is in the API log but **missing from the DB** → persistence failure
- Is in the DB but **missing from the UI callback log when `ThreeDSEnabled = 1`** → possible UI/App Insights logging gap or missed callback
- Has `Status ≠ completed` in the DB → incomplete payment flow

---

## Step 7 — Report

Output a consolidated pass/fail table:

| Check | Expected | Actual | Pass? |
|---|---|---|---|
| Pre-flight TenantA 3DS | configured | … | ✅/❌ |
| Pre-flight TenantB 3DS | configured | … | ✅/❌ |
| Pre-flight TenantC 3DS | configured | … | ✅/❌ |
| Q2 TenantA rows | 2 | … | ✅/❌ |
| Q2 TenantB rows | 2 | … | ✅/❌ |
| Q5 TenantA steps | 4 or 2 | … | ✅/❌ |
| Q5 TenantB steps | 4 or 2 | … | ✅/❌ |
| Q8 bleed | 0 | … | ✅/❌ |
| Q2-B TenantC rows | 2 | … | ✅/❌ |
| Q5-B TenantC steps | 4 or 2 | … | ✅/❌ |
| Q9-B TenantC bleed | 0 | … | ✅/❌ |
| API log → DB charge IDs | all match | … | ✅/❌ |
| UI telemetry → callbacks present where expected | 3DS tenants only | … | ✅/❌ |

When the verifier script is used, mirror its table-style summary in the chat response. Only surface raw JSON when the user explicitly asks for JSON or machine-readable output.

> **Scope note:** This runbook covers `CardTransactions` and `TransactionStatusHistories` only. `PayinLog` and `PayinLogDetails` tables are intentionally out of scope here — they require the full diagnostic query set. See `docs/runbooks/payment-db-verification.md` for Q1, Q3, Q4, Q6, Q6a, Q7 and the PayinLog queries.

If **any check fails**:
- Missing DB rows → check API errors in the log around the same timestamp
- Missing UI callbacks → check you are reading the **correct profile's** log file (`http` vs `https`); each container writes to its own file since the profile suffix fix
- `Status ≠ completed` → check StatusHistories for the partial trail and compare with OpenPay response in the log
- For full diagnostic queries (Q1, Q3, Q4, Q6, Q6a, Q7 etc.), open `docs/runbooks/payment-db-verification.md`
