# Payment Database Verification Runbook

## Overview

SQL queries to verify end-to-end payment records in the database after a transaction run,
deployment, or incident investigation. Run these in order — each query builds on the context
of the previous one.

**Target database (shared-pool tenants):** `OrderProcessingSystem_Local` (dev) · adjust connection for stg/prod.  
**Target database (TenantC Option B):** `OrderProcessingSystem_TenantC` — use the dedicated-DB queries in the [Option B section](#option-b-tenantc-dedicated-db-verification) at the end of this runbook.  
**When to run:**
- After a full end-to-end payment test (manual or automated)
- After a production deployment to confirm seeded data and schema are correct
- During incident triage to trace a specific payment

**Runtime note:** The SQL queries in this runbook are runtime-agnostic. Only the way you identify the payment run differs:
- `docker` / `local`: read the physical API/UI log files first, then use the derived prefix with the SQL queries below.
- `azure`: use App Insights to derive the logical run prefix and callback evidence first, then run the same SQL queries below.
- This Azure refinement does **not** change the non-Azure verification flow.

---

## Azure / App Insights quick path

Use this entry path when the payment run happened on Azure App Service and logs live in Application Insights.

For repeat Azure reruns, prefer the script path over manual terminal reconstruction:

```powershell
.\scripts\verify-payment-run-azure.ps1 -Environment <env> -RunPrefix <RUN_PREFIX>
```

The script performs the same App Insights + SQL correlation described below, but does it in one deterministic pass.

### 1. Identify the logical run prefix from API traces

Query only payment-specific API events and derive the shared logical run prefix (for example `OR-1-2ndApr`) from the tenant-specific `CustomerOrderId` values:

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

If more than one `RunPrefix` appears for the day, split them by first timestamp and verify one run at a time.

Replace `{ENV_TAG}` with the env suffix (`dev`, `stg`, `prod`).

### 2. Check UI callback traces narrowly

Do **not** query all UI traces for the day. Query callback-only lines:

```powershell
$uiQuery = @"
traces
| where timestamp >= startofday(now() + 330m) - 330m
| where message has_any('OpenPay callback received', 'payment/callback responded')
| extend application = tostring(customDimensions['Application'])
| where cloud_RoleName has 'ui' or application == 'UI'
| project timestamp, message
| order by timestamp asc
"@
```

Interpret UI callbacks with the 3DS state from the pre-flight SQL query below:
- `Use3DSecure = 1`: callback evidence is expected in UI traces
- `Use3DSecure = 0`: callback evidence is **not** required; the charge is expected to complete synchronously with `ThreeDSecureStage = not_applicable`

Use OR logic (`cloud_RoleName has 'ui' or application == 'UI'`) rather than AND — either property may be absent on some traces. In practice this keeps API and UI traces separated when both apps write to the same App Insights resource.

### 2a. Optional: inspect richer UI payment telemetry

The UI now persists client-originated payment events through `POST /payment/client-event`, so App Insights contains a deeper event stream than the older callback-only traces. Use this query when you need to prove where the browser-side flow stopped before or after 3DS:

```powershell
$uiPaymentTelemetryQuery = @"
traces
| where timestamp >= startofday(now() + 330m) - 330m
| where message startswith 'UI payment event'
| extend application = tostring(customDimensions['Application'])
| where cloud_RoleName has 'ui' or application == 'UI'
| extend uiEventName = tostring(customDimensions['UiEventName'])
| extend tenant = tostring(customDimensions['TenantCode'])
| extend customerOrderId = tostring(customDimensions['CustomerOrderId'])
| extend attemptOrderId = tostring(customDimensions['AttemptOrderId'])
| extend paymentId = tostring(customDimensions['PaymentId'])
| extend flowId = tostring(customDimensions['ClientFlowId'])
| project timestamp, uiEventName, tenant, customerOrderId, attemptOrderId, paymentId, flowId, message
| order by timestamp asc
"@
```

Common event names in this stream:
- `ui_payment_submit_started`
- `ui_payment_token_created`
- `ui_payment_processing_requested`
- `ui_payment_3ds_redirect_started`
- `ui_payment_completed`
- `ui_payment_processing_failed`
- `ui_payment_callback_loaded`
- `ui_payment_callback_confirmation_requested`
- `ui_payment_callback_confirmed`
- `ui_payment_callback_confirmation_failed`

Use this query as a supplement, not a replacement, for the callback-only query above:
- callback traces remain the minimum signal for 3DS callback evidence used by the main Azure verification flow
- `ui_payment_*` traces provide finer-grained browser timing and failure context when callback evidence alone is not enough

### 3. Then run the SQL queries in this runbook

Use the shared logical run prefix in the SQL filters below:
- Example: `OR-1-2ndApr%` for a multi-tenant Azure run
- Example: `OR-4-28Mar-tA-http-dock-prod%` for a single-tenant physical-log run

---

## Execution checklist

Run every item in this order. Do not skip steps — each query validates a precondition used by the next.

**Step 1 — Pre-flight (both DBs)**
- [ ] Pre-flight: `OrderProcessingSystem_Local` — note `ThreeDSEnabled` for TenantA and TenantB
- [ ] Pre-flight: `OrderProcessingSystem_TenantC` — note `ThreeDSEnabled` for TenantC

**Step 2 — Shared-pool DB (`OrderProcessingSystem_Local`)**
- [ ] Q1 — Tenant baseline (Status, TenantTier)
- [ ] Q2 — CardTransactions E2E
- [ ] Q3 — PayinLogs
- [ ] Q4 — PayinLogDetails (row count depends on ThreeDSEnabled)
- [ ] Q5 — TransactionStatusHistories (step count depends on ThreeDSEnabled)
- [ ] Q6 — BillingCustomerKeyInfos
- [ ] Q6a — PaymentProviders per tenant
- [ ] Q7 — TenantC row counts (must be **0** for Option B)
- [ ] Q8 — Cross-tenant bleed check (must be **0 rows**)

**Step 3 — TenantC dedicated DB (`OrderProcessingSystem_TenantC`)** _(Option B only)_
- [ ] Q2-B — CardTransactions E2E
- [ ] Q3-B — PayinLogs
- [ ] Q4-B — PayinLogDetails (row count depends on ThreeDSEnabled)
- [ ] Q5-B — TransactionStatusHistories (step count depends on ThreeDSEnabled)
- [ ] Q6-B — BillingCustomerKeyInfos
- [ ] Q6a-B — PaymentProviders for TenantC
- [ ] Q7-B — TenantC row counts (must match expected values)
- [ ] Q8-B — No shared-pool bleed into dedicated DB (must be **0 rows**)
- [ ] Q9-B — No TenantC bleed into shared DB — run on `OrderProcessingSystem_Local` (must be **0 rows**)

---

## Pre-flight: verify current 3DS state

Run this **before** executing Q2–Q6 (and Q2-B–Q6-B). The expected values in those queries depend
on the `Use3DSecure` flag for each tenant. Misreading the state against hardcoded expectations is the
most common source of false failures.

```sql
-- Run against: OrderProcessingSystem_Local (shared-pool tenants — TenantA and TenantB)
SELECT t.Code AS Tenant, pp.Name AS Provider, pp.Use3DSecure AS ThreeDSEnabled
FROM   dbo.PaymentProviders pp
JOIN   dbo.Tenants          t  ON t.Id = pp.TenantId
ORDER BY pp.TenantId;
```

```sql
-- Run against: OrderProcessingSystem_TenantC (dedicated DB)
SELECT pp.TenantId, pp.Name AS Provider, pp.Use3DSecure AS ThreeDSEnabled
FROM   dbo.PaymentProviders pp;
```

Use the `ThreeDSEnabled` column when reading the Expected sections below:

| `ThreeDSEnabled` | Q4 / Q4-B (PayinLogDetails) | Q5 / Q5-B (StatusHistories) |
|:----------------:|-----------------------------|-----------------------------|
| `1` | 2 rows (`redirect_issued` + `completed`) | 4-step trail |
| `0` | 1 row (`not_applicable`) | 2-step trail |

> `AppMasterData` is **scoped** (per-request) — `Use3DSecure` DB changes take effect on the
> next API request without restart. See [Per-tenant 3DS toggle](#per-tenant-3ds-toggle) for the UPDATE queries.

---

## Design context: two CardTransaction rows per payment

Query 2 returns **two rows per payment** by design — one for card tokenization, one for the charge:

| Row | OpenPayChargeId | Stage | ThreeDS | Reference |
|-----|-----------------|-------|---------|-----------|
| 1 | card token ID | `tokenization_completed` | 0 | NULL |
| 2 _(3DS, `Use3DSecure=1`)_ | charge ID | `completed` | 1 | OpenPay reference no. |
| 2 _(non-3DS, `Use3DSecure=0`)_ | charge ID | `not_applicable` | 0 | OpenPay reference no. (charge succeeded synchronously) |

This is expected and correct.

---

## Query 1 — Tenant baseline

Confirm all tenants are seeded with the correct tier.

```sql
SELECT Id, Code, Name, Status, TenantTier
FROM   dbo.Tenants
ORDER BY Id;
```

**Expected:**
- TenantA, TenantB → `SharedPool`
- TenantC → `Dedicated` — dedicated connection string is resolved at runtime from `DedicatedTenantConnectionStrings:TenantC` in `sharedsettings.local.json` (or Key Vault in Azure). Connection strings are never stored in the database (ADR-009).

---

## Query 2 — CardTransactions (full E2E view)

Full transaction record with billing customer, card token, and OpenPay IDs.

```sql
SELECT
    t.Code                      AS Tenant,
    bc.APICustomerId             AS OpenPayCustomerId,
    pm.Token                     AS CardToken,
    ct.CustomerOrderId,
    ct.AttemptOrderId,
    ct.TransactionId             AS OpenPayChargeId,
    ct.PaymentTraceId,
    ct.TransactionStatus         AS Status,
    ct.TransactionReferenceId    AS OpenPayReference,
    ct.MaskedCardNumber,
    ct.Amount,
    ct.CurrencyCode,
    ct.IsThreeDSecureEnabled     AS ThreeDS,
    ct.ThreeDSecureStage,
    ct.IsTransactionSuccess,
    ct.CreatedDate
FROM   dbo.CardTransactions   ct
JOIN   dbo.BillingCustomers   bc  ON bc.Id = ct.BillingCustomerId
JOIN   dbo.PaymentMethods     pm  ON pm.Id = bc.PaymentMethodId
JOIN   dbo.Tenants            t   ON t.Id  = ct.TenantId
ORDER BY ct.TenantId, ct.Id;
```

**Expected per successful payment (both flows):**
- 2 rows per tenant (tokenization + charge) — same regardless of `Use3DSecure` state; see design context above
- `IsTransactionSuccess = 1`, final `Status = completed`
- `MaskedCardNumber` in format `411111******1111` — raw PAN must never appear
- Different `OpenPayCustomerId` and `CardToken` per tenant — no cross-sharing
- **If `Use3DSecure = 1`:** charge row has `ThreeDS = 1`, `ThreeDSecureStage = completed`, `OpenPayReference` populated
- **If `Use3DSecure = 0`:** charge row has `ThreeDS = 0`, `ThreeDSecureStage = not_applicable`, `OpenPayReference` populated (synchronous)

---

## Query 3 — PayinLogs

One log per charge attempt per tenant (does NOT include tokenization rows).

```sql
SELECT
    t.Code             AS Tenant,
    pl.CustomerOrderId,
    pl.AttemptOrderId,
    pl.OpenPayChargeId,
    pl.PaymentTraceId,
    pl.Amount,
    pl.Currency,
    pl.LastFourCardNbr,
    pl.IsThreeDSecureEnabled AS ThreeDS,
    pl.ThreeDSecureStage,
    pl.Result,
    pl.CreatedDate
FROM   dbo.PayinLogs pl
JOIN   dbo.Tenants   t  ON t.Id = pl.TenantId
ORDER BY pl.TenantId, pl.Id;
```

**Expected:** 1 row per tenant, `Result = 1`.
- **If `Use3DSecure = 1`:** `ThreeDSecureStage = completed`
- **If `Use3DSecure = 0`:** `ThreeDSecureStage = not_applicable`

Check the [Pre-flight query](#pre-flight-verify-current-3ds-state) to know which to expect.

---

## Query 4 — PayinLogDetails (raw request/response audit)

Row count depends on `Use3DSecure` — check the [Pre-flight query](#pre-flight-verify-current-3ds-state) first.

```sql
SELECT
    t.Code                AS Tenant,
    pl.OpenPayChargeId,
    pld.ThreeDSecureStage,
    pld.PaymentTraceId,
    LEFT(pld.PostInfo, 120)       AS PostInfo,
    LEFT(pld.RespInfo, 120)       AS RespInfo,
    LEFT(pld.AdditionalInfo, 120) AS AdditionalInfo
FROM   dbo.PayinLogDetails pld
JOIN   dbo.PayinLogs       pl  ON pl.Id = pld.PayinLogId
JOIN   dbo.Tenants         t   ON t.Id  = pl.TenantId
ORDER BY pl.TenantId, pld.Id;
```

**Expected — 3DS flow (`Use3DSecure = 1`):** 2 rows per tenant per charge:

| Stage | PostInfo | Meaning |
|-------|----------|---------|
| `redirect_issued` | Charge creation request to OpenPay | 3DS flow initiated |
| `completed` | Confirm-status request + OpenPay response | Callback reconciled |

**Expected — non-3DS flow (`Use3DSecure = 0`):** 1 row per tenant per charge:

| Stage | PostInfo | Meaning |
|-------|----------|---------|
| `not_applicable` | Charge creation request to OpenPay | Charge completed synchronously — no 3DS redirect |

---

## Query 5 — TransactionStatusHistories (complete audit trail)

4-step status trail per charge. This is the definitive audit log.

```sql
SELECT
    t.Code                   AS Tenant,
    ct.TransactionId         AS OpenPayChargeId,
    ct.CustomerOrderId,
    tsh.AttemptOrderId,
    tsh.Status,
    tsh.ThreeDSecureStage,
    tsh.IsThreeDSecureEnabled AS ThreeDS,
    tsh.TransactionReferenceId,
    tsh.Notes,
    tsh.CreatedDate
FROM   dbo.TransactionStatusHistories tsh
JOIN   dbo.CardTransactions           ct  ON ct.Id = tsh.TransactionId
JOIN   dbo.Tenants                    t   ON t.Id  = ct.TenantId
ORDER BY ct.TenantId, ct.Id, tsh.Id;
```

**Expected trail per tenant — depends on `Use3DSecure` state (check [Pre-flight query](#pre-flight-verify-current-3ds-state)):**

**3DS flow (`Use3DSecure = 1`) — 4 steps:**

| Step | Status | Stage | Reference | Meaning |
|------|--------|-------|-----------|----------|
| 1 | `completed` | `tokenization_completed` | NULL | Card tokenized by OpenPay |
| 2 | `charge_pending` | `redirect_issued` | NULL | 3DS redirect issued |
| 3 | `completed` | `callback_received` | populated | Browser redirected back |
| 4 | `completed` | `completed` | populated | OpenPay confirmed final status |

**Non-3DS flow (`Use3DSecure = 0`) — 2 steps:**

| Step | Status | Stage | Reference | Meaning |
|------|--------|-------|-----------|---------|
| 1 | `completed` | `tokenization_completed` | NULL | Card tokenized by OpenPay |
| 2 | `completed` | `not_applicable` | OpenPay reference no. | Charge completed synchronously — OpenPay still returns a reference number |

---

## Query 6 — BillingCustomerKeyInfos

Supplementary keys stored per billing customer (e.g. creation timestamp).

```sql
SELECT
    t.Code            AS Tenant,
    bc.APICustomerId  AS OpenPayCustomerId,
    bc.Email,
    bck.KeyName,
    bck.KeyValue,
    bck.CreatedDate
FROM   dbo.BillingCustomerKeyInfos bck
JOIN   dbo.BillingCustomers        bc  ON bc.Id = bck.BillingCustomerId
JOIN   dbo.Tenants                 t   ON t.Id  = bc.TenantId
ORDER BY bc.TenantId, bck.Id;
```

**Expected:** 1 row per tenant with `KeyName = CreationDate` and ISO timestamp value.  
Different `OpenPayCustomerId` per tenant confirms no cross-sharing.

---

## Query 6a — PaymentProviders (per-tenant OpenPay configuration)

Confirms each tenant has a correctly seeded OpenPay provider entry. Without this row, payment processing fails silently.

```sql
SELECT
    t.Code           AS Tenant,
    pp.Id,
    pp.Name,
    pp.APIUrl,
    pp.IsProduction,
    pp.Use3DSecure,
    pp.IsActive,
    pp.TenantId
FROM   dbo.PaymentProviders pp
JOIN   dbo.Tenants          t  ON t.Id = pp.TenantId
ORDER BY pp.TenantId;
```

**Expected:**
- 1 row per tenant with `Name = OpenPay`, `IsActive = 1`, `IsProduction = 0` (sandbox)
- `Use3DSecure`: `1` for all tenants by default. Toggle per tenant via DB UPDATE — see [Per-tenant 3DS toggle](#per-tenant-3ds-toggle) section. Changes take effect on the next request (scoped AppMasterData — ADR-009).
- `APIUrl = https://sandbox-api.openpay.mx/v1`
- Each row has the correct `TenantId` matching the `Tenants` table
- For Option B: TenantC's provider is in `OrderProcessingSystem_TenantC`, not here (run Q6a-B below)

---

## Query 7 — TenantC row counts

Confirms TenantC (Dedicated) has the expected number of DB writes after a successful payment.
Before `DedicatedTenantConnectionStrings:TenantC` is configured in appsettings, the middleware rejects TenantC requests with `400` and all counts remain 0.

```sql
SELECT 'CardTransactions'           AS TableName, COUNT(*) AS Cnt FROM dbo.CardTransactions          WHERE TenantId = 3
UNION ALL
SELECT 'BillingCustomers',           COUNT(*) FROM dbo.BillingCustomers          WHERE TenantId = 3
UNION ALL
SELECT 'PaymentMethods',             COUNT(*) FROM dbo.PaymentMethods             WHERE TenantId = 3
UNION ALL
SELECT 'PayinLogs',                  COUNT(*) FROM dbo.PayinLogs                  WHERE TenantId = 3
UNION ALL
SELECT 'TransactionStatusHistories', COUNT(*) FROM dbo.TransactionStatusHistories WHERE TenantId = (
    SELECT TOP 1 ct.TenantId FROM dbo.CardTransactions ct WHERE ct.TenantId = 3
);
```

> **Note:** `AS RowCount` is a reserved word in `Invoke-Sqlcmd` and causes a syntax error. Use `AS Cnt` (as above) when running via PowerShell.

**Expected after one successful 3DS payment (Option A — same physical DB as shared pool):**
- `CardTransactions` = 2 (tokenization + charge)
- `BillingCustomers` = 1
- `PaymentMethods` = 1
- `PayinLogs` = 1
- `TransactionStatusHistories` = 4

**Expected for Option B (TenantC on dedicated `OrderProcessingSystem_TenantC` DB):** All counts = **0** here — this is correct. TenantC data lives entirely in `OrderProcessingSystem_TenantC`. Run the Option B queries below to verify.

**Expected before `DedicatedTenantConnectionStrings:TenantC` is configured:** All rows = 0 and middleware rejects TenantC requests with `400`.

---

## Query 8 — Cross-tenant bleed check

Detects any data that was written to the wrong tenant's bucket.
Must return 0 rows — any result is a data isolation failure requiring immediate investigation.

```sql
SELECT 'CardTransactions cross-bleed' AS Check,
       ct.CustomerOrderId, ct.TenantId, t.Code
FROM   dbo.CardTransactions ct
JOIN   dbo.Tenants t ON t.Id = ct.TenantId
WHERE  (ct.CustomerOrderId LIKE '%-tA-%' AND ct.TenantId <> 1)
    OR (ct.CustomerOrderId LIKE '%-tB-%' AND ct.TenantId <> 2)
    OR (ct.CustomerOrderId LIKE '%-tC-%' AND ct.TenantId <> 3);
```

**Expected:** 0 rows.  
> Note: this relies on the `CustomerOrderId` naming convention (`-tA-` / `-tB-` suffix).
> For tenants added later, extend the `WHERE` clause with their suffix + expected `TenantId`.
>
> For Option B: TenantC data is not in `OrderProcessingSystem_Local` at all — run Q8-B in the Option B section to verify isolation on the dedicated DB.

---

## Per-tenant 3DS toggle

`Use3DSecure` is a per-tenant flag on the `PaymentProviders` table. It controls whether `ProcessPaymentCommand` requests a 3DS redirect flow from OpenPay.

> `AppMasterData` is **scoped** (per-request) — updating the DB flag takes effect on the **next API request** without restart (ADR-009).

### Enable / disable 3DS for a tenant (shared-pool DB)

```sql
-- Run against: OrderProcessingSystem_Local
-- Disable 3DS for a specific tenant (replace TenantId value as needed)
UPDATE dbo.PaymentProviders SET Use3DSecure = 0 WHERE TenantId = <TenantId>;

-- Re-enable 3DS
UPDATE dbo.PaymentProviders SET Use3DSecure = 1 WHERE TenantId = <TenantId>;

-- Check current state for all tenants
SELECT t.Code AS Tenant, pp.Id, pp.Use3DSecure
FROM   dbo.PaymentProviders pp
JOIN   dbo.Tenants          t  ON t.Id = pp.TenantId
ORDER BY pp.TenantId;
```

**TenantId reference:** TenantA = 1, TenantB = 2. TenantC is in its dedicated DB (see below).

### Enable / disable 3DS for TenantC (dedicated DB)

```sql
-- Run against: OrderProcessingSystem_TenantC
UPDATE dbo.PaymentProviders SET Use3DSecure = 0 WHERE TenantId = 3;

-- Re-enable
UPDATE dbo.PaymentProviders SET Use3DSecure = 1 WHERE TenantId = 3;
```

---

## Non-3DS flow: expected results

When `Use3DSecure = 0` the payment completes **synchronously** — no redirect, no `confirm-status` call needed.

### Differences vs 3DS flow

| Field | 3DS flow (`Use3DSecure = 1`) | Non-3DS flow (`Use3DSecure = 0`) |
|-------|------------------------------|----------------------------------|
| `ProcessPayment` response `status` | `charge_pending` | `completed` |
| `threeDSecureUrl` | present (redirect URL) | `null` |
| `isThreeDSecureEnabled` | `true` | `false` |
| `threeDSecureStage` | `redirect_issued` | `not_applicable` |
| `confirm-status` step required | yes | **no** — charge is already final |
| `CardTransactions` rows | 2 (tokenization + charge) | 2 (tokenization + charge) |
| `TransactionStatusHistories` rows | 4 | 2 (tokenization_completed + completed) |

### Non-3DS CardTransactions expected (shared or dedicated DB)

```sql
-- Both rows have IsThreeDSecureEnabled = 0, ThreeDSecureStage = not_applicable
SELECT ct.CustomerOrderId, ct.TransactionId AS ChargeId,
       ct.TransactionStatus AS Status, ct.IsThreeDSecureEnabled AS ThreeDS,
       ct.ThreeDSecureStage AS Stage, ct.IsTransactionSuccess AS OK
FROM   dbo.CardTransactions ct
JOIN   dbo.Tenants t ON t.Id = ct.TenantId
WHERE  t.Code = '<TenantCode>'   -- e.g. 'TenantB' or 'TenantC'
ORDER BY ct.Id;
```

**Expected:**
- Row 1: `Stage = tokenization_completed`, `ThreeDS = 0`
- Row 2: `Stage = not_applicable`, `ThreeDS = 0`, `Status = completed`

### Non-3DS TransactionStatusHistories expected (2 rows only)

```sql
SELECT tsh.Status, tsh.ThreeDSecureStage AS Stage, tsh.TransactionReferenceId AS Ref
FROM   dbo.TransactionStatusHistories tsh
JOIN   dbo.CardTransactions ct ON ct.Id = tsh.TransactionId
JOIN   dbo.Tenants t ON t.Id = ct.TenantId
WHERE  t.Code = '<TenantCode>'   -- e.g. 'TenantB' or 'TenantC'
ORDER BY tsh.Id;
```

**Expected 2-step trail (no redirect or callback steps):**

| Step | Status | Stage | Meaning |
|------|--------|-------|---------|
| 1 | `completed` | `tokenization_completed` | Card tokenized |
| 2 | `completed` | `not_applicable` | Charge completed directly — no 3DS redirect |

> **Note:** If a prior 3DS payment exists for the same tenant, filter by `ct.CustomerOrderId` to isolate the non-3DS run.

---

## Option B — TenantC dedicated-DB verification

Run these queries connected to **`OrderProcessingSystem_TenantC`** (not `OrderProcessingSystem_Local`).
All shared-pool tables (TenantA, TenantB) must be absent — TenantC only.

> **Why no Q1-B?** Q1 runs on `OrderProcessingSystem_Local` and already shows TenantC's row (`TenantTier = Dedicated`). The dedicated DB does contain its own `Tenants` table (required for JOINs in Q2-B through Q6-B), but verifying the tenant baseline in the shared DB via Q1 is sufficient.

### Q2-B — CardTransactions E2E view (dedicated DB)

Full transaction record including billing customer, card token, and OpenPay IDs — TenantC only.

```sql
-- Run against: OrderProcessingSystem_TenantC
SELECT
    t.Code                      AS Tenant,
    bc.APICustomerId             AS OpenPayCustomerId,
    pm.Token                     AS CardToken,
    ct.CustomerOrderId,
    ct.AttemptOrderId,
    ct.TransactionId             AS OpenPayChargeId,
    ct.PaymentTraceId,
    ct.TransactionStatus         AS Status,
    ct.TransactionReferenceId    AS OpenPayReference,
    ct.MaskedCardNumber,
    ct.Amount,
    ct.CurrencyCode,
    ct.IsThreeDSecureEnabled     AS ThreeDS,
    ct.ThreeDSecureStage,
    ct.IsTransactionSuccess,
    ct.CreatedDate
FROM   dbo.CardTransactions   ct
JOIN   dbo.BillingCustomers   bc  ON bc.Id = ct.BillingCustomerId
JOIN   dbo.PaymentMethods     pm  ON pm.Id = bc.PaymentMethodId
JOIN   dbo.Tenants            t   ON t.Id  = ct.TenantId
WHERE  ct.TenantId = 3
ORDER BY ct.Id;
```

**Expected after one successful payment (both flows):**
- 2 rows (tokenization row + charge row) — identical to shared-pool behaviour; see design context at top of this runbook
- Row 1: `OpenPayChargeId` = card token ID, `ThreeDSecureStage = tokenization_completed`, `IsTransactionSuccess = 1`
- `MaskedCardNumber` in format `411111******1111` — raw PAN must never appear
- `OpenPayCustomerId` must differ from TenantA and TenantB values (no cross-sharing)
- **If `Use3DSecure = 1`:** Row 2 has `ThreeDS = 1`, `ThreeDSecureStage = completed`, `OpenPayReference` populated
- **If `Use3DSecure = 0`:** Row 2 has `ThreeDS = 0`, `ThreeDSecureStage = not_applicable`, `OpenPayReference` populated (synchronous)

---

### Q3-B — PayinLogs (dedicated DB)

One log per charge attempt for TenantC.

```sql
-- Run against: OrderProcessingSystem_TenantC
SELECT
    t.Code             AS Tenant,
    pl.CustomerOrderId,
    pl.AttemptOrderId,
    pl.OpenPayChargeId,
    pl.PaymentTraceId,
    pl.Amount,
    pl.Currency,
    pl.LastFourCardNbr,
    pl.IsThreeDSecureEnabled AS ThreeDS,
    pl.ThreeDSecureStage,
    pl.Result,
    pl.CreatedDate
FROM   dbo.PayinLogs pl
JOIN   dbo.Tenants   t  ON t.Id = pl.TenantId
WHERE  pl.TenantId = 3
ORDER BY pl.Id;
```

**Expected:** 1 row, `Result = 1`.
- **If `Use3DSecure = 1`:** `ThreeDSecureStage = completed`
- **If `Use3DSecure = 0`:** `ThreeDSecureStage = not_applicable`

Check the [Pre-flight query](#pre-flight-verify-current-3ds-state) to know which to expect.

---

### Q4-B — PayinLogDetails (raw request/response audit, dedicated DB)

Row count depends on `Use3DSecure` — check the [Pre-flight query](#pre-flight-verify-current-3ds-state) first.

```sql
-- Run against: OrderProcessingSystem_TenantC
SELECT
    t.Code                        AS Tenant,
    pl.OpenPayChargeId,
    pld.ThreeDSecureStage,
    pld.PaymentTraceId,
    LEFT(pld.PostInfo, 120)       AS PostInfo,
    LEFT(pld.RespInfo, 120)       AS RespInfo,
    LEFT(pld.AdditionalInfo, 120) AS AdditionalInfo
FROM   dbo.PayinLogDetails pld
JOIN   dbo.PayinLogs       pl  ON pl.Id = pld.PayinLogId
JOIN   dbo.Tenants         t   ON t.Id  = pl.TenantId
WHERE  pl.TenantId = 3
ORDER BY pld.Id;
```

**Expected — 3DS flow (`Use3DSecure = 1`):** 2 rows:

| Stage | Meaning |
|-------|---------|
| `redirect_issued` | Charge-creation request sent to OpenPay; 3DS redirect URL issued |
| `completed` | Confirm-status request + OpenPay final-status response; callback reconciled |

**Expected — non-3DS flow (`Use3DSecure = 0`):** 1 row:

| Stage | Meaning |
|-------|---------|
| `not_applicable` | Charge-creation request sent to OpenPay; charge completed synchronously — no redirect |

---

### Q5-B — TransactionStatusHistories 4-step trail (dedicated DB)

Complete audit trail for TenantC's charge. This is the definitive verification of the full payment lifecycle in the dedicated DB.

```sql
-- Run against: OrderProcessingSystem_TenantC
SELECT
    t.Code                   AS Tenant,
    ct.TransactionId         AS OpenPayChargeId,
    ct.CustomerOrderId,
    tsh.AttemptOrderId,
    tsh.Status,
    tsh.ThreeDSecureStage,
    tsh.IsThreeDSecureEnabled AS ThreeDS,
    tsh.TransactionReferenceId,
    tsh.Notes,
    tsh.CreatedDate
FROM   dbo.TransactionStatusHistories tsh
JOIN   dbo.CardTransactions           ct  ON ct.Id = tsh.TransactionId
JOIN   dbo.Tenants                    t   ON t.Id  = ct.TenantId
WHERE  ct.TenantId = 3
ORDER BY ct.Id, tsh.Id;
```

**Expected trail — depends on `Use3DSecure` state (check [Pre-flight query](#pre-flight-verify-current-3ds-state)):**

**3DS flow (`Use3DSecure = 1`) — 4 steps:**

| Step | Status | Stage | Reference | Meaning |
|------|--------|-------|-----------|----------|
| 1 | `completed` | `tokenization_completed` | NULL | Card tokenized by OpenPay |
| 2 | `charge_pending` | `redirect_issued` | NULL | 3DS redirect issued |
| 3 | `completed` | `callback_received` | populated | Browser redirected back |
| 4 | `completed` | `completed` | populated | OpenPay confirmed final status |

**Non-3DS flow (`Use3DSecure = 0`) — 2 steps:**

| Step | Status | Stage | Reference | Meaning |
|------|--------|-------|-----------|---------|
| 1 | `completed` | `tokenization_completed` | NULL | Card tokenized by OpenPay |
| 2 | `completed` | `not_applicable` | OpenPay reference no. | Charge completed synchronously — OpenPay still returns a reference number |

---

### Q6-B — BillingCustomerKeyInfos (dedicated DB)

Supplementary keys stored for TenantC's billing customer.

```sql
-- Run against: OrderProcessingSystem_TenantC
SELECT
    t.Code            AS Tenant,
    bc.APICustomerId  AS OpenPayCustomerId,
    bc.Email,
    bck.KeyName,
    bck.KeyValue,
    bck.CreatedDate
FROM   dbo.BillingCustomerKeyInfos bck
JOIN   dbo.BillingCustomers        bc  ON bc.Id = bck.BillingCustomerId
JOIN   dbo.Tenants                 t   ON t.Id  = bc.TenantId
WHERE  bc.TenantId = 3
ORDER BY bck.Id;
```

**Expected:** 1 row with `KeyName = CreationDate` and ISO timestamp value.  
`OpenPayCustomerId` must differ from TenantA and TenantB values — confirms no cross-sharing.

---

### Q6a-B — PaymentProviders on dedicated DB

Confirms TenantC has its own OpenPay provider seeded in the dedicated DB.

```sql
-- Run against: OrderProcessingSystem_TenantC
SELECT pp.Id, pp.TenantId, pp.Name, pp.APIUrl, pp.IsProduction, pp.Use3DSecure, pp.IsActive
FROM   dbo.PaymentProviders pp
ORDER BY pp.Id;
```

**Expected:** 1 row with `TenantId = 3`, `Name = OpenPay`, `IsActive = 1`, `IsProduction = 0`. `Use3DSecure` reflects the current setting — verify the value against the [Pre-flight query](#pre-flight-verify-current-3ds-state) rather than expecting a hardcoded value.

---

### Q7-B — TenantC row counts (dedicated DB)

```sql
-- Run against: OrderProcessingSystem_TenantC
SELECT 'CardTransactions'           AS TableName, COUNT(*) AS Cnt FROM dbo.CardTransactions          WHERE TenantId = 3
UNION ALL
SELECT 'BillingCustomers',           COUNT(*) FROM dbo.BillingCustomers          WHERE TenantId = 3
UNION ALL
SELECT 'PaymentMethods',             COUNT(*) FROM dbo.PaymentMethods             WHERE TenantId = 3
UNION ALL
SELECT 'PayinLogs',                  COUNT(*) FROM dbo.PayinLogs                  WHERE TenantId = 3
UNION ALL
SELECT 'TransactionStatusHistories', COUNT(*) FROM dbo.TransactionStatusHistories WHERE TenantId = 3;
```

> **Note:** `AS RowCount` is a reserved word in `Invoke-Sqlcmd` and causes a syntax error. Use `AS Cnt` (as above) when running via PowerShell.

**Expected after one successful 3DS payment:**
- `CardTransactions` = 2 (tokenization + charge)
- `BillingCustomers` = 1
- `PaymentMethods` = 1
- `PayinLogs` = 1
- `TransactionStatusHistories` = 4

### Q8-B — No bleed from shared-pool tenants into dedicated DB

Confirms no TenantA or TenantB data was written to TenantC's dedicated DB.
Must return 0 rows.

```sql
-- Run against: OrderProcessingSystem_TenantC
SELECT 'Shared-pool bleed into TenantC dedicated DB' AS Check,
       ct.CustomerOrderId, ct.TenantId
FROM   dbo.CardTransactions ct
WHERE  ct.TenantId <> 3;
```

**Expected:** 0 rows. Any result is a critical isolation failure.

### Q9-B — No TenantC data leaked into shared DB

Run on **`OrderProcessingSystem_Local`** to confirm TenantC payment rows did not bleed into the shared pool.

```sql
-- Run against: OrderProcessingSystem_Local
SELECT 'TenantC bleed into shared DB' AS Check,
       ct.CustomerOrderId, ct.TenantId
FROM   dbo.CardTransactions ct
WHERE  ct.TenantId = 3;
```

**Expected:** 0 rows. Any result means the dedicated-DB routing failed and TenantC wrote to the shared DB instead.
