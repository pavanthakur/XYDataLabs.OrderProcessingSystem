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

## Patterns & Conventions

### Data Access
- Use `IAppDbContext` (defined in Application) — never concrete `OrderProcessingSystemDbContext`
- No Repository/Unit of Work wrapper — `IAppDbContext` is the abstraction
- Infrastructure's DbContext implements `IAppDbContext`

### CQRS (Hand-Rolled, no MediatR)
- `ICommand<TResult>` / `IQuery<TResult>` — marker interfaces
- `ICommandHandler<TCommand, TResult>` / `IQueryHandler<TQuery, TResult>` — handlers
- `IPipelineBehavior<TRequest, TResult>` — cross-cutting (validation, logging, caching)
- `IDispatcher` — resolves and invokes handlers from DI
- Feature folder structure: `Application/Features/{Feature}/Commands/`, `Queries/`

### Error Handling
- Use `Result<T>` for business outcomes — not exceptions
- Exceptions are for truly exceptional situations (infrastructure failures, bugs)
- Controllers map `Result<T>` → `ApiResponse<T>` → HTTP status codes

### API Responses
- ALL endpoints return `ApiResponse<T>` with `{ Success, Data, Message, Errors }`
- URL-segment API versioning: `/api/v{version}/[controller]`

### Caching
- `ICacheService` interface in Application, Redis implementation in Infrastructure
- `CachingBehavior<TRequest, TResult>` CQRS pipeline — queries opt in via `ICacheable`
- Commands always bypass cache (and can invalidate)

### Observability
- OpenTelemetry for distributed tracing via `AddObservability(serviceName)` in SharedKernel
- Custom `ActivitySource` per bounded context for business operation spans
- Structured logging only: `Log.Information("{Key}", value)` — never string interpolation

### Multi-Tenancy
- Shared DB + `Tenants` master table + EF Global Query Filters via `ITenantProvider`
- Tenant-owned entities use inherited `TenantId` (`int`) on `BaseAuditableEntity` / `BaseAuditableCreateEntity`, auto-stamped on `SaveChangesAsync`
- `HeaderTenantProvider` resolves `X-Tenant-Code` to canonical tenant context (`TenantId`, `TenantCode`, `TenantExternalId`)
- Missing or unknown tenant code returns HTTP 400; suspended or decommissioned tenant returns HTTP 403
- `Tenants` is a system table and must be excluded from global tenant query filters
- Non-request operations must set `TenantId` explicitly instead of relying on ambient tenant context

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
