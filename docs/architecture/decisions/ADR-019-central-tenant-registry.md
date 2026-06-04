# ADR-019: Central Tenant Registry — Separation of Duties for Payment Provider Assignment

**Status:** Accepted

## Context

Before Phase 8.6, the active payment provider for each tenant was determined by
`PaymentProvider.IsActive` — a column managed entirely by `DbInitializer` at application
startup.
This design had three practical problems:

1. **Developer visibility.** Any developer who could read `DbInitializer.cs` could see which
   provider each tenant was assigned to. Provider assignments are operational configuration,
   not source code.

2. **Ops change requires a code change.** Switching TenantA from Razorpay to OpenPay required
   a code change to `SeedDefaultProvider`, a migration to flip `IsActive`, a PR, CI, and a
   deployment. For an operational parameter this is disproportionate toil.

3. **No per-tenant control.** The constant `SeedDefaultProvider = "Razorpay"` was a
   repository-wide constant. There was no clean path to independently assign different
   providers to different tenants without structural code changes.

### What we already had

`Tenant` was already the domain entity with the widest authority — it carries `TenantTier`,
`ConnectionString`, and determines routing at the infrastructure level. The `ITenantRegistry`
contract and `TenantRegistryDbContext` (a lightweight, no-filter DbContext) already existed
as a clean seam between tenant resolution and business data.

## Decision

Store the active payment provider assignment per-tenant as `Tenant.PaymentProviderCode`
(a nullable `nvarchar(50)` column) and make `ITenantRegistry` the authoritative lookup path
at payment dispatch time.

### What changes

| Concern | Before Phase 8.6 | After Phase 8.6 |
|---------|-----------------|-----------------|
| Provider authority | `PaymentProvider.IsActive` set by `DbInitializer` | `Tenant.PaymentProviderCode` set by migration/ops script |
| Resolver input | `AppMasterData.GetActiveProviderForTenant(tenantId)` | `ITenantRegistry.FindByCode(tenantCode)` → `PaymentProviderCode` |
| `DbInitializer` role | Seeds active provider; calls `ResolveMissingProviderActiveState()` | Seeds both providers `IsActive=false`; no routing logic |
| Ops change process | Code change → PR → CI → deploy | `UPDATE Tenants SET PaymentProviderCode = '…' WHERE Code = '…'` via controlled script |
| Developer code visibility | `SeedDefaultProvider = "Razorpay"` visible in source | Column value lives in database; not in source code |

### Schema

```sql
ALTER TABLE [Tenants] ADD [PaymentProviderCode] nvarchar(50) NULL;
```

Canonical seeded values (applied by migration `AddTenantPaymentProviderCode`):

| Tenant | PaymentProviderCode |
|--------|---------------------|
| TenantA | Razorpay |
| TenantB | Razorpay |
| TenantC | OpenPay |

### Access model

- **Local / dev**: `TenantRegistryDbConnection` points to the shared local SQL Server
  database (`OrderProcessingSystem_Local`). The `Tenants` table is in the same physical
  database as the business data. No separate DB required for local development.
- **Staging / prod (future)**: `TenantRegistryDbConnection` will reference a read-optimised
  replica or a separate admin database accessible only via Managed Identity. Application
  identity gets `db_datareader` on the registry database only; it cannot mutate tenant
  assignments. Operations use a controlled migration/script path with audit logging.

### `PaymentProvider.IsActive` column

`IsActive` is **kept but semantically inert** for routing after Phase 8.6.
It is not dropped to:

- Minimise migration scope and blast radius.
- Preserve existing integration test assertions on the column schema.
- Leave an optional audit signal (a future phase may re-purpose it as a "provider
  credentials validated" flag rather than a routing flag).

`DbInitializer` seeds new rows with `IsActive = false` and a code comment explaining the
inversion. Existing rows' `IsActive` values are not mutated on re-seed, ensuring
idempotency for credential-only updates.

### Sync requirement

`TenantPaymentProviderResolver.ResolveCurrentTenantProvider()` remains synchronous because
`ProcessPaymentCommandHandler` and `ConfirmPaymentStatusCommandHandler` resolve the provider
in their constructors. Making this async would cascade through adapter interfaces,
`SharedKernel`, and all test mocks. `ITenantRegistry.FindByCode(string)` (synchronous) is
added alongside the existing `FindByCodeAsync` to support this path without async
contamination.

## Rationale

| Option considered | Why not chosen |
|-------------------|---------------|
| Keep `IsActive` as authority; add per-tenant constant | Still requires a code change for every ops switch; constants are source-visible |
| Separate `TenantProviderAssignment` table | Additional table, join required, more migration surface — `Tenant` already owns this concern |
| Feature flag / configuration service | External dependency; overkill for a stable per-tenant assignment that changes infrequently |
| **`Tenant.PaymentProviderCode` (chosen)** | Minimal schema change; uses existing registry seam; controlled ops path; no new dependencies |

## Consequences

**Positive:**
- Provider assignments are no longer visible in source code.
- Switching providers for a tenant is a database operation, not a deployment.
- `DbInitializer` is simplified — no routing logic, no `ResolveMissingProviderActiveState`.
- `TenantRegistryDbContext` is now the single read path for tenant configuration at
  dispatch time, consistent with its design intent.
- Independent per-tenant provider assignment is supported without structural changes.

**Negative / trade-offs:**
- `PaymentProvider.IsActive` is now an orphaned column. Future cleanup should drop it once
  all integration tests are migrated off the column.
- Ops teams must ensure `Tenant.PaymentProviderCode` is populated before application startup
  in any new environment. Bootstrap scripts and runbooks must document this requirement.
- `ITenantRegistry.FindByCode` is synchronous. If the registry later becomes a remote service,
  this path will need to be re-evaluated.

## Related

- ADR-007: Hybrid Multi-Tenant Model (SharedPool + Dedicated)
- ADR-009: Tenant Isolation Hardening
- ADR-011: Hand-Rolled CQRS (synchronous resolver constraint)
- `XYDataLabs.OrderProcessingSystem.Infrastructure/Migrations/20260603124839_AddTenantPaymentProviderCode.cs`
