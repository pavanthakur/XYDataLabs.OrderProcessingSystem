# ADR-008: Architecture Test Guardrails for Multitenancy Compliance

## Status
Accepted

## Context
The codebase uses a hybrid multitenancy model (ADR-007) with SharedPool and Dedicated tiers.
Every tenant-owned entity requires: an audit base class, a global query filter, an FK to Tenants,
registration in `ConfigureTenantOwnership<T>()`, and a matching `DbSet<T>` on `IAppDbContext`.

As the entity count grows, it becomes increasingly likely that a developer adds a new entity but
forgets one of these configuration steps. Manual code review catches some gaps, but is inconsistent
and scales poorly. The `IgnoreQueryFilters` escape hatch is another vector — a single unreviewed
call can silently break tenant isolation for every customer.

We needed an automated, CI-enforced guardrail strategy that:
1. Catches missing tenant configuration **before merge**, not after a production data leak.
2. Scales automatically as new entities are added (no per-entity test maintenance).
3. Guards the `IgnoreQueryFilters` escape hatch with an auditable allow-list.
4. Enforces API surface rules (no tenant params in controllers).
5. Ensures CQRS handler consistency (`Result<T>` pattern).

## Decision
Implement 10 dynamic architecture tests across two test classes, enforced at CI via `dotnet test`.

### Test inventory

| # | Test | Class | What it guards |
|---|------|-------|---------------|
| 1.1 | `All_TenantOwned_Entities_Should_Inherit_AuditBase` | MultiTenantSchemaTests | Every IAppDbContext entity inherits BaseAuditableEntity or BaseAuditableCreateEntity |
| 1.2 | `All_TenantOwned_Entities_Should_Have_Global_Query_Filter` | MultiTenantSchemaTests | ConfigureTenantOwnership was called for every entity |
| 1.3 | `All_TenantOwned_Entities_Should_Have_FK_To_Tenants` | MultiTenantSchemaTests | FK from TenantId to Tenants(Id) exists |
| 1.4 | `IAppDbContext_DbSets_Must_Match_OrderProcessingSystemDbContext_Minus_Tenant` | MultiTenantSchemaTests | IAppDbContext stays in sync with concrete DbContext |
| 1.5 | `IAppDbContext_Should_Not_Expose_Tenant_DbSet` | MultiTenantSchemaTests | Tenant system entity excluded from application abstraction |
| 1.6 | `IgnoreQueryFilters_Usage_Must_Be_In_Allow_List_Only` | ArchitectureTests | File-system scan with explicit allow-list (currently empty — see ADR-009) |
| 1.7 | `All_CQRS_Handlers_Must_Return_Result_T` | ArchitectureTests | Every ICommandHandler/IQueryHandler returns Result<T> |
| FC3 | `Controllers_Should_Not_Accept_TenantId_Or_TenantCode_Parameters` | ArchitectureTests | No TenantId/TenantCode/TenantExternalId in action params or request DTOs |
| FC4 | `ITenantProvider_Must_Expose_Hybrid_Routing_Properties` | MultiTenantSchemaTests | ConnectionString + IsSharedPool cannot be removed from ITenantProvider |
| — | `GetAllTenantOwnedEntityTypes()` | MultiTenantSchemaTests | Shared helper: reflects IAppDbContext DbSet<T> properties |

### How it scales
Tests 1.1–1.5 use `GetAllTenantOwnedEntityTypes()` which reflects all `DbSet<T>` properties from
`IAppDbContext`. When a developer adds a new entity, they add the `DbSet<T>` to `IAppDbContext` (enforced
by test 1.4), and tests 1.1–1.3 automatically validate the new entity's tenant configuration. Zero
per-entity test maintenance.

## Rationale
| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| Dynamic reflection tests (chosen) | Zero maintenance per entity, catches gaps at CI, auditable allow-list for IgnoreQueryFilters | File-system scan for IgnoreQueryFilters is slightly fragile | ✅ Selected |
| Per-entity hardcoded tests | Simple, explicit | O(n) test maintenance, easily forgotten for new entities | ❌ Rejected |
| Roslyn analyzer | Compile-time feedback, IDE integration | High implementation cost, harder to maintain, overkill for team of 1–4 | ❌ Deferred (FC2) |
| Code review only | No tooling overhead | Inconsistent, doesn't scale, misses gaps under time pressure | ❌ Rejected |

## Consequences

**Positive:**
- Any new tenant-owned entity that skips ConfigureTenantOwnership, audit base, or IAppDbContext sync will fail CI immediately.
- IgnoreQueryFilters cannot be added without updating the allow-list — creates an auditable approval trail.
- Controller tenant parameter violations are caught before merge.
- CQRS handler consistency is enforced (Result<T> everywhere).

**Negative / Trade-offs:**
- IgnoreQueryFilters test uses file-system scanning — could have false positives if a file contains the string in a comment. Acceptable trade-off: better to flag and review than to miss a real bypass.
- Tests depend on reflection over IAppDbContext — if the interface is restructured, tests need updating.

**Future obligations:**
- When adding `IgnoreQueryFilters` to a new file, add the filename to the allow-list in `ArchitectureTests.IgnoreQueryFilters_Usage_Must_Be_In_Allow_List_Only`.
- FC1 (SaveChanges TenantId=0 guard): Add after integration test suite is stable — prevents saving entities with unset TenantId.
- FC2 (Roslyn analyzer): Consider when team grows beyond 4 — provides compile-time feedback in IDE.
- FC6 (Cross-tenant audit trail): Implement when compliance requirements demand it.

**Validation protocol for new guardrail tests:**
After each new architecture test is added, verify it actually catches violations:
1. Temporarily add a non-compliant entity (e.g., a class without base class inheritance, or add `IgnoreQueryFilters` to an unlisted file)
2. Run the test suite and confirm the new test fails with a clear, actionable message
3. Revert the non-compliant entity
4. Confirm the test passes again

This prevents "always green" tests that pass even when the violation exists.

## Related
- ADR-007: Hybrid Multi-Tenant Model (SharedPool + Dedicated)
- `tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests/MultiTenantSchemaTests.cs`
- `tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests/ArchitectureTests.cs`
- `.github/instructions/clean-architecture.instructions.md` — Multi-Tenancy section
- `.github/instructions/multitenant-payment-schema.instructions.md` — ConfigureTenantOwnership + IgnoreQueryFilters sections
