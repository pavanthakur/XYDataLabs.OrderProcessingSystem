# Clean Architecture Patterns — Detail Reference

Progressive-disclosure reference for `cqrs-backend-implementation`. The always-on core (dependency flow, layer rules, tenant hard rules, red flags) stays in `.github/instructions/clean-architecture.instructions.md`; read this file when implementing or reviewing handlers, caching, observability or tenancy wiring.

## Data Access
- Use `IAppDbContext` (defined in Application) — never concrete `OrderProcessingSystemDbContext`.
- No Repository/Unit of Work wrapper — `IAppDbContext` is the abstraction; Infrastructure's DbContext implements it.

## CQRS (Hand-Rolled, no MediatR)
- `ICommand<TResult>` / `IQuery<TResult>` — marker interfaces.
- `ICommandHandler<TCommand, TResult>` / `IQueryHandler<TQuery, TResult>` — handlers.
- `IPipelineBehavior<TRequest, TResult>` — cross-cutting (validation, logging, caching).
- `IDispatcher` — resolves and invokes handlers from DI.
- Feature folder structure: `Application/Features/{Feature}/Commands/`, `Queries/`.

## Error Handling
- `Result<T>` for business outcomes; exceptions only for infrastructure failures and bugs.
- Controllers map `Result<T>` → `ApiResponse<T>` → HTTP status codes.
- `PaymentProviderCustomerActionException` (SharedKernel) = terminal provider decline — map to `PaymentAttemptStatus.Failed`, no retry. All other gateway exceptions → `UnknownNeedsReconciliation`.

## API Responses
- ALL endpoints return `ApiResponse<T>` with `{ Success, Data, Message, Errors }`.
- URL-segment API versioning: `/api/v{version}/[controller]`.

## Caching
- `ICacheService` interface in Application, Redis implementation in Infrastructure.
- `CachingBehavior<TRequest, TResult>` pipeline — queries opt in via `ICacheable`; commands bypass cache (and can invalidate).

## Observability
- OpenTelemetry via `AddObservability(serviceName)` in SharedKernel; custom `ActivitySource` per bounded context for business spans.
- Structured logging only: `Log.Information("{Key}", value)` — never string interpolation.

## Multi-Tenancy (Hybrid — SharedPool + Dedicated)
- Two tiers: `SharedPool` (default, shared DB with TenantId discriminator) and `Dedicated` (separate physical DB per tenant). See ADR-007.
- Tenant-owned entities inherit `BaseAuditableEntity` or `BaseAuditableCreateEntity` (provides `TenantId` + audit columns); never redeclare `TenantId`.
- `ConfigureTenantOwnership<T>()` in `OnModelCreating()` configures FK to Tenants, global query filter and `DeleteBehavior.Restrict`; every new tenant-owned entity must be registered there.
- `IAppDbContext` parity: every `DbSet<T>` on `OrderProcessingSystemDbContext` except `Tenant` must appear on `IAppDbContext` (architecture tests enforce this).
- `IgnoreQueryFilters` bypasses tenant isolation; usage is restricted to an architecture-test allow-list and needs explicit tenant-safety review.
- `HeaderTenantProvider` resolves `X-Tenant-Code` to canonical tenant context (`TenantId`, `TenantCode`, `TenantExternalId`, `ConnectionString`, `IsSharedPool`). Missing or unknown code → HTTP 400; suspended or decommissioned → HTTP 403.
- `Tenants` is a system table — excluded from query filters, `IAppDbContext` and tenant stamping.
- Non-request operations must set `TenantId` explicitly instead of relying on ambient tenant context.
- Full tenant/payment schema rules: `.github/instructions/multitenant-payment-schema.instructions.md`.

## Payment Configuration Safety
- `IsProduction = false` is the required default in all `sharedsettings.{env}.json` files. Startup logs `"TEST mode"` or `"LIVE mode"`.
- `RazorpayConfigValidator` cross-checks key prefix (`rzp_test_*` / `rzp_live_*`) against `IsProduction` at startup — mismatch fails startup immediately.
- Never put per-tenant runtime config (`Use3DSecure`, provider routing) in sharedsettings. The database is the source of truth.
