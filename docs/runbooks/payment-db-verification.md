# Payment Database Verification Runbook

## Overview

SQL queries to verify end-to-end payment records in the database after a transaction run,
deployment, or incident investigation. Run these in order — each query builds on the context
of the previous one.

**Target database (shared-pool tenants):** `OrderProcessingSystem_Local` (dev) · adjust connection for stg/prod.  
**Target database (TenantC Option B):** `OrderProcessingSystem_TenantC` — use the dedicated-DB queries in the [Option B section](#option-b--tenantc-dedicated-db-verification) at the end of this runbook.  
**When to run:**
- After a full end-to-end payment test (manual or automated)
- After a production deployment to confirm seeded data and schema are correct
- During incident triage to trace a specific payment

---

## Design context: two CardTransaction rows per payment

Query 2 returns **two rows per payment** by design — one for card tokenization, one for the charge:

| Row | OpenPayChargeId | Stage | ThreeDS | Reference |
|-----|-----------------|-------|---------|-----------|
| 1 | card token ID | `tokenization_completed` | 0 | NULL |
| 2 | charge ID | `completed` | 1 | OpenPay reference no. |

This is expected and correct.

---

## Query 1 — Tenant baseline

Confirm all tenants are seeded, correct tier, and correct `ConnectionString` state.

```sql
SELECT Id, Code, Name, Status, TenantTier,
       CASE WHEN ConnectionString IS NULL THEN 'NULL (SharedPool)' ELSE '*** (Dedicated)' END AS ConnectionString
FROM   dbo.Tenants
ORDER BY Id;
```

**Expected:**
- TenantA, TenantB → `SharedPool`, `ConnectionString = NULL`
- TenantC → `Dedicated`, `ConnectionString = *** (set)` — auto-provisioned on first startup via `DedicatedTenantConnectionStrings:TenantC` in `sharedsettings.local.json` + `ApplyDedicatedConnectionStrings()` in `DbInitializer`. No manual `UPDATE` required.

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

**Expected per successful 3DS payment:**
- 2 rows per tenant (tokenization + charge) — see design context above
- `IsTransactionSuccess = 1`, final `Status = completed`
- `MaskedCardNumber` in format `411111******1111` — raw PAN must never appear
- Different `OpenPayCustomerId` and `CardToken` per tenant — no cross-sharing

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

**Expected:** 1 row per tenant, `Result = 1`, `ThreeDSecureStage = completed`.

---

## Query 4 — PayinLogDetails (raw request/response audit)

Two rows per charge: `redirect_issued` (charge creation) and `completed` (callback reconciliation).

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

**Expected:** 2 rows per tenant per charge:

| Stage | PostInfo | Meaning |
|-------|----------|---------|
| `redirect_issued` | Charge creation request to OpenPay | 3DS flow initiated |
| `completed` | Confirm-status request + OpenPay response | Callback reconciled |

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

**Expected 4-step trail per tenant:**

| Step | Status | Stage | Reference | Meaning |
|------|--------|-------|-----------|---------|
| 1 | `completed` | `tokenization_completed` | NULL | Card tokenized by OpenPay |
| 2 | `charge_pending` | `redirect_issued` | NULL | 3DS redirect issued |
| 3 | `completed` | `callback_received` | 801585 | Browser redirected back |
| 4 | `completed` | `completed` | 801585 | OpenPay confirmed final status |

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
- `Use3DSecure`: `1` for all tenants by default. Toggle per tenant via DB UPDATE — see [Per-tenant 3DS toggle](#per-tenant-3ds-toggle) section. Requires API restart to take effect (singleton reload).
- `APIUrl = https://sandbox-api.openpay.mx/v1`
- Each row has the correct `TenantId` matching the `Tenants` table
- For Option B: TenantC's provider is in `OrderProcessingSystem_TenantC`, not here (run Q6a-B below)

---

## Query 7 — TenantC row counts

Confirms TenantC (Dedicated) has the expected number of DB writes after a successful payment.
Before ConnectionString is provisioned, the middleware rejects TenantC requests with `400` and all counts remain 0.

```sql
SELECT 'CardTransactions'           AS [Table], COUNT(*) AS RowCount FROM dbo.CardTransactions          WHERE TenantId = 3
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

**Expected after one successful 3DS payment (Option A — same physical DB as shared pool):**
- `CardTransactions` = 2 (tokenization + charge)
- `BillingCustomers` = 1
- `PaymentMethods` = 1
- `PayinLogs` = 1
- `TransactionStatusHistories` = 4

**Expected for Option B (TenantC on dedicated `OrderProcessingSystem_TenantC` DB):** All counts = **0** here — this is correct. TenantC data lives entirely in `OrderProcessingSystem_TenantC`. Run the Option B queries below to verify.

**Expected before ConnectionString is provisioned:** All rows = 0 and middleware rejects TenantC requests with `400`.

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

> **Important:** `AppMasterData` is a **singleton** loaded once at API startup. Updating the DB flag takes effect only after the **API is restarted**. No hot-reload is supported.

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

**Expected after one successful 3DS payment:**
- 2 rows (tokenization row + charge row) — identical to shared-pool behaviour; see design context at top of this runbook
- Row 1: `OpenPayChargeId` = card token ID, `ThreeDSecureStage = tokenization_completed`, `IsTransactionSuccess = 1`
- Row 2: `OpenPayChargeId` = charge ID, `ThreeDSecureStage = completed`, `IsTransactionSuccess = 1`
- `MaskedCardNumber` in format `411111******1111` — raw PAN must never appear
- `OpenPayCustomerId` must differ from TenantA and TenantB values (no cross-sharing)

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

**Expected:** 1 row, `Result = 1`, `ThreeDSecureStage = completed`.

---

### Q4-B — PayinLogDetails (raw request/response audit, dedicated DB)

Two audit rows per charge: `redirect_issued` (charge creation) and `completed` (callback reconciliation).

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

**Expected:** 2 rows:

| Stage | Meaning |
|-------|---------|
| `redirect_issued` | Charge-creation request sent to OpenPay; 3DS redirect URL issued |
| `completed` | Confirm-status request + OpenPay final-status response; callback reconciled |

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

**Expected 4-step trail (same pattern as shared-pool tenants):**

| Step | Status | Stage | Reference | Meaning |
|------|--------|-------|-----------|---------|
| 1 | `completed` | `tokenization_completed` | NULL | Card tokenized by OpenPay |
| 2 | `charge_pending` | `redirect_issued` | NULL | 3DS redirect issued |
| 3 | `completed` | `callback_received` | 801585 | Browser redirected back |
| 4 | `completed` | `completed` | 801585 | OpenPay confirmed final status |

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

### Q7-B — TenantC row counts (dedicated DB)

```sql
-- Run against: OrderProcessingSystem_TenantC
SELECT 'CardTransactions'           AS [Table], COUNT(*) AS RowCount FROM dbo.CardTransactions          WHERE TenantId = 3
UNION ALL
SELECT 'BillingCustomers',           COUNT(*) FROM dbo.BillingCustomers          WHERE TenantId = 3
UNION ALL
SELECT 'PaymentMethods',             COUNT(*) FROM dbo.PaymentMethods             WHERE TenantId = 3
UNION ALL
SELECT 'PayinLogs',                  COUNT(*) FROM dbo.PayinLogs                  WHERE TenantId = 3
UNION ALL
SELECT 'TransactionStatusHistories', COUNT(*) FROM dbo.TransactionStatusHistories WHERE TenantId = 3;
```

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

### Q6a-B — PaymentProviders on dedicated DB

Confirms TenantC has its own OpenPay provider seeded in the dedicated DB.

```sql
-- Run against: OrderProcessingSystem_TenantC
SELECT pp.Id, pp.TenantId, pp.Name, pp.APIUrl, pp.IsProduction, pp.Use3DSecure, pp.IsActive
FROM   dbo.PaymentProviders pp
ORDER BY pp.Id;
```

**Expected:** 1 row with `TenantId = 3`, `Name = OpenPay`, `IsActive = 1`, `IsProduction = 0`, `Use3DSecure = 1`.

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
