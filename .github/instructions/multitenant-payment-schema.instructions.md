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
- Dedicated tenant connection strings are stored in configuration (`DedicatedTenantConnectionStrings:{Code}` in appsettings / Key Vault), never in the database.
  - Missing config entry = unresolvable (fail-loud, not silent shared-pool routing).
  - For Managed Identity connections: use the full connection string (no credentials embedded).
  - For password-based connections: use a Key Vault secret reference, never the raw password.
- `TenantA` and `TenantB` are always `SharedPool`.
- `TenantC` is `Dedicated` with connection string provisioned per environment via config/Key Vault.
- `IsSharedPool` is derived from `TenantTier == SharedPool`, NOT from connection string presence.
- A Dedicated tenant without a provisioned connection string config entry is treated as unresolvable (fail-loud).

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

## Card data handling (PCI DSS 3.2)
- `CardTransaction` must never store raw PAN or CVV.
- `CreditCardCvv2` was removed — CVV must not be persisted under any circumstances.
- `MaskedCardNumber` stores BIN (first 6) + masked middle + last 4, e.g. `411111******1234`.
- `PayinLog.LastFourCardNbr` stores only the last 4 digits for audit trail.
- No DTO, log output, or error message may contain a full card number or CVV.
- Architecture tests enforce these constraints — see `CardTransaction_Should_Not_Store_Raw_Card_Data`.

## Per-tenant payment flags
- `PaymentProvider.Use3DSecure` controls whether 3D Secure is enabled per tenant. It is a `bool` column (default `true`) on the `PaymentProvider` entity.
- This is a business rule per tenant, not an infrastructure/global setting. It must NOT be in `OpenPayConfig` or appsettings JSON.
- `ProcessPaymentCommandHandler` reads `Use3DSecure` from the tenant-specific `PaymentProvider` row via `AppMasterData.GetProviderByNameForTenant()`.
- All tenants seed with `Use3DSecure = true` by default (from the `StartupSeedTenant` record default). Override per-tenant at runtime via a DB UPDATE or by adding a seed-data migration.
- Future per-tenant payment flags (e.g. per-tenant MerchantId) should follow the same pattern: column on `PaymentProvider`, not appsettings.

## ConfigureTenantOwnership pattern
- Every new tenant-owned entity MUST be registered in `ConfigureTenantOwnership<T>()` in `OnModelCreating()`.
- This single call configures: FK to `Tenants(Id)`, global query filter on `TenantId`, and `DeleteBehavior.Restrict`.
- Do NOT manually configure these three concerns individually — always use `ConfigureTenantOwnership<T>()`.
- After adding the call, also add the corresponding `DbSet<T>` to both `OrderProcessingSystemDbContext` and `IAppDbContext`.

## IAppDbContext parity rule
- `IAppDbContext` must expose every `DbSet<T>` from `OrderProcessingSystemDbContext` **except** `DbSet<Tenant>`.
- `Tenant` is a system entity — tenant queries go through `ITenantRegistry` or `ITenantResolver`, never through `IAppDbContext`.
- Architecture test `IAppDbContext_DbSets_Must_Match_OrderProcessingSystemDbContext_Minus_Tenant` enforces this at CI.

## IgnoreQueryFilters exemption rule
- `.IgnoreQueryFilters()` bypasses tenant isolation and is restricted to an architecture-test allow-list.
- Current approved usages: **none** — the allow-list is empty (ADR-009).
- `AppMasterData` was removed from the allow-list: it now uses scoped lifetime and respects the tenant query filter.
- Any new usage requires: (1) a code-review justification documenting why cross-tenant access is safe, and (2) adding the filename to the allow-list in `ArchitectureTests.IgnoreQueryFilters_Usage_Must_Be_In_Allow_List_Only`.

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
- For dedicated-DB seeding, use `NullTenantProvider` (null-object `ITenantProvider` with `HasTenantContext = false`). This causes the EF query filter to short-circuit to `true` (all rows visible), which is correct when physical DB isolation replaces query-filter isolation.
- `DbInitializer.SeedDedicatedTenants()` reads `DedicatedTenantConnectionStrings` from `IConfiguration` to seed dedicated tenant databases. Connection strings are never stored in the `Tenants` table.

## Required test coverage

### Architecture tests (`MultiTenantSchemaTests`)
- Migration drift detection (`EfMigrationDriftTests`)
- Tenant-scoped composite index presence on payment entities
- Tenant global query filter presence on tenant-owned entities; absence on Tenant entity
- Customer-facing DTO identifier surface compliance (no internal IDs exposed)
- `TenantTierConstants` defines `SharedPool` and `Dedicated` values
- `Tenant.TenantTier` defaults to `SharedPool`
- `TenantRegistryDbContext` has no query filter on Tenant

### Middleware / integration tests (`TenantMiddlewareTests`)
- 400 for missing tenant header
- 400 for unknown tenant code
- 403 for Suspended / Decommissioned tenant status
- Runtime configuration endpoint returns DB tenants without auth

### SharedPool tenant isolation tests (`TenantIsolationTests`)
- Per-entity query-filter isolation: tenants in the same DB see only their own data
- No dependency on shared baseline tenant rows (tests create their own tenants)

### Dedicated tenant tests (`DedicatedTenantTests`)

**Middleware / status scenarios (single-DB factory):**
- Dedicated + unprovisioned (null CS) + Active → 400 (fail-loud, not silent shared-pool fallback)
- Dedicated + unprovisioned (null CS) + Suspended → 400 (unresolvable takes priority over status)
- Dedicated + provisioned + Suspended → 403
- Dedicated + provisioned + Decommissioned → 403
- Dedicated + provisioned + Active → 200 (routed to dedicated DB)
- SharedPool tenant coexists with Dedicated tenants without interference

**Physical DB isolation scenarios (routing-aware factory):**
- Data written to dedicated tenant is physically present in dedicated DB (direct SQL verification)
- Dedicated tenant data NOT visible via direct query on shared-pool DB
- SharedPool tenant data NOT visible via direct query on dedicated DB

### New feature guardrail
When adding a new tenant-owned entity or feature:
1. SharedPool path: verify query filter isolation via `TenantIsolationTests` pattern
2. Dedicated path: verify physical DB isolation via `DedicatedTenantTests` pattern — write through routing factory, verify via direct SQL on both databases
3. Architecture guard: ensure FK to Tenants, composite index, and query filter are tested
4. Never silently route an unprovisioned Dedicated tenant to SharedPool — fail loud