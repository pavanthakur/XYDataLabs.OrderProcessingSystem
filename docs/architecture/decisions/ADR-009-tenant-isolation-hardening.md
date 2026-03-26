# ADR-009: Tenant Isolation Hardening

**Status:** Accepted

**Date:** 2026-03-23

---

## Context

A multi-tenant audit identified three enterprise-grade isolation violations:

1. **AppMasterData singleton with IgnoreQueryFilters** — `AppMasterData` was registered as a
   singleton, loaded once at startup from the shared-pool database using
   `.IgnoreQueryFilters()`. This meant ALL tenants' PaymentProviders were held in a single
   in-memory cache, including data that should exist only in dedicated databases.

2. **Cross-database PaymentProvider seeding** — `DbInitializer.SeedDedicatedTenants()` seeded
   TenantC's PaymentProvider into the shared-pool database (`OrderProcessingSystem_Local`) in
   addition to the dedicated database. This was required by the singleton design (violation #1)
   but exposed TenantC's configuration to the shared pool.

3. **Connection strings stored in the Tenants table** — `Tenant.ConnectionString` (nvarchar 500)
   stored dedicated database connection strings as application data. Connection strings are
   secrets that should reside in configuration (Key Vault / appsettings), not in a queryable
   database column.

An additional operational issue: changing `PaymentProvider.Use3DSecure` in the database required
an API restart because the singleton cached stale data.

---

## Decision

### Fix 1: AppMasterData — Singleton → Scoped

- Changed DI registration from `AddSingleton<AppMasterData>` to `AddScoped<AppMasterData>()`.
- Removed `.IgnoreQueryFilters()` from `InitializeData()`. The scoped DbContext applies the
  tenant query filter, returning only the current tenant's PaymentProviders.
- Removed the startup warmup (`GetRequiredService<AppMasterData>()` in `Program.cs`).
- Emptied the `IgnoreQueryFilters` allow-list in `ArchitectureTests` (no approved usages remain).

### Fix 2: Remove cross-database seeding

- Removed `SeedOpenpayProviders(mainContext, new[] { seedTenant })` from `SeedDedicatedTenants()`.
  Dedicated tenants' PaymentProviders are seeded only in their own database.

### Fix 3: Connection strings from configuration only

- Removed `ConnectionString` property from `Tenant` entity.
- `EntityFrameworkTenantResolver` now injects `IConfiguration` and reads dedicated connection
  strings from `DedicatedTenantConnectionStrings:{TenantCode}`.
- Removed `ApplyDedicatedConnectionStrings()` from `DbInitializer` (no longer stamps config → DB).
- `SeedDedicatedTenants()` reads connection strings from `IConfiguration` instead of from
  `Tenant.ConnectionString`.
- EF migration drops the `ConnectionString` column from the `Tenants` table.

---

## Rationale

| Criterion | Old Design | New Design |
|-----------|-----------|------------|
| Tenant isolation | IgnoreQueryFilters bypassed filters; cross-DB seeding leaked data | Scoped per-tenant context; no cross-DB seeding |
| Secret management | Connection strings in DB column (queryable, dumpable) | Connection strings in Key Vault / appsettings only |
| Operational agility | Use3DSecure changes required API restart | Changes take effect on next request (scoped) |
| IgnoreQueryFilters surface | 1 approved usage (AppMasterData.cs) | 0 approved usages — allow-list empty |
| Performance | 1 DB query at startup (singleton) | 1 small query per payment request (scoped) |

The per-request query cost is negligible (PaymentProviders table has 1–3 rows per tenant, indexed
by TenantId) and is far outweighed by the isolation and operational benefits.

---

## Consequences

### Positive

- Zero `IgnoreQueryFilters` usages in the codebase — strongest tenant isolation posture.
- No cross-contaminated PaymentProvider rows in the shared-pool database.
- Connection strings are never stored in application data tables.
- `Use3DSecure` toggle is immediate — no API restart required.
- `RefreshData()` on `AppMasterData` is now a no-op concern (scoped = always fresh).

### Negative

- One additional `PaymentProviders` query per payment request (negligible cost).
- Existing databases need a cleanup migration (drop `ConnectionString` column) and manual
  `DELETE FROM dbo.PaymentProviders WHERE TenantId = <dedicated_tenant_id>` against the
  shared-pool database to remove cross-contaminated rows.

### Neutral

- Integration tests use a `MutableConfigSource` in `IntegrationTestWebAppFactory` to register
  dedicated connection strings dynamically (mirrors production's IConfiguration pattern).

---

## Related

- ADR-008: Architecture Test Guardrails (IgnoreQueryFilters allow-list — now empty)
- `multitenant-payment-schema.instructions.md` — updated IgnoreQueryFilters exemption rule
- `ARCHITECTURE.md` — updated rule 5 (AppMasterData scoped lifetime)
- `payment-db-verification.md` — removed API restart warnings
