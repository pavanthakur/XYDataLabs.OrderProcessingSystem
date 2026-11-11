# Tenant And Payment Test Coverage

Progressive-disclosure reference for `cqrs-backend-implementation`. Read when adding or reviewing tenant, payment or migration tests. Binding rules stay in `.github/instructions/multitenant-payment-schema.instructions.md`.

- Architecture (`MultiTenantSchemaTests`, `EfMigrationDriftTests`): migration drift, tenant composite indexes, query filter on tenant-owned entities (not `Tenant`), no internal IDs in customer DTOs, tier constants/default, `TenantRegistryDbContext` has no filter.
- Middleware (`TenantMiddlewareTests`): 400 missing/unknown tenant code; 403 Suspended/Decommissioned; runtime-configuration endpoint works without auth.
- SharedPool isolation (`TenantIsolationTests`): per-entity filter isolation; tests create their own tenants, no reliance on baseline rows.
- Dedicated (`DedicatedTenantTests`): unprovisioned → 400 even if Suspended (unresolvable wins); provisioned Suspended/Decommissioned → 403; provisioned Active → 200 routed to the dedicated DB; coexistence with SharedPool; physical isolation verified by direct SQL on both databases.
