---
applyTo: "**/XYDataLabs.OrderProcessingSystem.Domain/Entities/**/*.cs,**/XYDataLabs.OrderProcessingSystem.Application/DTO/**/*.cs,**/XYDataLabs.OrderProcessingSystem.Application/Features/Payments/**/*.cs,**/XYDataLabs.OrderProcessingSystem.Infrastructure/**/*.cs,**/XYDataLabs.OrderProcessingSystem.API/Controllers/**/*.cs,**/XYDataLabs.OrderProcessingSystem.UI/**/*.cshtml,**/XYDataLabs.OrderProcessingSystem.UI/wwwroot/js/**/*.js,**/tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests/**/*.cs,**/tests/XYDataLabs.OrderProcessingSystem.Integration.Tests/**/*.cs"
---
# Multitenant Payment Schema Rules — XYDataLabs.OrderProcessingSystem

These rules are binding for all tenant, payment, DTO, migration, middleware, and related test changes.

## Authority
- Root standard: `ARCHITECTURE.md`
- If this file conflicts with older instructions or comments, follow `ARCHITECTURE.md` and the current codebase.

## Tenant model
- Use the three-key tenant pattern only:
  - `Tenant.Id` → internal FK only
  - `Tenant.ExternalId` → external API/webhook/integration key
  - `Tenant.Code` → `X-Tenant-Code`, ops tooling, logs
- `Tenant.Id` must never appear in external DTOs or UI surfaces.
- `Tenants` is a system table, not a tenant-owned table.

## Tenant resolution
- Request header is `X-Tenant-Code`, never `X-Tenant-Id`.
- Missing or unknown tenant code → HTTP 400.
- Resolved `Suspended` or `Decommissioned` tenant → HTTP 403.
- No null tenant context may flow downstream.
- `ITenantProvider` must expose `HasTenantContext`, `TenantId`, `TenantCode`, `TenantExternalId`, `ConnectionString`, and `IsSharedPool`.
- The only approved headerless bootstrap path is `GET /api/v1/info/runtime-configuration`.
- UI/browser code must read the active tenant from API runtime configuration, not UI-local configuration.

## Tenant tier model (hybrid)
- Two tiers: `SharedPool` (default) and `Dedicated`. Values in `TenantTierConstants`.
- `Tenant.TenantTier` — nvarchar(20), NOT NULL, default `SharedPool`.
- `Tenant.ConnectionString` — nvarchar(500), nullable.
  - `null` = shared pool. Non-null = dedicated DB connection string.
  - For Managed Identity connections: store the full connection string (no credentials embedded).
  - For password-based connections: store a Key Vault secret name reference, never the raw password.
- `TenantA` and `TenantB` are always `SharedPool` with `ConnectionString = null`.
- `IsSharedPool` is derived from `TenantTier == SharedPool`, NOT from `ConnectionString == null`.
- A Dedicated tenant without a provisioned ConnectionString is treated as unresolvable (fail-loud, not silent shared-pool routing).

## Tenant resolution pipeline (circular dependency rule)
- `EntityFrameworkTenantResolver` MUST use `TenantRegistryDbContext`, never `OrderProcessingSystemDbContext`.
- `TenantRegistryDbContext` always uses the shared/admin connection string from configuration.
- `TenantRegistryDbContext` has no `ITenantProvider` dependency and no query filters.
- `OrderProcessingSystemDbContext` uses the per-request connection string resolved from `ITenantProvider`.
- Query filters are always active on all DbContexts (defense-in-depth). On dedicated DBs the filter is trivially true.

## IAppDbContext boundary
- `IAppDbContext` must NOT expose `DbSet<Tenant>`. Tenant queries go through `ITenantRegistry` or `ITenantResolver`.
- Application-layer handlers must never query the `Tenants` table directly.
- `ITenantRegistry` (in Application/Abstractions) provides read-only access to active tenants for bootstrap endpoints.

## Tenant-owned entities
- Tenant-owned entities must inherit from `BaseAuditableEntity` or `BaseAuditableCreateEntity`.
- Do not redeclare `TenantId` on derived entities.
- `TenantId` is `int`, non-nullable, FK-backed.
- Tenant-owned entities must have:
  - FK to `Tenants(Id)`
  - global query filter on `TenantId`
  - explicit tenant-scoped indexes for lookup keys
- `Tenants` and any other non-tenant-owned system tables are excluded from tenant query filters and tenant stamping.

## Payment identifiers
- Use only these names:
  - `CustomerOrderId`
  - `AttemptOrderId`
  - `PaymentTraceId`
- Do not introduce new uses of these ambiguous or legacy names:
  - `OrderId` for payment attempt identity
  - `ReferenceNo`
  - `APINO1`
  - `APINO2`
- Customer-facing DTOs and UI may show `CustomerOrderId`.
- `AttemptOrderId` is provider/callback/technical only.
- `PaymentTraceId` is internal-only and must not appear in customer-facing DTOs or UI.

## EF and migrations
- Current baseline starts from `RebaselineMultitenantPaymentSchema`.
- `TenantA` and `TenantB` must be seeded in the baseline migration `Up()`.
- Every new tenant-owned table migration must include:
  - FK to `Tenants`
  - required tenant-scoped indexes
- After creating any migration, run a drift check with a second migration and confirm it is empty.
- Remove the temporary drift-check migration after verification.

## Non-request operations
- `DbInitializer`, background jobs, test fixtures, and any out-of-band creation flow must pass `TenantId` explicitly.
- Never rely on ambient middleware tenant context in non-request code paths.

## Required test coverage
- Architecture tests must cover:
  - migration drift
  - tenant-scoped index presence
  - tenant filter isolation
  - identifier surface compliance
- Middleware/integration tests must cover:
  - 400 for missing tenant code
  - 400 for unknown tenant code
  - 403 for blocked tenant status
  - per-class tenant isolation
  - no dependency on shared baseline tenant rows