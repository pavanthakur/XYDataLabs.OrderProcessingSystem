---
agent: agent
description: "Verify a payment test run end-to-end: read today's physical log files for the chosen environment/profile, extract charge IDs and OR prefix, then run the DB verification queries and produce a correlated pass/fail report."
---

# Verify DB + Physical Logs

The user wants to verify that a payment test run is fully consistent across physical log files and
the database. Cover **all three** of: API log → UI log → DB.

---

## Step 1 — Resolve environment and profile

If the user did not specify, ask:
> "Which environment and profile did you run?  
> Options: `dev http docker` · `dev https docker` · `stg http docker` · `stg https docker` ·  
> `prod http docker` · `prod https docker` · `local http` · `local https`"

Accept shorthand (e.g. `"prod https"`, `"stg"`, `"local"`).

Map their answer to the following table:

| Selection | Env tag | API log file | UI log file | Shared DB | TenantC DB |
|---|---|---|---|---|---|
| dev http docker | `dev` | `webapi-dev-http-{DATE}.log` | `ui-dev-http-{DATE}.log` | `OrderProcessingSystem_Dev` | `OrderProcessingSystem_TenantC_Dev` |
| dev https docker | `dev` | `webapi-dev-https-{DATE}.log` | `ui-dev-https-{DATE}.log` | `OrderProcessingSystem_Dev` | `OrderProcessingSystem_TenantC_Dev` |
| stg http docker | `stg` | `webapi-stg-http-{DATE}.log` | `ui-stg-http-{DATE}.log` | `OrderProcessingSystem_Stg` | `OrderProcessingSystem_TenantC_Stg` |
| stg https docker | `stg` | `webapi-stg-https-{DATE}.log` | `ui-stg-https-{DATE}.log` | `OrderProcessingSystem_Stg` | `OrderProcessingSystem_TenantC_Stg` |
| prod http docker | `prod` | `webapi-prod-http-{DATE}.log` | `ui-prod-http-{DATE}.log` | `OrderProcessingSystem_Prod` | `OrderProcessingSystem_TenantC_Prod` |
| prod https docker | `prod` | `webapi-prod-https-{DATE}.log` | `ui-prod-https-{DATE}.log` | `OrderProcessingSystem_Prod` | `OrderProcessingSystem_TenantC_Prod` |
| local dotnet run | `dev` | `webapi-dev-http-{DATE}.log` | `ui-dev-http-{DATE}.log` | `OrderProcessingSystem_Local` | `OrderProcessingSystem_TenantC` |

`{DATE}` = today as `YYYYMMDD` (e.g. `20260328`).  
Log files are in `Q:\GIT\TestAppXY_OrderProcessingSystem\logs\`.

---

## Step 2 — Read today's log files

Read the SQL password:
```powershell
$pass = (Get-Content "Q:\GIT\TestAppXY_OrderProcessingSystem\Resources\Docker\.env.local" |
         Select-String "LOCAL_SQL_PASSWORD" |
         ForEach-Object { ($_ -split "=", 2)[1].Trim() } |
         Select-Object -First 1)
```

Determine today's date tag:
```powershell
$dateTag = (Get-Date).ToString("yyyyMMdd")   # e.g. 20260328
```

Read **API log** — extract only payment-relevant lines:
```powershell
$apiLog  = "Q:\GIT\TestAppXY_OrderProcessingSystem\logs\webapi-{ENV_TAG}-{PROFILE}-$dateTag.log"
Get-Content $apiLog |
  Select-String -Pattern "Generated payment|created charge|charge created|callback reconciliation completed|confirm-status responded|Response: 200.*OR-" |
  ForEach-Object { $_.Line.Trim() }
```

Read **UI log** — extract only callback lines:
```powershell
$uiLog = "Q:\GIT\TestAppXY_OrderProcessingSystem\logs\ui-{ENV_TAG}-{PROFILE}-$dateTag.log"
Get-Content $uiLog |
  Select-String -Pattern "OR-|callback|payment/callback responded" |
  ForEach-Object { $_.Line.Trim() }
```

Replace `{ENV_TAG}` with the env tag and `{PROFILE}` with `http` or `https` from Step 1.

If either file does not exist, note this as a finding and proceed with whichever file is available.

**From the API log, extract and record:**
- All `CustomerOrderId` values seen today (the OR prefix, e.g. `OR-1-28Mar`)
- All `ChargeId` values created (`created charge with ID: <id>`)
- All callback completion results (`callback reconciliation completed … Status completed`)

**From the UI log, extract and record:**
- All callback receipts (`OpenPay callback received … for payment <id>`)
- HTTP response status for each (`/payment/callback responded <N>`)

---

## Step 3 — Determine today's OR prefix

If more than one OR prefix appears in the log today, list them all and ask the user:
> "Multiple OR prefixes found today: `OR-1-28Mar`, `OR-3-27Mar`. Which one should I verify?"

Otherwise use the single prefix found. Use it as `<PREFIX>` for all queries below.

---

## Step 4 — Pre-flight (3DS state)

Read SQL password from Step 2 (`$pass`). Run on both DBs:

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

---

## Step 5 — DB queries

The `<PREFIX>` is the day-specific OR prefix extracted from the log (e.g. `OR-1-28Mar-tA-http-dock-prod`). No date filter is applied — the prefix already scopes to the correct run and avoids UTC/IST timezone offset issues where IST payments before 05:30 land on the previous UTC date.

### Q2 — CardTransactions (shared DB)

```sql
SELECT t.Code AS Tenant, ct.CustomerOrderId, ct.TransactionId AS ChargeId,
       ct.TransactionStatus AS Status, ct.IsThreeDSecureEnabled AS ThreeDS,
       ct.ThreeDSecureStage, ct.TransactionReferenceId AS Ref,
       ct.IsTransactionSuccess AS OK, ct.CreatedDate
FROM   dbo.CardTransactions ct
JOIN   dbo.Tenants t ON t.Id = ct.TenantId
WHERE  ct.CustomerOrderId LIKE '<PREFIX>%'
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
WHERE  ct.CustomerOrderId LIKE '<PREFIX>%'
ORDER BY ct.TenantId, ct.CustomerOrderId, ct.Id, tsh.Id;
```

**Expected:** 4 rows per payment (3DS=1) or 2 rows (3DS=0). See pre-flight table.

### Q8 — Cross-tenant bleed (shared DB)

```sql
SELECT ct.CustomerOrderId, ct.TenantId, t.Code
FROM   dbo.CardTransactions ct
JOIN   dbo.Tenants t ON t.Id = ct.TenantId
WHERE  ct.CustomerOrderId LIKE '<PREFIX>%'
  AND  ((ct.CustomerOrderId LIKE '%-tA-%' AND ct.TenantId <> 1)
     OR (ct.CustomerOrderId LIKE '%-tB-%' AND ct.TenantId <> 2));
```

**Expected: 0 rows.**

### Q2-B — CardTransactions (TenantC dedicated DB)

```sql
SELECT ct.CustomerOrderId, ct.TransactionId AS ChargeId,
       ct.TransactionStatus AS Status, ct.IsThreeDSecureEnabled AS ThreeDS,
       ct.ThreeDSecureStage, ct.TransactionReferenceId AS Ref,
       ct.IsTransactionSuccess AS OK, ct.CreatedDate
FROM   dbo.CardTransactions ct
WHERE  ct.TenantId = 3
  AND  ct.CustomerOrderId LIKE '<PREFIX>%'
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
  AND  ct.CustomerOrderId LIKE '<PREFIX>%'
ORDER BY ct.CustomerOrderId, ct.Id, tsh.Id;
```

**Expected:** 4 rows (3DS=1) or 2 rows (3DS=0).

### Q9-B — No TenantC bleed into shared DB (run on shared DB)

```sql
SELECT ct.CustomerOrderId, ct.TenantId
FROM   dbo.CardTransactions ct
WHERE  ct.TenantId = 3
  AND  ct.CustomerOrderId LIKE '<PREFIX>%';
```

**Expected: 0 rows.**

---

## Step 6 — Correlation check (log ↔ DB)

For each charge ID seen in the API log, confirm it also appears in the DB (Q2 / Q2-B).

| Charge ID (log) | Tenant (log) | In DB? | DB Status | DB Stage | Match |
|---|---|---|---|---|---|
| `<id>` | TenantA/B/C | ✅/❌ | completed/… | completed/… | ✅/❌ |

For each charge ID, confirm the UI log received the callback (`/payment/callback responded 200`):

| Charge ID | UI callback logged? | HTTP status |
|---|---|---|
| `<id>` | ✅/❌ | 200/… |

Flag any charge ID that:
- Is in the API log but **missing from the DB** → persistence failure
- Is in the DB but **missing from the UI callback log** → possible Serilog file-lock issue or missed callback
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
| UI log → callbacks present | all 200 | … | ✅/❌ |

If **any check fails**:
- Missing DB rows → check API errors in the log around the same timestamp
- Missing UI callbacks → check you are reading the **correct profile's** log file (`http` vs `https`); each container writes to its own file since the profile suffix fix
- `Status ≠ completed` → check StatusHistories for the partial trail and compare with OpenPay response in the log
- For full diagnostic queries (Q1, Q3, Q4, Q6, Q6a, Q7 etc.), open `docs/runbooks/payment-db-verification.md`
