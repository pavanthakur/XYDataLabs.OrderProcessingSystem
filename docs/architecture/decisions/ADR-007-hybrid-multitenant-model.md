# ADR-007: Hybrid Multitenant Model (SharedPool + Dedicated Database)

## Status
Accepted

## Context
The application started with a pure Model A (shared database, TenantId discriminator) multitenancy design. All tenants share a single SQL database with row-level isolation via EF Core global query filters.

As the product scales, enterprise clients will require dedicated databases for:
- Regulatory/compliance isolation (data residency, audit)
- Independent scaling and performance guarantees
- Custom backup and retention policies

The architecture must support both small tenants on the shared database and enterprise tenants on dedicated databases, without conditional model logic or separate deployment artifacts.

Key constraint: EF Core calls `OnModelCreating` once per `DbContext` type and caches the resulting `IModel`. Any conditional FK or filter logic in `OnModelCreating` would use the first request's values for all subsequent requests.

## Decision
Adopt a hybrid Model A+C multitenancy architecture:

1. **Tenant entity** gains `TenantTier` (SharedPool/Dedicated) and `ConnectionString` (nullable) columns.
2. **TenantRegistryDbContext** — new lightweight DbContext for tenant resolution. Uses the shared/admin connection string. Has no `ITenantProvider` dependency and no query filters. Breaks the circular dependency where the business DbContext needs tenant context but tenant resolution needs the DB.
3. **OrderProcessingSystemDbContext** — business DbContext. Connection string resolved per-request from `ITenantProvider`. Dedicated tenants route to their own database; shared pool tenants route to the default connection.
4. **IsSharedPool derived from TenantTier** — never from `ConnectionString` nullability. A Dedicated tenant without a provisioned ConnectionString is treated as unresolvable (fail-loud) to prevent silent data isolation breach.
5. **Query filters always active** on all databases (defense-in-depth). On dedicated DBs the filter is trivially true — zero runtime cost.
6. **Single migration chain** — both shared and dedicated databases use the same schema and migrations. Dedicated DBs get their own `Tenants` table with their single tenant row.
7. **IAppDbContext no longer exposes `DbSet<Tenant>`** — application handlers must not query the tenant registry directly. Tenant data flows through `ITenantResolver` and `ITenantProvider`.

## Rationale
| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| Hybrid A+C (SharedPool + Dedicated) | Supports both SMB and enterprise tiers. Single codebase and migration chain. Defense-in-depth query filters. No conditional OnModelCreating. | Slightly more complex DI registration. Dedicated DBs carry unused shared-pool infrastructure tables. | ✅ Selected |
| Pure Model A (shared DB only) | Simplest. One connection string. | Cannot meet enterprise isolation requirements. Single point of failure for all tenants. | ❌ Insufficient for scale |
| Pure Model C (dedicated DB per tenant) | Maximum isolation. | Operationally expensive for small tenants. Connection management overhead at scale. | ❌ Overkill for SMBs |
| Conditional OnModelCreating | Could skip FK/filters per-request. | EF caches model per DbContext type — conditional logic silently ignored after first request. Would need IModelCacheKeyFactory which adds complexity for no gain. | ❌ Technically invalid |

## Consequences

**Positive:**
- Enterprise tenants get full database isolation with no code changes to business logic
- Existing SharedPool tenants (TenantA, TenantB) continue working with zero impact
- Defense-in-depth: query filters protect even dedicated databases
- Circular dependency in tenant resolution cleanly broken via TenantRegistryDbContext
- Silent data breach prevented: Dedicated tenant without ConnectionString fails loudly

**Negative / Trade-offs:**
- Two DbContext registrations in DI — slightly more complexity in StartupHelper
- Dedicated databases carry all tables including those only meaningful in shared pool context
- Connection string management for dedicated tenants needs operational tooling (future: provisioning service)

**Future obligations:**
- Build dedicated tenant provisioning service: create DB → run MigrateAsync() → seed single Tenant row → update registry
- Implement connection string rotation strategy for dedicated tenants
- Add health checks per dedicated database connection

## Related
- ADR-001: Clean Architecture with DDD layers
- ADR-004: EF Core 8 + Azure SQL
- ADR-006: Passwordless SQL via DefaultAzureCredential + Managed Identity
- `ARCHITECTURE.md` — Tenant Model section (updated with TenantTier + ConnectionString)
- `.github/instructions/multitenant-payment-schema.instructions.md` — Binding rules for tenant tier model
