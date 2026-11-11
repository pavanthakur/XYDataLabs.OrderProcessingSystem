---
applyTo: "**/*.cs,**/*.csproj"
---
# Clean Architecture Rules — XYDataLabs.OrderProcessingSystem

These rules are MANDATORY for all code changes. Violations must be fixed before committing.

## Dependency Flow (strict)

```text
Domain (zero dependencies)
  ↑
Application (→ Domain, → SharedKernel only)
  ↑
Infrastructure (→ Application, → Domain, → SharedKernel)
  ↑
API (→ Application, → Infrastructure, → SharedKernel) ← composition root
```

## Layer Rules

### Domain Layer
- Contains: Entities, Value Objects, Domain Events, Enums
- ZERO project references — no dependencies on any other project
- ZERO NuGet packages except `Microsoft.Extensions.*` abstractions
- Never import EF Core, Azure SDK, or any infrastructure namespace
- Pure business rules only — no framework or database concerns

### Application Layer
- Contains: Use Cases (Commands, Queries, Handlers), DTOs, Validators, Mapper Profiles, Abstractions
- References: Domain, SharedKernel ONLY
- **NEVER reference Infrastructure** — no `<ProjectReference>` to Infrastructure.csproj
- **NEVER import Infrastructure namespaces** — no `using ...Infrastructure.*`
- **NEVER use concrete DbContext** — use `IAppDbContext` interface only
- No DI registration code — DI wiring belongs in the API composition root
- CQRS pattern: Commands for writes, Queries for reads, Handlers for orchestration
- All handlers return `Result<T>` for business outcomes (not exceptions)

### Infrastructure Layer
- Contains: DbContext, Migrations, Repository implementations, External service clients, Caching
- References: Application, Domain, SharedKernel
- Implements interfaces defined in Application (e.g., `IAppDbContext`)
- ALL EF Core, Azure SDK, and database concerns live here ONLY

### Presentation Layer (API)
- Contains: Controllers, Middleware, Filters, Program.cs (composition root)
- References: Application, Infrastructure, SharedKernel
- **IS the composition root** — ALL DI registrations happen here (Program.cs or DependencyInjection.cs)
- Controllers are thin — delegate to `IDispatcher` (CQRS) or service interfaces only
- No business logic in controllers
- All endpoints return `ApiResponse<T>` standard envelope

### SharedKernel (cross-cutting)
- Contains: Result<T>, Error, ApiResponse<T>, Constants, configuration helpers, observability extensions
- Referenced by all layers — keep it lightweight
- No business logic — only shared primitives and cross-cutting utilities

## Patterns & Conventions (core)

- Data access: `IAppDbContext` only (no concrete DbContext, no Repository/UoW wrapper).
- CQRS is hand-rolled (no MediatR): `ICommand`/`IQuery`, handlers, `IDispatcher`; features live in `Application/Features/{Feature}/Commands|Queries/`.
- `Result<T>` for business outcomes; controllers map it to the `ApiResponse<T>` envelope. `PaymentProviderCustomerActionException` = terminal decline (`Failed`, no retry); all other gateway exceptions → `UnknownNeedsReconciliation`.
- Structured logging only (`Log.Information("{Key}", value)`), never string interpolation.

### Multi-Tenancy (non-negotiable)
- Tiers `SharedPool` and `Dedicated` (ADR-007). Tenant-owned entities inherit `BaseAuditableEntity`/`BaseAuditableCreateEntity`; never redeclare `TenantId`.
- Register every new tenant-owned entity in `ConfigureTenantOwnership<T>()` and expose its `DbSet<T>` on `IAppDbContext` (except `Tenant`).
- `IgnoreQueryFilters` is restricted to the architecture-test allow-list.
- Missing/unknown tenant code → HTTP 400; suspended/decommissioned → 403. `Tenants` is a system table.
- **Controllers must never accept TenantId, TenantCode or TenantExternalId as parameters or in request DTOs.** Tenant context comes from middleware only.
- Non-request operations set `TenantId` explicitly.

### Payment Configuration Safety
- `IsProduction = false` by default; Razorpay key prefix is cross-checked at startup. Per-tenant runtime config (`Use3DSecure`, provider routing) lives in the database, never in sharedsettings.

Detail (caching, observability, pipeline behaviors, full tenancy wiring): `.github/skills/cqrs-backend-implementation/clean-architecture-patterns.md`.

## Red Flags — Reject These in Code Review

- `using XYDataLabs.OrderProcessingSystem.Infrastructure` in Application layer
- `OrderProcessingSystemDbContext` used directly outside Infrastructure
- `<ProjectReference>` from Application to Infrastructure in any .csproj
- DI registrations (`services.Add*`) in Application project
- Business logic in Controllers
- Raw data returned without `ApiResponse<T>` envelope
- Exception-based flow control for expected business outcomes
- `client-secret:` in any workflow YAML
- String-interpolated log messages instead of structured logging
