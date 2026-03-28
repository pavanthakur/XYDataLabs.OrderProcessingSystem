# Architecture Instruction Guideline

## XYDataLabs.OrderProcessingSystem

### Multitenant Payment Schema Standard

Document ID: EAS-2025-001  
Status: Binding  
Scope: All entities, DTOs, handlers, controllers, middleware, migrations, and tests in this repository

This file is the authoritative implementation standard for tenant modeling, payment identifier naming, migration behavior, and test enforcement in this solution. Treat every checklist here as a gate, not guidance.

## 1. Binding Rules

1. Do not introduce new tenant-owned entities without `TenantId` FK ownership.
2. Do not introduce new payment identifiers outside the canonical vocabulary in this file.
3. Do not expose `Tenant.Id` or `PaymentTraceId` in customer-facing DTOs.
4. Do not add tenant seed data anywhere except the baseline migration or an explicitly named seed migration.
5. Do not rely on ambient tenant context in non-request code paths.
6. Do not change these rules without an architecture review and an ADR.

## 2. Tenant Model

The tenant model uses three keys for three distinct audiences.

| Property | Audience | Stability | Allowed surfaces |
|---|---|---|---|
| `Tenant.Id` | Database and EF only | Internal | FK columns, query filters, save stamping |
| `Tenant.ExternalId` | External integrations | Immutable | External API contracts, webhooks, third-party integrations |
| `Tenant.Code` | Operations and runtime resolution | Stable with notice | `X-Tenant-Code`, logs, admin tooling |

Current canonical entity shape:

```csharp
public class Tenant
{
    public int Id { get; set; }
    public string ExternalId { get; set; } = string.Empty;
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public string TenantTier { get; set; } = "SharedPool";   // "SharedPool" | "Dedicated"
    // ConnectionString removed (ADR-009): dedicated DB connections are resolved at runtime
    // from IConfiguration["DedicatedTenantConnectionStrings:{Code}"], never persisted in the DB.
    public int? CreatedBy { get; set; }
    public DateTime? CreatedDate { get; set; }
    public int? UpdatedBy { get; set; }
    public DateTime? UpdatedDate { get; set; }
}
```

Tenant statuses are operationally meaningful:

| Status | Meaning | Middleware result |
|---|---|---|
| `Active` | Tenant can use the system | Request continues |
| `Suspended` | Tenant exists but is blocked | HTTP 403 |
| `Decommissioned` | Tenant exists but is permanently closed | HTTP 403 |

## 3. Tenant Resolution Rules

Every inbound request follows exactly one of these outcomes:

1. Missing `X-Tenant-Code` -> HTTP 400 and stop immediately.
2. Unknown `X-Tenant-Code` -> HTTP 400 and stop immediately.
3. Resolved tenant with `Suspended` or `Decommissioned` status -> HTTP 403 and stop immediately.
4. Resolved `Active` tenant -> continue with canonical tenant context.
5. The only approved headerless bootstrap path is `GET /api/v1/info/runtime-configuration`.
6. UI/browser code must acquire the active tenant code from API runtime configuration, never from UI-local configuration.

Required runtime contract:

```csharp
public interface ITenantProvider
{
    bool HasTenantContext { get; }
    int TenantId { get; }
    string TenantCode { get; }
    string TenantExternalId { get; }
    string? ConnectionString { get; }
    bool IsSharedPool { get; }
}
```

No null tenant context may flow downstream from middleware.

## 4. Payment Identifier Vocabulary

These are the only approved payment identifier names in the codebase.

| Identifier | Meaning | Allowed surfaces |
|---|---|---|
| `CustomerOrderId` | Business-visible order reference | UI, customer-facing responses, receipts |
| `AttemptOrderId` | Single payment-attempt/provider reference | Provider calls, callback reconciliation, technical diagnostics |
| `PaymentTraceId` | Internal correlation id | Structured logs and telemetry only |

Surface rules:

1. `CustomerOrderId` is the only order identifier that may appear in customer-facing UI or response payloads.
2. `AttemptOrderId` is not a customer-facing field.
3. `PaymentTraceId` never leaves the server in customer-facing APIs or UI.
4. `Tenant.ExternalId` is the only tenant identifier allowed in external contracts.
5. `Tenant.Id` never appears in API responses, logs intended for consumers, or UI.

## 5. Banned Names

Do not introduce these names in new code or new schema changes for payment and tenant modeling.

| Banned name | Use instead |
|---|---|
| `OrderId` for payment attempt identity | `AttemptOrderId` |
| `ReferenceNo` | `AttemptOrderId` or a provider-specific explicit name |
| `APINO1` | `OpenPayChargeId` |
| `APINO2` | `OpenPayAuthorizationId` |
| `TenantCode` on tenant-owned rows | `TenantId` FK only |
| `X-Tenant-Id` | `X-Tenant-Code` |

Existing legacy fields should be migrated toward the canonical names when touched.

## 6. New Entity Checklist

Use this every time a new entity is created.

### 6.1 Tenant-owned entities

1. Inherit from the correct base type:

```csharp
public class MyEntity : BaseAuditableEntity { }
// or
public class MyEntity : BaseAuditableCreateEntity { }
```

2. Never redeclare `TenantId` on the derived type.
3. Use canonical payment/tenant identifiers only.
4. Add EF configuration:
   - FK to `Tenants`
   - global query filter using `ITenantProvider.TenantId`
   - composite indexes for every tenant-scoped lookup key
5. Ensure save stamping picks it up automatically.
6. Add or update architecture and integration tests.

### 6.2 System entities

System entities include `Tenant` itself and any future system-wide control tables.

1. Do not make them tenant-owned.
2. Do not apply tenant query filters to them.
3. Manage audit fields explicitly if needed.

## 7. New DTO Checklist

1. Identify whether the DTO is customer-facing, provider-facing, or internal.
2. Customer-facing DTOs may include `CustomerOrderId` but must not include `AttemptOrderId` unless it is explicitly a technical/admin surface.
3. Customer-facing DTOs must not expose `PaymentTraceId`.
4. No DTO leaving the server may expose `Tenant.Id`.
5. External tenant identity, if needed, must use `Tenant.ExternalId`.
6. Customer-facing UI must not define its own active tenant source; it must consume the API-owned runtime configuration contract.

## 8. DbContext Rules

The DbContext is the enforcement point for tenant integrity.

Required rules:

1. Every tenant-owned entity must have a non-nullable `TenantId` int FK.
2. Every tenant-owned entity must have a global query filter scoped to `ITenantProvider.TenantId`.
3. `Tenants` must be explicitly excluded from tenant query filters.
4. Save stamping applies only to tenant-owned base classes.
5. `Tenants` and any other non-tenant-owned system tables are exempt from tenant stamping.

Mandatory composite indexes already standardized:

| Entity | Required composite indexes |
|---|---|
| `CardTransaction` | `(TenantId, CustomerOrderId)`, `(TenantId, AttemptOrderId)` |
| `PayinLog` | `(TenantId, AttemptOrderId)` |
| `TransactionStatusHistory` | `(TenantId, AttemptOrderId)` |

## 9. Migration Rules

1. The repository uses a single clean baseline migration plus future incremental migrations.
2. The current baseline migration is `RebaselineMultitenantPaymentSchema`.
3. `TenantA` and `TenantB` are seeded in the baseline migration `Up()` method.
4. New tenant-owned tables must include:
   - FK to `Tenants(Id)`
   - required composite indexes
   - no string tenant surrogate columns
5. After generating any migration, run a drift check by generating a second migration. It must be empty.
6. Remove the temporary drift-check migration immediately after verification.

## 10. Non-request Operations

The following code paths must pass `TenantId` explicitly and must not depend on ambient middleware state:

1. `DbInitializer`
2. background jobs
3. integration test fixtures
4. any out-of-band scripts or import utilities

Rule: stamp tenant-owned entities, not everything.

### 10.1 DbInitializer — Dedicated-DB seeding (Phase 2)

`DbInitializer.Initialize()` accepts an optional `IConfiguration` parameter. After running `Database.Migrate()`, it:

1. Seeds shared-pool sample data (Phase 1: TenantA, TenantB).
2. Calls `SeedDedicatedTenants()` (Phase 2) — for each Dedicated-tier tenant, reads the connection string from `IConfiguration["DedicatedTenantConnectionStrings:{Code}"]`, creates a scoped `OrderProcessingSystemDbContext` with `NullTenantProvider` and runs `Database.Migrate()` + sample data seeding on the dedicated DB. Connection strings are never stored in the `Tenants` table (ADR-009).

**NullTenantProvider** is a null-object `ITenantProvider` with `HasTenantContext = false`. It prevents query filter NullReferenceException in non-request contexts. The filter short-circuits to `true` (all rows visible), which is correct for dedicated-DB seeding where physical isolation replaces query-filter isolation.

**Config pattern** — each environment provides its own `DedicatedTenantConnectionStrings` section:
- Local: `sharedsettings.local.json`
- Azure: Key Vault references or App Settings

## 11. Required Tests

These tests form the compliance envelope for the standard.

### 11.1 Architecture tests

Required concerns:

1. migration drift
2. required composite index presence
3. tenant filter isolation
4. identifier surface compliance

Current examples live in:

- `EfMigrationDriftTests`
- `MultiTenantSchemaTests`

### 11.2 Middleware and integration tests

Required concerns:

1. HTTP 400 for missing `X-Tenant-Code`
2. HTTP 400 for unknown `X-Tenant-Code`
3. HTTP 403 for `Suspended` and `Decommissioned` tenants
4. per-class tenant isolation
5. no reuse of global baseline tenant rows in test data setup

### 11.3 Dedicated-DB isolation tests

Required concerns:

1. Dedicated + unprovisioned (null CS) + Active → 400 (fail-loud)
2. Dedicated + provisioned + Active → 200 (routed to dedicated DB)
3. Data written to dedicated tenant exists in dedicated DB (direct SQL verification)
4. Dedicated tenant data not visible via direct query on shared-pool DB
5. SharedPool tenant data not visible via direct query on dedicated DB

Current examples live in `DedicatedTenantTests`.

### 11.4 Payment handler tests

Required regression guards (both tenant tiers):

1. Both CardTransaction rows (tokenization + charge) set `BillingCustomerId`
2. OpenPay timestamps normalized to UTC
3. Orphaned PaymentMethod deactivated on charge failure
4. TSH state machine entries (callback + remote confirmation)
5. TSH.CreatedBy uses `BillingCustomerId`
6. 3DS ON path sets `IsThreeDSecureEnabled = true` and `ThreeDSecureStage = completed`
7. 3DS OFF path sets `IsThreeDSecureEnabled = false` and `ThreeDSecureStage = not_applicable`

Current examples live in `ProcessPaymentHandlerTests` and `ConfirmPaymentStatusHandlerTests`.

### 11.5 Per-tenant 3DS scenario matrix

`PaymentProvider.Use3DSecure` is a per-tenant `bool` column — any combination is valid at runtime:

| Tenant | Tier | Use3DSecure | Supported | Mechanism |
|---|---|---|---|---|
| TenantA | SharedPool | true | ✅ | Default seed value |
| TenantA | SharedPool | false | ✅ | DB UPDATE at runtime |
| TenantB | SharedPool | true | ✅ | Default seed value |
| TenantB | SharedPool | false | ✅ | DB UPDATE at runtime |
| TenantC | Dedicated | true | ✅ | Default seed value |
| TenantC | Dedicated | false | ✅ | DB UPDATE at runtime |
| TenantD+ | Either | true/false | ✅ | Set in seed migration or DB UPDATE |

Rules:

1. `Use3DSecure` is a business rule per tenant, not a global infrastructure setting.
2. The property lives on `PaymentProvider`, not `OpenPayConfig` or appsettings.
3. `DbInitializer` seeds all tenants with `Use3DSecure = true` by default.
4. Override per-tenant at runtime via DB UPDATE or by adding a seed-data migration.
5. `ProcessPaymentCommandHandler` reads the value per-tenant via `AppMasterData.GetProviderByNameForTenant()`.
   `AppMasterData` is scoped (per-request) and reads from the tenant-routed DbContext — no API restart needed for Use3DSecure changes.
6. `ConfirmPaymentStatusCommandHandler` does not consult `PaymentProvider.Use3DSecure` — it reads `IsThreeDSecureEnabled` from the `CardTransaction` row (already stamped by ProcessPayment).

Unit test coverage:

| Path | Test | Verified assertion |
|---|---|---|
| 3DS ON (default) | `HandleAsync_NewCustomer_BothCardTransactionsShouldSetBillingCustomerId` | Implicit — uses default `use3DSecure: true` |
| 3DS OFF | `HandleAsync_3DSecureOff_ShouldSetNotApplicableStageOnChargeCardTransaction` | `IsThreeDSecureEnabled = false`, `ThreeDSecureStage = not_applicable` |

## 12. Out of Scope

These topics are intentionally excluded from this standard and require separate architecture review before implementation:

1. user-to-tenant membership
2. authentication and claims-based tenant switching
3. tenant administration UI
4. remote environment data migration
5. webhook/API versioning changes unrelated to tenant and payment identifier standards

## 13.1 UI Tenant Bootstrap

The UI must bootstrap tenant context from API-owned runtime configuration.

Rules:

1. The API owns the active tenant bootstrap contract.
2. The approved endpoint is `GET /api/v1/info/runtime-configuration`.
3. That endpoint may be called without `X-Tenant-Code`.
4. No other business endpoint may bypass tenant middleware for UI convenience.
5. UI-local configuration such as `UI:DefaultTenantCode` must not be used as the runtime tenant source.
6. The runtime configuration payload may include non-sensitive bootstrap metadata only, such as `ActiveTenantCode` and `TenantHeaderName`.

## 14. Quick Reference

| Decision point | Standard |
|---|---|
| Request header | `X-Tenant-Code` |
| Missing or unknown tenant code | HTTP 400 |
| Suspended or decommissioned tenant | HTTP 403 |
| Resolved active tenant | continue |
| Headerless bootstrap endpoint | `GET /api/v1/info/runtime-configuration` |
| UI tenant source | API runtime configuration |
| Internal tenant key | `Tenant.Id` |
| External tenant key | `Tenant.ExternalId` |
| Ops/runtime tenant key | `Tenant.Code` |
| Business order id | `CustomerOrderId` |
| Attempt/provider order id | `AttemptOrderId` |
| Internal correlation id | `PaymentTraceId` |
| 3DS toggle location | `PaymentProvider.Use3DSecure` (per-tenant, not global config) |
| Baseline seed location | baseline migration `Up()` |
| Tenant stamping scope | tenant-owned base classes only |
| Tenant table filtering | no global query filter |

## 15. Card Data Handling (PCI DSS 3.2)

Binding rules for payment card data storage:

1. `CardTransaction` must never store raw PAN or CVV. CVV must not be persisted under any circumstances.
2. `CardTransaction.MaskedCardNumber` stores BIN (first 6) + masked middle + last 4, e.g. `411111******1234`.
3. `PayinLog.LastFourCardNbr` stores only the last 4 digits for audit trail.
4. No DTO, log output, or error message may contain a full card number or CVV.
5. Architecture tests must enforce these constraints to prevent regression.

## 16. File-Level References

Use these as the first reference points when applying the standard:

- `XYDataLabs.OrderProcessingSystem.SharedKernel/Multitenancy/ITenantProvider.cs`
- `XYDataLabs.OrderProcessingSystem.SharedKernel/Multitenancy/TenantMiddleware.cs`
- `XYDataLabs.OrderProcessingSystem.API/Controllers/InfoController.cs`
- `XYDataLabs.OrderProcessingSystem.Domain/Entities/Tenant.cs`
- `XYDataLabs.OrderProcessingSystem.Domain/Entities/BaseAuditableEntity.cs`
- `XYDataLabs.OrderProcessingSystem.Domain/Entities/BaseAuditableCreateEntity.cs`
- `XYDataLabs.OrderProcessingSystem.Infrastructure/DataContext/OrderProcessingSystemDbContext.cs`
- `XYDataLabs.OrderProcessingSystem.Infrastructure/SeedData/DbInitializer.cs`
- `XYDataLabs.OrderProcessingSystem.Infrastructure/Migrations/20260322112523_RebaselineMultitenantPaymentSchema.cs`
- `tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests/EfMigrationDriftTests.cs`
- `tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests/MultiTenantSchemaTests.cs`
- `tests/XYDataLabs.OrderProcessingSystem.Integration.Tests/DedicatedTenantTests.cs`

Any deviation from this file requires an ADR and explicit architecture approval.