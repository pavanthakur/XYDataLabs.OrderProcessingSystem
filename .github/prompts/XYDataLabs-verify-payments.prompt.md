---
agent: agent
description: "Run after any payment test run or payment-related feature change to verify DB records across shared-pool and dedicated-tenant DBs. Generates filtered verification queries specific to the most recent OR series from the logs."
---

# Payment DB Verification

The user wants to verify payment records in the database.

## Step 1: Identify the most recent run

Ask the user:
- "What OR series prefix did you just run? (e.g. OR-7, OR-9, OR-10 — check the log output or the CustomerOrderId you submitted)"
- "Which environment? (local / stg / prod)"

DB name mapping:
| Environment | Shared DB | TenantC DB |
|-------------|-----------|------------|
| local | `OrderProcessingSystem_Local` | `OrderProcessingSystem_TenantC` |
| stg | `OrderProcessingSystem_Stg` | `OrderProcessingSystem_TenantC_Stg` |
| prod | `OrderProcessingSystem_Prod` | `OrderProcessingSystem_TenantC_Prod` |

Substitute the correct names in all queries below. Steps 2–4 use `<SHARED_DB>` and `<TENANTC_DB>` as placeholders.

If the user doesn't know the prefix, run this query against `<SHARED_DB>` to find the latest:

```sql
SELECT DISTINCT ct.CustomerOrderId, ct.CreatedDate
FROM   dbo.CardTransactions ct
ORDER BY ct.CreatedDate DESC;
```

Note the prefix (e.g. `OR-9-26Mar`) for use in Step 2.

## Step 2: Check current 3DS state (Pre-flight)

Run against **`<SHARED_DB>`**:

```sql
SELECT t.Code AS Tenant, pp.Use3DSecure AS ThreeDSEnabled
FROM   dbo.PaymentProviders pp
JOIN   dbo.Tenants t ON t.Id = pp.TenantId
ORDER BY pp.TenantId;
```

Run against **`<TENANTC_DB>`**:

```sql
SELECT pp.TenantId, pp.Use3DSecure AS ThreeDSEnabled
FROM   dbo.PaymentProviders pp;
```

Note `ThreeDSEnabled` per tenant — this determines expected row counts and stage values below.

## Step 3: Shared DB verification (`<SHARED_DB>`)

Replace `<PREFIX>` with the prefix from Step 1 (e.g. `OR-9-26Mar`).

**Q2 — CardTransactions:**

```sql
SELECT t.Code AS Tenant, ct.CustomerOrderId, ct.TransactionId AS ChargeId,
       ct.TransactionStatus AS Status, ct.IsThreeDSecureEnabled AS ThreeDS,
       ct.ThreeDSecureStage, ct.TransactionReferenceId AS Ref, ct.IsTransactionSuccess AS OK
FROM   dbo.CardTransactions ct
JOIN   dbo.Tenants t ON t.Id = ct.TenantId
WHERE  ct.CustomerOrderId LIKE '<PREFIX>%'
ORDER BY ct.TenantId, ct.CustomerOrderId, ct.Id;
```

Expected per tenant per payment: 2 rows (tokenization + charge). Both `OK = 1`.
- If `ThreeDSEnabled = 1`: charge row `ThreeDS = 1`, `ThreeDSecureStage = completed`, `Ref` populated
- If `ThreeDSEnabled = 0`: charge row `ThreeDS = 0`, `ThreeDSecureStage = not_applicable`, `Ref` populated

**Q5 — TransactionStatusHistories:**

```sql
SELECT t.Code AS Tenant, ct.CustomerOrderId, tsh.Status, tsh.ThreeDSecureStage AS Stage,
       tsh.IsThreeDSecureEnabled AS ThreeDS, tsh.TransactionReferenceId AS Ref
FROM   dbo.TransactionStatusHistories tsh
JOIN   dbo.CardTransactions ct ON ct.Id = tsh.TransactionId
JOIN   dbo.Tenants t ON t.Id = ct.TenantId
WHERE  ct.CustomerOrderId LIKE '<PREFIX>%'
ORDER BY ct.TenantId, ct.CustomerOrderId, ct.Id, tsh.Id;
```

Expected per payment — the **`Stage` column** shows the 3DS pipeline progression; `Status` reflects the payment outcome at each step:
- If `ThreeDSEnabled = 1`: 4 rows. Stage values: `tokenization_completed` → `redirect_issued` → `callback_received` → `completed`. Status values: `completed` → `charge_pending` → `completed` → `completed`
- If `ThreeDSEnabled = 0`: 2 rows. Stage values: `tokenization_completed` → `not_applicable`. Status values: `completed` → `completed`

**Q8 — Cross-tenant bleed check:**

```sql
SELECT ct.CustomerOrderId, ct.TenantId, t.Code
FROM   dbo.CardTransactions ct
JOIN   dbo.Tenants t ON t.Id = ct.TenantId
WHERE  ct.CustomerOrderId LIKE '<PREFIX>%'
AND    ((ct.CustomerOrderId LIKE '%-tA-%' AND ct.TenantId <> 1)
     OR (ct.CustomerOrderId LIKE '%-tB-%' AND ct.TenantId <> 2));
```

**Expected: 0 rows.** Any result is a data isolation failure.

## Step 4: TenantC dedicated DB (`<TENANTC_DB>`)

Replace `<PREFIX>` with the same prefix.

**Q2-B — CardTransactions:**

```sql
SELECT ct.CustomerOrderId, ct.TransactionId AS ChargeId,
       ct.TransactionStatus AS Status, ct.IsThreeDSecureEnabled AS ThreeDS,
       ct.ThreeDSecureStage, ct.TransactionReferenceId AS Ref, ct.IsTransactionSuccess AS OK
FROM   dbo.CardTransactions ct
WHERE  ct.TenantId = 3
  AND  ct.CustomerOrderId LIKE '<PREFIX>%'
ORDER BY ct.CustomerOrderId, ct.Id;
```

Expected: 2 rows (same logic as Q2 above for TenantC's 3DS state).

**Q5-B — TransactionStatusHistories:**

```sql
SELECT ct.CustomerOrderId, tsh.Status, tsh.ThreeDSecureStage AS Stage,
       tsh.IsThreeDSecureEnabled AS ThreeDS, tsh.TransactionReferenceId AS Ref
FROM   dbo.TransactionStatusHistories tsh
JOIN   dbo.CardTransactions ct ON ct.Id = tsh.TransactionId
WHERE  ct.TenantId = 3
  AND  ct.CustomerOrderId LIKE '<PREFIX>%'
ORDER BY ct.CustomerOrderId, ct.Id, tsh.Id;
```

Expected — same Stage/Status pattern as Q5: 4 rows (3DS) or 2 rows (non-3DS); see Q5 expected values above.

**Q9-B — No TenantC bleed into shared DB** (run on `<SHARED_DB>`):

```sql
SELECT ct.CustomerOrderId, ct.TenantId
FROM   dbo.CardTransactions ct
WHERE  ct.TenantId = 3
  AND  ct.CustomerOrderId LIKE '<PREFIX>%';
```

**Expected: 0 rows.**

## Step 5: Report results

Summarise the outcome as a pass/fail table:

| Query | Expected | Actual | Pass? |
|-------|----------|--------|-------|
| Q2 TenantA rows | 2 | ? | ? |
| Q2 TenantB rows | 2 | ? | ? |
| Q5 TenantA steps | 4 or 2 | ? | ? |
| Q5 TenantB steps | 4 or 2 | ? | ? |
| Q8 bleed | 0 | ? | ? |
| Q2-B TenantC rows | 2 | ? | ? |
| Q5-B TenantC steps | 4 or 2 | ? | ? |
| Q9-B TenantC bleed | 0 | ? | ? |

If any query fails, open `docs/runbooks/payment-db-verification.md` for the full query set, design context, and isolation troubleshooting guidance.
