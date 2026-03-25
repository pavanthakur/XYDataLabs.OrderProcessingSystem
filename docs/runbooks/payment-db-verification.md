# Payment Database Verification Runbook

## Overview

SQL queries to verify end-to-end payment records in the database after a transaction run,
deployment, or incident investigation. Run these in order — each query builds on the context
of the previous one.

**Target database:** `OrderProcessingSystem_Local` (dev) · adjust connection for stg/prod.  
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
- TenantC → `Dedicated`, `ConnectionString = NULL` in dev (provisioned by ops per environment, not seeded)

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

## Query 7 — TenantC isolation check

Confirms TenantC (Dedicated, no ConnectionString provisioned in dev) produced zero DB writes.
The middleware rejects TenantC requests with `400` before any DB write occurs.

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

**Expected:** All rows = 0.

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
    OR (ct.CustomerOrderId LIKE '%-tB-%' AND ct.TenantId <> 2);
```

**Expected:** 0 rows.  
> Note: this relies on the `CustomerOrderId` naming convention (`-tA-` / `-tB-` suffix).
> For tenants added later, extend the `WHERE` clause with their suffix + expected `TenantId`.
