# Architecture Evolution: Monolith to Enterprise Microservices

**Last Updated:** March 22, 2026  
**Current Status:** Phases 1-6 Complete ✅ | Phase 7 Next 📅 | Phases 8-14 Planned 📅

---

## 📊 Architecture Evolution Overview

This document tracks the architectural evolution of the XYDataLabs Order Processing System across
**14 phases** — from a monolithic application deployed on Azure App Service to a production-grade,
event-driven microservices platform with YARP gateway, Azure Container Apps, .NET Aspire
orchestration, Azure Service Bus messaging, multi-tenancy, and CQRS read/write separation
with MongoDB.

---

## Baseline: Monolith on Azure App Service ✅ DEPLOYED

### Timeline
- **Duration:** Weeks 1-4 (Days 1-31)
- **Completed:** January 26, 2026
- **Learning Focus:** Azure fundamentals, deployment, CI/CD, Infrastructure as Code

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    AZURE CLOUD                               │
│                                                              │
│  ┌──────────────────────┐         ┌──────────────────────┐  │
│  │   API App Service    │         │   UI App Service     │  │
│  │  (Monolith)          │         │   (MVC Web App)      │  │
│  │                      │         │                      │  │
│  │  • Orders            │◄────────┤  • Customer Views    │  │
│  │  • Customers         │         │  • Order Views       │  │
│  │  • Payments          │         │  • Payment UI        │  │
│  │  • OpenPay Adapter   │         │                      │  │
│  └──────────┬───────────┘         └──────────────────────┘  │
│             │                                                │
│             │                                                │
│  ┌──────────▼───────────┐         ┌──────────────────────┐  │
│  │  Azure SQL Database  │         │  Application         │  │
│  │  OrderProcessingDB   │         │  Insights            │  │
│  └──────────────────────┘         └──────────────────────┘  │
│                                                              │
│  ┌──────────────────────┐         ┌──────────────────────┐  │
│  │   Key Vault          │         │  GitHub Actions      │  │
│  │   (kv-orderproc)     │         │  CI/CD + OIDC        │  │
│  └──────────────────────┘         └──────────────────────┘  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Solution Structure (7 Projects)

```
XYDataLabs.OrderProcessingSystem.sln
├── XYDataLabs.OrderProcessingSystem.API          (Composition Root)
│   ├── Controllers/                              (Thin — IDispatcher only)
│   ├── Extensions/ResultExtensions.cs            (Result<T> → ActionResult)
│   ├── Middleware/
│   └── Program.cs
├── XYDataLabs.OrderProcessingSystem.Application  (Use Cases — CQRS)
│   ├── Abstractions/IAppDbContext.cs
│   ├── CQRS/                                     (Dispatcher, Behaviors)
│   ├── Features/Customers/                       (Commands + Queries)
│   ├── Features/Orders/                           (Commands + Queries)
│   ├── Features/Payments/                         (Commands)
│   ├── DTO/
│   └── Validators/
├── XYDataLabs.OrderProcessingSystem.Domain       (Entities — zero deps)
├── XYDataLabs.OrderProcessingSystem.Infrastructure (EF Core, DbContext)
├── XYDataLabs.OrderProcessingSystem.SharedKernel  (Result<T>, ApiResponse<T>)
├── XYDataLabs.OrderProcessingSystem.UI           (MVC Web App)
└── XYDataLabs.OpenPayAdapter                     (Payment Integration)
```

### Characteristics

✅ **Advantages:**
- Simple deployment (2 App Services)
- Easy debugging (single process)
- Straightforward development
- Direct database access
- No network latency between components
- Azure-native monitoring with App Insights

⚠️ **Limitations:**
- Tight coupling between business domains
- Scaling issues (must scale entire app)
- Deployment risk (one change affects all)
- Technology stack locked (all .NET)
- Difficult to parallelize development
- Database contention possible

### Production Status

| Component | Resource Name | Status |
|-----------|---------------|--------|
| **API** | `pavanthakur-orderprocessing-api-xyapp-dev` | ✅ Running |
| **UI** | `pavanthakur-orderprocessing-ui-xyapp-dev` | ✅ Running |
| **Database** | `orderprocessing-sql-dev / OrderProcessingSystem_Dev` | ✅ Active |
| **Monitoring** | `ai-orderprocessing-dev` | ✅ Active |
| **Secrets** | `kv-orderprocessing-dev` | ⚠️ Created (needs access config) |
| **CI/CD** | GitHub Actions (OIDC) | ✅ Working |

### URLs

- **API Swagger:** https://pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net/swagger
- **UI:** https://pavanthakur-orderprocessing-ui-xyapp-dev.azurewebsites.net

---

## Architecture Roadmap (14 Phases)

| # | Phase | Focus | Status |
|---|-------|-------|--------|
| **1** | Structural Foundation | SharedKernel, `Result<T>`, `IAppDbContext`, layer decoupling | ✅ **COMPLETE** |
| **2** | Hand-Rolled CQRS | Dispatcher, pipeline behaviors, 12 handlers, controller refactoring | ✅ **COMPLETE** |
| **3** | Observability (OpenTelemetry) | Auto-instrumentation, App Insights + OTLP, custom ActivitySource, correlation | ✅ **COMPLETE** |
| **4** | Multi-Tenancy Skeleton | `ITenantProvider`, EF global query filters, `X-Tenant-Id` header | ✅ **COMPLETE** |
| **5** | Test Project Restructure | Domain.Tests, Application.Tests, API.Tests, Integration.Tests (Testcontainers) | ✅ **COMPLETE** |
| **6** | Polish & Hardening | CachingBehavior, Redis, API versioning `/api/v1/`, health checks, CancellationToken, TimeProvider | ✅ **COMPLETE** |
| **7** | Tenant Enforcement & Ops | TenantValidationBehavior, AuditLog, security headers, liveness/readiness checks | 📅 **NEXT** |
| **8** | Event-Driven Foundation | Domain events, integration events, Outbox pattern, background publisher | 📅 Planned |
| **8.5** | Multi-Provider Payment Architecture | Stripe migration, per-tenant provider selection, `HttpClient`-based resilience, idempotency keys | 📅 Planned |
| **9** | YARP Microservices (Local) | Gateway, Orders/Inventory/Notifications APIs, Docker Compose, event-based communication | 📅 Planned |
| **10** | Azure Container Apps | ACA deployment, ACR, Service Bus, Entra ID + JWT, private networking | 📅 Planned |
| **11** | Data Ownership & Autonomy | Database per service, remove shared DbContext, eventual consistency | 📅 Planned |
| **12** | Platform Engineering & DevOps | Azure App Configuration, Polly resilience, per-service CI/CD, observability dashboards | 📅 Planned |
| **13** | Aspire & Final Maturity | .NET Aspire orchestration, service discovery, blue-green/canary deployments | 📅 Planned |
| **14** | CQRS Read Model (MongoDB) | Separate read/write models, projection handlers, Hangfire, tenant-scoped documents | 📅 Planned |

---

## Phase 1 — Structural Foundation ✅
- Renamed `Utilities` project → `SharedKernel` (project, .csproj refs, namespaces, .sln)
- Added `Result<T>` + `Error` types in `SharedKernel/Results/`
- Added `ApiResponse<T>` standard envelope
- Added `IAppDbContext` interface in `Application/Abstractions/`
- `OrderProcessingSystemDbContext` implements `IAppDbContext`
- Changed all services: concrete DbContext → `IAppDbContext`
- Removed Application → Infrastructure project reference
- Moved DI wiring to API composition root
- **Roslyn analyzers** — `Roslynator.Analyzers`, `Meziantou.Analyzer`, `SonarAnalyzer.CSharp` in `Directory.Build.props` (global, build-time only); enforces code quality, security patterns, and anti-pattern detection at build time

## Phase 2 — Hand-Rolled CQRS ✅
- CQRS abstractions: `ICommand<T>`, `IQuery<T>`, `ICommandHandler`, `IQueryHandler`, `IPipelineBehavior`, `IDispatcher`
- `Dispatcher` — resolves handlers from DI, chains pipeline behaviors
- `ValidationBehavior` — runs FluentValidation, returns `Result<T>.Failure` on errors
- `LoggingBehavior` — structured logging with duration tracking
- `CqrsServiceExtensions.AddCqrs()` — assembly-scanning auto-registration
- 12 handlers: 7 Customer (Create, GetAll, GetById, GetByName, GetWithOrders, Update, Delete), 2 Order (CreateOrder, GetOrderDetails), 1 Payment (ProcessPayment), + info endpoint unchanged
- All controllers refactored to thin `IDispatcher`-only delegates
- `ResultExtensions` maps `Result<T>` → `ApiResponse<T>` → HTTP status codes
- Old service layer deleted (ICustomerService, IOrderService, IOpenPayService, CustomerService, OrderService, OpenPayService, CustomerValidator, OrderValidator)
- All 31 unit tests rewritten and passing
- **Committed:** `85fdd46` on `dev` branch (March 21, 2026)

## Phase 3 — Observability (OpenTelemetry) ✅
- Added 8 NuGet packages to SharedKernel (7 OpenTelemetry + Serilog)
- Created `AddObservability(serviceName, configuration, activitySourceNames)` extension in `SharedKernel/Observability/`
- Auto-instrumentation: ASP.NET Core, HttpClient, SqlClient, Runtime metrics
- Azure Monitor exporter (App Insights) + conditional OTLP exporter (Jaeger/Aspire)
- Created 3 `ActivitySource` classes: `OrderProcessing.Orders`, `.Customers`, `.Payments`
- Added activity spans to `CreateOrderCommandHandler` and `ProcessPaymentCommandHandler`
- Created `CorrelationMiddleware` in SharedKernel — extracts `Activity.TraceId`, enriches Serilog `LogContext`, adds `X-Trace-Id` response header
- Updated Serilog output templates: `{CorrelationId}` → `[{TraceId}]` in all 4 sharedsettings files
- Wired API + UI `Program.cs` with `AddObservability()` and `CorrelationMiddleware`
- Bumped `Microsoft.Extensions.DependencyInjection` + `Options.ConfigurationExtensions` to 9.0.0
- Build: 0 errors, 31/31 tests passing

## Phase 4 — Multi-Tenancy Skeleton ✅
- `ITenantProvider` interface in `SharedKernel/Multitenancy/` (cross-cutting, avoids circular dependency)
- `TenantId` property added to both `BaseAuditableEntity` and `BaseAuditableCreateEntity` — covers all 13 entities
- EF Global Query Filters on all 13 entity `DbSet`s with `_tenantProvider == null ||` guard for design-time/test compat
- `SaveChangesAsync` override auto-stamps `TenantId` on Added entities (both base classes)
- `TenantMiddleware` extracts `X-Tenant-Id` header (default: `"default"`), stores in `HttpContext.Items`, enriches Serilog `LogContext`
- `HeaderTenantProvider` reads tenant from `HttpContext.Items` at DI scope resolution
- AppMasterData uses `.IgnoreQueryFilters()` for cross-tenant PaymentProviders
- Wired in API + UI `Program.cs` (Scoped DI, middleware before `CorrelationMiddleware`)
- Build: 0 errors, 31/31 tests passing

## Phase 5 — Test Project Restructure ✅
- Created 4 test projects under `tests/` solution folder:
  - `Domain.Tests` — 8 entity tests (Customer defaults, Order defaults, OrderProduct computed price, tenant inheritance)
  - `Application.Tests` — 17 handler tests migrated (OrderHandlerTests, CustomerHandlerTests) + 4 TestBase classes
  - `API.Tests` — 15 controller tests migrated (OrderControllerTests, CustomersControllerTests)
  - `Integration.Tests` — 4 end-to-end scenario tests (Testcontainers SQL Server + WebApplicationFactory)
- Added `public partial class Program { }` to API for WebApplicationFactory<Program> access
- `SqlServerFixture` — Testcontainers `MsSqlContainer` with shared `[Collection("SqlServer")]`
- `IntegrationTestWebAppFactory` — replaces DbContext with Testcontainers connection string
- Removed old `XYDataLabs.OrderProcessingSystem.UnitTest` project from solution
- **Architecture tests** (`NetArchTest.Rules`) — compile-time enforcement of layer boundaries: Domain has zero dependencies, Application never references Infrastructure, no circular references between projects
- Build: 0 errors, 39/39 unit tests passing (integration tests require Docker)

## Phase 6 — Polish & Hardening ✅
- `CancellationToken` propagated through all 10 controller actions → Dispatcher → handlers
- `TimeProvider` abstraction replaces `DateTime.UtcNow` (InfoController, ProcessPaymentCommandHandler); registered as `TimeProvider.System` singleton
- `ICacheable` interface + `CachingBehavior<TRequest,TResult>` pipeline behavior (outermost, before logging)
- `IDistributedCache`: Redis via `StackExchangeRedisCache` when connection string present, `DistributedMemoryCache` fallback
- `GetAllCustomersQuery` implements `ICacheable` (5-min cache, key `customers:all`)
- `[JsonConstructor]` on `Result<T>` and `Error` for cache serialization round-trip
- `/health` endpoint with SQL Server health check (`AspNetCore.HealthChecks.SqlServer`)
- API versioning: `Asp.Versioning.Mvc` — URL segment `/api/v1/[controller]`, `[ApiVersion("1.0")]` on all controllers
- Swagger configured with `SubstituteApiVersionInUrl`, versioned group `'v'VVV`
- 3 new CachingBehavior unit tests (cache miss, cache hit, non-cacheable passthrough)
- All integration test routes updated to `/api/v1/` paths
- **Central Package Management (CPM)** — `ManagePackageVersionsCentrally=true` in `Directory.Packages.props`; all `Version=""` attributes removed from individual `.csproj` files; single source of truth for all NuGet package versions across the solution
- Build: 0 errors, 42/42 unit tests passing

---

## Phase 7 — Tenant Enforcement & Operational Discipline 📅

**Focus:** Make the system secure, tenant-safe, and production-ready.

### Key Deliverables

- `TenantValidationBehavior<TRequest, TResult>` — CQRS pipeline behavior enforcing tenant consistency across all requests
- `AuditLog` table (tenant-scoped) with structured entries for create/update/delete operations
- Structured logging enrichment: `TenantId`, `TraceId`, request name on every log line
- **Problem Details (RFC 9457)** — standardized error responses (`type`, `title`, `status`, `detail`, `traceId`, `tenantId`) on all endpoints
- **Global exception middleware** — catch-all that converts unhandled exceptions → `ProblemDetails` (no stack traces in production)
- Security headers middleware:
  - `X-Content-Type-Options: nosniff`
  - `X-Frame-Options: DENY`
  - `Strict-Transport-Security` (HSTS)
- Enhanced OpenTelemetry: request duration metrics, tenant validation failure counters
- Split health checks into `/health/live` (liveness) and `/health/ready` (readiness with SQL + Redis)

### DDD Tactical Patterns

- **Aggregate root** — `Order` entity with private constructor, `Create()` factory method returning `Result<Order>`
- **State machine** — `Order` status transitions: `Created → Paid → Shipped → Delivered → Cancelled` with explicit transition methods (`Pay()`, `Ship()`, `Deliver()`, `Cancel()`) each returning `Result<T>` — invalid transitions return failure, never throw
- **Value objects** — `Address` and `Money` as immutable `record` types with self-validation in constructor
- **Strongly-typed IDs** — `OrderId`, `CustomerId`, `ProductId` as `readonly record struct` wrappers around `Guid`; eliminates parameter-swap bugs (`Guid orderId, Guid customerId` → `OrderId orderId, CustomerId customerId`); EF Core value converters for transparent persistence
- **Optimistic concurrency** — `RowVersion` (`byte[]` / `[Timestamp]`) on `BaseAuditableEntity`; EF Core intercepts `DbUpdateConcurrencyException` in `SaveChangesAsync` → wraps as domain `ConcurrencyException`; command handlers catch and return `Result.Failure(Errors.Conflict)` with retry guidance
- **Domain invariants** — enforced inside aggregate methods (e.g. cannot ship an unpaid order), returning `Result<T>.Failure` with descriptive `Error` — no exceptions for business rules
- **Aggregate boundary rule** — aggregates enforce only their own transactional invariants and do not depend on injected infrastructure services. External collaboration (payment gateways, inventory lookups, messaging, persistence orchestration) remains in application handlers, process managers, or domain policies — keeps aggregate behavior focused and predictable

### Builds On

- Phase 4 (multi-tenancy skeleton — `ITenantProvider`, EF global filters)
- Phase 6 (basic `/health` endpoint, CachingBehavior pipeline)

### Outcome

Secure, observable, tenant-enforced system with rich domain model, standardized error handling — ready for event-driven decoupling.

### Known Risk (resolved in Phase 8)

The current `ProcessPaymentCommandHandler` makes three sequential OpenPay API calls (`CreateCustomerAsync` → `CreateCardTokenAsync` → `CreateChargeAsync`) followed by two DB writes (`CardTransaction` + `PayinLog`) in a single handler. If the process crashes or the DB transaction fails after the charge is successfully created at OpenPay, the charge is real but unrecorded — no reconciliation is possible without manually querying OpenPay by `AttemptOrderId`.

The Outbox Pattern in Phase 8 resolves this: write an `OutboxMessage` (with the charge result) in the same DB transaction as `CardTransaction`. The background publisher then confirms/reconciles asynchronously. Until Phase 8 ships, `AttemptOrderId` in `PayinLog` is the manual reconciliation key — queries to OpenPay's charge API can recover the charge state by that ID.

---

## Phase 8 — Event-Driven Foundation 📅

**Focus:** Decouple the system using events — foundation for microservices.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    EVENT-DRIVEN FLOW                              │
│                                                                  │
│  ┌──────────┐    ┌──────────┐    ┌──────────────────────────┐   │
│  │  Command  │───►│  Handler │───►│  SQL Database             │   │
│  │  (API)    │    │          │    │  ┌────────┐ ┌──────────┐ │   │
│  └──────────┘    └────┬─────┘    │  │ Entity │ │ Outbox   │ │   │
│                       │          │  │ Tables │ │ Messages │ │   │
│                       │          │  └────────┘ └─────┬────┘ │   │
│                       │          └───────────────────┼──────┘   │
│                       │                              │          │
│                       │          ┌───────────────────▼────────┐ │
│                       │          │  Background Publisher       │ │
│                       │          │  (polls OutboxMessages)     │ │
│                       │          └───────────────────┬────────┘ │
│                       │                              │          │
│                       │          ┌───────────────────▼────────┐ │
│                       │          │  Event Dispatcher            │ │
│                       │          │  (in-memory, pluggable for   │ │
│                       │          │   Service Bus in Phase 10)   │ │
│                       │          └──┬──────────┬──────────┬───┘ │
│                       │             │          │          │      │
│              ┌────────▼──┐  ┌──────▼───┐ ┌────▼────┐ ┌──▼────┐ │
│              │ Domain     │  │Inventory │ │Notific- │ │Audit  │ │
│              │ Event      │  │Reserved  │ │ation    │ │Log    │ │
│              │ Handler    │  │Handler   │ │Handler  │ │Handler│ │
│              └───────────┘  └──────────┘ └─────────┘ └───────┘ │
│                                                                  │
│  Domain Events:              Integration Events:                 │
│  • OrderCreatedDomainEvent   • OrderCreatedIntegrationEvent      │
│  • PaymentProcessedEvent     • InventoryReservedIntegrationEvent │
│                              • NotificationRequestedEvent        │
└─────────────────────────────────────────────────────────────────┘
```

### Key Deliverables

- **Domain Events** — `OrderCreatedDomainEvent`, `PaymentProcessedDomainEvent`
- **Integration Events** — `OrderCreatedIntegrationEvent`, `InventoryReservedIntegrationEvent`, `NotificationRequestedIntegrationEvent`
- **Outbox Pattern** — `OutboxMessages` table, transaction-safe event storage (same DB transaction as entity writes)
- **Inbox Pattern** — `InboxMessages` table for idempotent consumers (deduplication by `MessageId` before processing)
- **Background Publisher** — `IHostedService` that polls `OutboxMessages` and dispatches to the event bus
- **Event Dispatcher** — in-memory implementation (pluggable interface; swapped to Azure Service Bus in Phase 10)
- **Event Versioning** — envelope with `SchemaVersion` field; convention: `OrderCreatedV1` → `OrderCreatedV2` with backward-compatible projection
- **Parallel event handler execution** — `EventPublisher` dispatches all `IEventHandler<T>` via `Task.WhenAll`; partial failures collected into `AggregateException` — one handler failing does not skip remaining handlers
- **Automatic domain event dispatch** — `SaveChangesAsync` override extracts `IDomainEvent`s from `ChangeTracker.Entries<Entity>()` after `base.SaveChangesAsync()` succeeds; events are either published in-process (Phase 8) or written to the Outbox table in the same transaction — ensures events only fire after successful persistence, never on rollback

### Rules

- Events are **immutable** value objects — never modified after creation
- Outbox writes in the **same transaction** as the domain change (no dual-write)
- Background publisher is **idempotent** — Inbox table deduplicates by `MessageId` before handler execution
- **Event schema changes** must be backward-compatible (additive fields only; breaking changes = new version)
- **Parallel dispatch** — all handlers for a given event execute concurrently; failures are aggregated, not swallowed

### Outcome

Loose coupling, async workflows, idempotent delivery, parallel event handling, and a microservice-ready event backbone with versioned schemas.

---

## Phase 8.5 — Multi-Provider Payment Architecture 📅

**Focus:** Replace OpenPay with Stripe (`Stripe.net`) and enable per-tenant payment provider selection.

### Why Stripe

| Dimension | OpenPay (`Openpay` 1.0.27) | Stripe (`Stripe.net` v50+) |
|-----------|---------------------------|---------------------------|
| .NET support | .NET Framework 4.5.2 target | .NET Standard 2.0+ / .NET 8+ native |
| Maintenance | Last release April 2024 | Active — releases weekly |
| Async model | Sync SDK wrapped in `Task.Run()` | Async-first throughout |
| Resilience | Service-level `ResiliencePipeline<T>` workaround | Direct `Microsoft.Extensions.Http.Resilience` on `HttpClient` |
| Idempotency keys | Must build manually | First-class `RequestOptions.IdempotencyKey` on every call |
| 3DS | Per-tenant `Use3DSecure` flag (manual) | Payment Intents API — 3DS handled natively by flow |

The async model difference is the most architecturally significant: because the current OpenPay SDK is synchronous, `OpenPayAdapterService` wraps calls in `Task.Run()` and requires a custom `ResiliencePipeline<string>` registered at the service level. Stripe's async SDK would allow standard `Microsoft.Extensions.Http.Resilience` on the `IHttpClientBuilder` — the cleaner, framework-native pattern.

### Migration Path

The adapter pattern already isolates the blast radius. The full swap touches two files:
- `XYDataLabs.OpenPayAdapter/StripeAdapterService.cs` — new implementation of `IOpenPayAdapterService`
- `XYDataLabs.OpenPayAdapter/ServiceCollectionExtensions.cs` — DI registration switch

All Application and Domain code remains unchanged.

### Per-Tenant Provider Selection (Advanced)

The `PaymentProvider` entity already exists with a `Use3DSecure` flag per tenant. Extending it with a `ProviderType` discriminator enables per-tenant payment provider routing:

```csharp
// PaymentProvider entity extension
public string ProviderType { get; private set; }  // "Stripe" | "OpenPay"

// DI registration — keyed services (.NET 8+)
services.AddKeyedScoped<IOpenPayAdapterService, StripeAdapterService>("Stripe");
services.AddKeyedScoped<IOpenPayAdapterService, OpenPayAdapterService>("OpenPay");

// Handler resolution
var provider = serviceProvider.GetRequiredKeyedService<IOpenPayAdapterService>(
    tenant.PaymentProvider.ProviderType);
```

This makes per-tenant payment provider a runtime configuration decision — no redeploy needed to switch a tenant's processor. Each tenant in the `PaymentProvider` table declares their processor type, and the handler resolves the correct adapter via keyed DI.

### Idempotency Key Strategy

With Stripe, every charge call must carry an idempotency key to prevent double-charging on retries. The `AttemptOrderId` already generated per payment attempt maps directly to this — it becomes the idempotency key passed as `RequestOptions.IdempotencyKey`. This is the Phase 8 Outbox Pattern complement: the Outbox guarantees delivery; the idempotency key guarantees the provider sees each charge exactly once regardless of retry count.

### Resilience (Cleaner with Stripe)

With an async SDK, the `ResiliencePipeline<string>` service-level wrapper in `ServiceCollectionExtensions.cs` is replaced by:

```csharp
services.AddHttpClient<StripeAdapterService>()
    .AddStandardResilienceHandler();  // Microsoft.Extensions.Http.Resilience
```

Same retry + circuit breaker semantics, but composed at the `HttpClient` level — the framework-standard pattern. The `ResiliencePipeline<string>` registration and all `_pipeline.ExecuteAsync()` wrapping in the adapter disappears.

### Builds On

- Phase 4 (multi-tenancy — `PaymentProvider` entity per tenant)
- Phase 7 (`OpenPayAdapterService` resilience + circuit breaker — superseded by `AddStandardResilienceHandler`)
- Phase 8 (Outbox Pattern — `AttemptOrderId` becomes idempotency key)

### Outcome

Production-grade payment processing with async-native SDK, idempotency-safe retries, per-tenant processor routing, and `HttpClient`-level resilience. `OpenPayAdapterService` can be retained as a second registered provider until all tenants migrate.

---

## Phase 9 — YARP Microservices Architecture (Local) 📅

**Focus:** Module isolation within the monolith, then service extraction with event-based communication.

### Module Isolation (First Step — Before Extraction)

Before extracting to separate deployables, restructure the monolith into isolated modules:

- **Per-module project structure** — split shared `Application`, `Domain`, `Infrastructure` into per-module libraries:
  - `Orders.Domain`, `Orders.Features`, `Orders.Infrastructure`
  - `Inventory.Domain`, `Inventory.Features`, `Inventory.Infrastructure`
  - `Notifications.Domain`, `Notifications.Features`, `Notifications.Infrastructure`
- **PublicApi contracts** — `IOrderModuleApi`, `IInventoryModuleApi` interfaces in dedicated `*.PublicApi` projects with strongly-typed request/response records. Modules depend ONLY on each other's PublicApi — never internal Domain/Features/Infrastructure
- **Per-module DB schemas** — each module owns its own SQL schema (`orders`, `inventory`, `notifications`) within the shared database. Phase 11's "split databases" then becomes a connection string change, not a data migration
- **Per-module database migrators** — `IModuleDatabaseMigrator` interface; each module owns its `DbContext` and independent migration history. Startup runs all migrators sequentially
- **Module self-registration** — `AddOrdersModule()`, `AddInventoryModule()`, `AddNotificationsModule()` extension methods chain API registration, infrastructure setup, and assembly scanning. `Program.cs` stays clean as project count grows
- **`AssemblyReference.cs` markers** — static class per project exposing `Assembly` for reliable handler discovery, endpoint registration, and architecture test scanning
- **Bounded-context and subdomain mapping** — before extraction, explicitly model Orders, Inventory, and Notifications as business contexts with clear responsibilities, upstream/downstream relationships, and published contracts. Module boundaries should follow business capability boundaries, not just technical packaging
- **Architecture tests updated** — `NetArchTest.Rules` (from Phase 5) now enforces inter-module boundaries: modules cannot reference each other's internals, only PublicApi contracts
- **Specification pattern** — composable query objects (`OrderByStatusSpec`, `ActiveCustomersSpec`) encapsulating EF Core `Where`/`Include`/`OrderBy` logic; reusable across handlers within a module. Introduced alongside per-module repositories — specifications replace scattered inline LINQ with testable, named query definitions

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                    LOCAL DEVELOPMENT ENVIRONMENT                     │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                    YARP GATEWAY (Port 8080)                    │  │
│  │             http://gateway.localhost:8080                      │  │
│  │                                                                │  │
│  │  Routing Rules:                                                │  │
│  │  • orders.localhost      → Orders API                          │  │
│  │  • inventory.localhost   → Inventory API                       │  │
│  │  • notifications.localhost → Notifications API                 │  │
│  │  • ui.localhost          → UI                                  │  │
│  └────────┬──────────┬──────────┬──────────┬──────────────────────┘  │
│           │          │          │          │                         │
│  ┌────────▼─────┐ ┌──▼─────────┐ ┌────────▼────────┐ ┌──────▼─────┐│
│  │   Orders     │ │ Inventory  │ │ Notifications   │ │     UI     ││
│  │     API      │ │    API     │ │      API        │ │  (MVC App) ││
│  │              │ │            │ │                 │ │            ││
│  │  • Orders    │ │  • Stock   │ │  • Email        │ │  • Views   ││
│  │  • Customers │ │  • Reserve │ │  • SMS          │ │  • Forms   ││
│  │  • Payments  │ │  • Release │ │  • Templates    │ │            ││
│  └──────┬───────┘ └─────┬──────┘ └────────┬────────┘ └────────────┘│
│         │               │                 │                         │
│         └───────────────┼─────────────────┘                         │
│                         │                                            │
│         ┌───────────────▼──────────────────────┐                    │
│         │         Event Bus (in-memory)          │                    │
│         │  OrderCreated → InventoryReserved →    │                    │
│         │  NotificationRequested                 │                    │
│         └───────────────┬──────────────────────┘                    │
│                         │                                            │
│              ┌──────────▼──────────┐                                 │
│              │   SQL Database      │                                 │
│              │   (Shared — temp)   │                                 │
│              └─────────────────────┘                                 │
│                                                                      │
│  Managed by Docker Compose (7 containers)                            │
└─────────────────────────────────────────────────────────────────────┘
```

### Solution Structure (11 Projects)

```
XYDataLabs.OrderProcessingSystem.sln
├── XYDataLabs.OrderProcessingSystem.Gateway          (NEW - YARP Proxy)
│   ├── appsettings.json (routing configuration)
│   └── Program.cs
├── XYDataLabs.OrderProcessingSystem.API              (Refactored - Orders only)
│   └── Controllers/
│       ├── OrderController.cs
│       └── CustomerController.cs
├── XYDataLabs.OrderProcessingSystem.InventoryAPI     (NEW - Stock Management)
│   └── Controllers/
│       └── InventoryController.cs
├── XYDataLabs.OrderProcessingSystem.NotificationsAPI (NEW - Notifications)
│   └── Controllers/
│       └── NotificationController.cs
├── XYDataLabs.OrderProcessingSystem.Contracts        (NEW - Shared event schemas + API DTOs)
├── XYDataLabs.OrderProcessingSystem.Orders.PublicApi  (NEW - IOrderModuleApi + request/response records)
├── XYDataLabs.OrderProcessingSystem.Inventory.PublicApi (NEW - IInventoryModuleApi + contracts)
├── XYDataLabs.OrderProcessingSystem.Notifications.PublicApi (NEW - INotificationModuleApi + contracts)
├── XYDataLabs.OrderProcessingSystem.UI               (Existing - Updated routing)
├── XYDataLabs.OrderProcessingSystem.Orders.Domain     (Split from shared Domain)
├── XYDataLabs.OrderProcessingSystem.Orders.Features   (Split from shared Application)
├── XYDataLabs.OrderProcessingSystem.Orders.Infrastructure (Split from shared Infrastructure)
├── XYDataLabs.OrderProcessingSystem.Inventory.Domain  (NEW)
├── XYDataLabs.OrderProcessingSystem.Inventory.Features (NEW)
├── XYDataLabs.OrderProcessingSystem.Inventory.Infrastructure (NEW)
├── XYDataLabs.OrderProcessingSystem.Notifications.Domain (NEW)
├── XYDataLabs.OrderProcessingSystem.Notifications.Features (NEW)
├── XYDataLabs.OrderProcessingSystem.Notifications.Infrastructure (NEW)
├── XYDataLabs.OrderProcessingSystem.SharedKernel     (Shared)
└── XYDataLabs.OpenPayAdapter                         (Shared)
```

### Docker Compose Configuration

```yaml
# docker-compose.microservices.yml
services:
  gateway:
    image: orderprocessing-gateway:dev
    ports:
      - "8080:8080"
    depends_on:
      - orders-api
      - inventory-api
      - notifications-api
      - ui

  orders-api:
    image: orderprocessing-orders-api:dev
    # No exposed ports - accessed via gateway

  inventory-api:
    image: orderprocessing-inventory-api:dev
    # No exposed ports - accessed via gateway

  notifications-api:
    image: orderprocessing-notifications-api:dev
    # No exposed ports - accessed via gateway

  ui:
    image: orderprocessing-ui:dev
    # No exposed ports - accessed via gateway

  sqlserver:
    image: mcr.microsoft.com/mssql/server:2022-latest
    ports:
      - "1433:1433"

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
```

### Communication Rules (Critical)

| Communication Type | Pattern | Example |
|--------------------|---------|---------|
| **Queries** (read) | Synchronous HTTP | UI → Gateway → Orders API `GET /api/v1/Order/{id}` |
| **Workflows** (write) | Asynchronous Events | `OrderCreated` → Event Bus → Inventory reserves stock |
| **Shared DB** | Per-module schemas | `orders.*`, `inventory.*`, `notifications.*` schemas in shared DB; split to separate DBs in Phase 11 |
| **Module isolation** | Per-module projects | Each module owns Domain/Features/Infrastructure; cross-module communication via PublicApi contracts only |

### Characteristics

✅ **Advantages:**
- Service isolation — independent deployment and scaling
- Clean URLs via YARP — no port management (`orders.localhost`, `inventory.localhost`)
- Event-driven workflows — services communicate via events, not direct HTTP calls
- Fault isolation — one service failure doesn't crash entire system
- Production pattern — same as Azure Container Apps architecture
- Service-level observability — per-service metrics and tracing
- Resilient inter-service communication via Polly from day one

⚠️ **Challenges:**
- Increased complexity (7 containers vs 2, including Redis)
- Network latency between services
- Distributed transactions complexity
- Docker Compose orchestration required

### Gateway Cross-Cutting Concerns

- **CORS** — policy per downstream service, configured in YARP
- **Rate limiting** — `System.Threading.RateLimiting` per tenant/client at gateway level
- **Request/response logging** — structured audit trail at gateway entry point
- **Request size limits** — prevent oversized payloads reaching downstream services
- **Authentication prep** — token forwarding middleware (prepares for Phase 10 JWT)

### Resilience (Polly v8 Basics)

- `HttpClientFactory` with named/typed clients for inter-service HTTP calls
- **Retry** — exponential backoff for transient HTTP failures
- **Circuit breaker** — prevent cascade failures when a downstream service is unhealthy
- **Timeout** — per-request timeout to avoid hanging calls

### Operational Concerns

- **Graceful shutdown** — `IHostApplicationLifetime` to drain in-flight requests before container stops
- **Structured concurrency** — `Task.WhenAll` for parallel scatter-gather queries through gateway
- **Testcontainers snapshots** — pre-seeded Docker images for integration tests: build a custom SQL Server image with migrations + seed data baked in, so each test run skips migration/seed overhead; apply when test suite runtime becomes a CI bottleneck across multiple per-module DBs

### Outcome

Module-isolated, working microservices locally with proven PublicApi boundaries and correct event-based communication model.

---

## Phase 10 — Azure Container Apps Migration 📅

**Focus:** Cloud-native deployment with managed messaging and identity.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         AZURE CLOUD                                  │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │           Azure Container Apps Environment                      │ │
│  │                                                                 │ │
│  │  ┌──────────────────────────────────────────────────────────┐  │ │
│  │  │              YARP Gateway Container App                   │  │ │
│  │  │         (Internal - JWT validation + routing)             │  │ │
│  │  └────────┬──────────┬──────────┬──────────┬────────────────┘  │ │
│  │           │          │          │          │                    │ │
│  │  ┌────────▼─────┐ ┌──▼─────────┐ ┌────────▼────────┐ ┌───▼───┐│ │
│  │  │  Orders App  │ │Inventory   │ │ Notifications   │ │ UI    ││ │
│  │  │  (Internal)  │ │   App      │ │      App        │ │  App  ││ │
│  │  │              │ │(Internal)  │ │   (Internal)    │ │(Public)│ │
│  │  └──────┬───────┘ └─────┬──────┘ └───────┬─────────┘ └───────┘│ │
│  │         │               │                │                      │ │
│  │         └───────────────┼────────────────┘                      │ │
│  │                         │                                       │ │
│  │           ┌─────────────▼─────────────────┐                     │ │
│  │           │  Azure Service Bus             │                     │ │
│  │           │  (Topics + Subscriptions)      │                     │ │
│  │           │  Replaces in-memory event bus  │                     │ │
│  │           └───────────────────────────────┘                     │ │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  ┌──────────────────────┐         ┌──────────────────────┐          │
│  │  Azure SQL Database  │         │  Application         │          │
│  │  (Private Endpoint)  │         │  Insights + OTel     │          │
│  └──────────────────────┘         └──────────────────────┘          │
│                                                                      │
│  ┌──────────────────────┐         ┌──────────────────────┐          │
│  │  Azure Container     │         │  Azure Key Vault     │          │
│  │  Registry (ACR)      │         │  (Private Endpoint)  │          │
│  └──────────────────────┘         └──────────────────────┘          │
│                                                                      │
│  ┌──────────────────────┐         ┌──────────────────────┐          │
│  │  Azure Entra ID      │         │  Azure Monitor       │          │
│  │  (JWT + OIDC)        │         │  (Logging & Metrics) │          │
│  └──────────────────────┘         └──────────────────────┘          │
│                                                                      │
│  ┌──────────────────────┐         ┌──────────────────────┐          │
│  │  Azure Cache for     │         │  Azure API           │          │
│  │  Redis (Private EP)  │         │  Management (APIM)   │          │
│  └──────────────────────┘         │  (Public Gateway)    │          │
│                                   └──────────────────────┘          │
│  ┌──────────────────────┐         ┌──────────────────────┐          │
│  │  Azure Functions     │         │  Azure Event Grid    │          │
│  │  (DLQ reprocessor)   │         │  (Platform events)   │          │
│  └──────────────────────┘         └──────────────────────┘          │
│                                                                      │
│  ┌──────────────────────┐                                            │
│  │  Azure Blob Storage  │                                            │
│  │  (Order attachments) │                                            │
│  └──────────────────────┘                                            │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Deliverables

- Deploy to **Azure Container Apps** (managed environment, auto-scaling, scale-to-zero)
- **Azure API Management (APIM)** — Consumption tier as public-facing gateway; subscription keys, external rate limiting, developer portal, API analytics. YARP becomes the internal east-west proxy behind APIM: `Internet → APIM → ACA Ingress → YARP → Services`
- **Azure Container Registry (ACR)** — build and push container images
- **Azure Service Bus** — replace in-memory event bus with durable topics + subscriptions
- **Azure Event Grid** — platform/infrastructure event routing (deployment notifications, blob lifecycle); Service Bus remains for domain events. Decision rule: Event Grid = reactive fan-out, Service Bus = reliable delivery with sessions/DLQ
- **Azure Functions** — Service Bus-triggered Function for DLQ reprocessing (isolated process model); timer-triggered Function for scheduled projection health checks (Phase 14)
- **Azure Blob Storage** — order file attachments (invoices, receipts, proof of delivery); managed identity access, private endpoint. `BlobCreated` events routed via Event Grid to trigger downstream processing (e.g. Document Intelligence extraction in Phase 12)
- **Azure Cache for Redis** — managed Redis replacing local container; used for distributed cache and session state
- **Observability** — App Insights + OpenTelemetry distributed tracing across all services; `traceparent` propagated through Service Bus message headers
- **Secrets** — Azure Key Vault with managed identity (no credentials in config)
- **Private networking** — VNet integration, private endpoints for SQL, Key Vault, Redis, and Blob Storage
- **Cost governance** — scale-to-zero on all Container Apps, APIM Consumption tier (pay-per-call), autoscale RU caps on Cosmos DB, Azure Budget alerts per resource group

### Security

- **Identity:** Azure Entra ID (Azure AD) for authentication
- **JWT auth** — token validation at APIM (policy-based) and YARP gateway, token propagation to downstream services
- **Managed Identity** — services access Key Vault and SQL without stored credentials
- **OIDC** — GitHub Actions deploys via federated credentials (existing pattern)
- **WAF / Network Security** — Azure Front Door or WAF policy in front of APIM; NSG rules for ACA VNet; private DNS zones for internal service resolution

### Messaging Backbone

- **Azure Service Bus** replaces the in-memory event dispatcher from Phase 8
- Topics: `order-events`, `inventory-events`, `notification-events`
- Each service subscribes to relevant topics
- Dead-letter queues for failed message processing

### Dead-Letter Queue (DLQ) Handling

- **Alert threshold** — Azure Monitor alert when DLQ depth exceeds configurable limit
- **Azure Function (DLQ reprocessor)** — Service Bus-triggered Function replays dead-lettered messages back to source topic (replaces admin API endpoint — Functions are the natural fit for stateless, event-triggered processing)
- **Poison message quarantine** — messages that fail reprocessing N times are moved to a poison store for manual review

### Advanced Deployment Patterns

- **Blue-green deployments** — zero-downtime with ACA revisions; switch traffic after health check passes
- **Canary releases** — gradual traffic shifting (e.g. 10% → 50% → 100%) with automatic rollback on error-rate spike

> **Operational Detail:** See [ACA-Migration-Plan.md](./Documentation/04-Enterprise-Architecture/ACA-Migration-Plan.md) for the 13-phase operational runbook covering governance, identity hardening, ACR setup, canary deployments, and decommissioning.

### Outcome

Secure, scalable cloud-native microservices with APIM as public gateway, durable messaging (Service Bus + Event Grid), Azure Functions for DLQ reprocessing, managed Redis, and zero-downtime deployments.

---

## Phase 11 — Data Ownership & Service Autonomy 📅

**Focus:** True microservice boundaries — each service owns its data.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                    SERVICE DATA OWNERSHIP                            │
│                                                                      │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │   Orders API     │  │  Inventory API   │  │ Notifications API│  │
│  │                  │  │                  │  │                  │  │
│  │  Own entities:   │  │  Own entities:   │  │  Own entities:   │  │
│  │  • Order         │  │  • StockItem     │  │  • Notification  │  │
│  │  • Customer      │  │  • Reservation   │  │  • Template      │  │
│  │  • Payment       │  │  • StockMovement │  │  • DeliveryLog   │  │
│  │  Own migrations  │  │  Own migrations  │  │  Own migrations  │  │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘  │
│           │                     │                      │            │
│  ┌────────▼─────────┐  ┌───────▼──────────┐  ┌────────▼─────────┐  │
│  │   Orders DB      │  │  Inventory DB    │  │ Notifications DB │  │
│  │   (SQL Server)   │  │  (SQL Server)    │  │  (SQL Server)    │  │
│  └────────┬─────────┘  └───────┬──────────┘  └────────┬─────────┘  │
│           │                     │                      │            │
│           └─────────────────────┼──────────────────────┘            │
│                                 │                                    │
│              ┌──────────────────▼──────────────────┐                │
│              │       Azure Service Bus              │                │
│              │   (eventual consistency via events)   │                │
│              │                                      │                │
│              │  No cross-service joins allowed!      │                │
│              │  Data sync = events only              │                │
│              └──────────────────────────────────────┘                │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Deliverables

- **Database per service** — Orders DB, Inventory DB, Notifications DB
- Remove shared `DbContext` — each service owns its entities and EF migrations
- Shared projects (`Application`, `Domain`, `Infrastructure`) split into per-service libraries
- **Eventual consistency** — no cross-service joins; data synchronization via events only
- Each service maintains its own read-optimized projections of data it needs from other services
- **`XYDataLabs.OrderProcessingSystem.DurableFunctions`** — separate Azure Functions project (isolated process model) hosting Durable Function orchestrations for cross-service workflows that require compensating actions (see Distributed Workflow Strategy below)

### Rules

- No direct database queries across service boundaries
- If Orders needs inventory status, it subscribes to `InventoryUpdated` events and maintains a local projection
- Cross-service reads use lightweight HTTP queries (via gateway) for real-time needs

### Distributed Workflow Strategy

- **Default: Choreography** — services react to events independently (e.g. `OrderCreated` → Inventory reserves → Notification sends)
- **Escalation: Saga / Process Manager** — introduce only when a workflow requires compensating actions across 3+ services (e.g. order fulfilment with payment rollback)
- **Decision criteria:** If a failure in step N requires undoing steps 1…N-1, use a Saga; otherwise choreography is sufficient

### Durable Functions Project (`XYDataLabs.OrderProcessingSystem.DurableFunctions`)

- **Separate project** — Azure Functions (isolated process model) with `Microsoft.Azure.Functions.Worker.Extensions.DurableTask`
- **Orchestrator functions** — `OrderFulfilmentOrchestrator` (payment → inventory → shipping → notification with compensating rollback)
- **Activity functions** — each step is an activity: `ReserveInventoryActivity`, `ProcessPaymentActivity`, `SendNotificationActivity`, `CompensatePaymentActivity`
- **Sub-orchestrations** — complex sub-workflows (e.g. multi-item inventory reservation) composed within parent orchestrators
- **Fan-out/fan-in** — parallel activity execution (e.g. validate all order line items concurrently, await all before proceeding)
- **Durable timers + human interaction** — approval workflows with configurable timeout and escalation
- **Service Bus triggers** — orchestrations started by Service Bus messages (e.g. `OrderCreated` event triggers `OrderFulfilmentOrchestrator`)
- **Observability** — Durable Functions execution history + OpenTelemetry correlation; orchestration status queryable via built-in HTTP API
- **Deployment** — separate ACA container app with its own CI/CD pipeline; scale-to-zero when idle

### Database Migration Strategy

- **EF Core bundles** — `dotnet ef migrations bundle` produces a self-contained executable for each service DB
- **Init containers** — ACA init container runs the migration bundle before the app container starts
- **Rollback** — migration bundles support `--target` for reverting to a specific migration; never use destructive migrations in production

### Performance Conventions

- **`AsNoTracking()`** on all EF Core read queries — enforced as team convention; avoids change-tracker overhead on write-side validation/lookup queries
- **Indexing review** per service DB — cover foreign keys, `TenantId` filters, and common `WHERE` clause columns; use EF Core query logging or SQL Profiler to identify slow queries
- **EF Core 8 `SqlQuery<T>`** for complex/reporting queries — raw SQL returning unmapped DTOs with zero change-tracking overhead; parameterized by default (no SQL injection risk); eliminates need for Dapper while keeping a single `DbContext` connection pool. Use `EF.CompileAsyncQuery` for true hot paths.
- **Bulk operations** — use `EFCore.BulkExtensions` or `ExecuteSqlInterpolated` for batch import/export scenarios (e.g. bulk order ingestion); standard single-entity writes remain via EF Core

### Outcome

Independent, fully decoupled services with clear data ownership, Durable Functions for orchestrated workflows with compensating actions, automated database migrations, and codified performance conventions.

---

## Phase 12 — Platform Engineering & DevOps 📅

**Focus:** Operational excellence — configuration, observability dashboards, and advanced resilience.

### Key Deliverables

- **Central configuration** — Azure App Configuration for feature flags and shared settings
- **Secrets management** — Azure Key Vault with RBAC (migrate from access policies)
- **Observability dashboards** — Azure Monitor workbooks with per-service metrics, SLIs/SLOs
- **Distributed tracing** — full correlation across Service Bus messages and HTTP requests
- **Per-service CI/CD pipelines** — independent build/test/deploy per service
- **Health check gates** — deployment blocked if `/health/ready` fails post-deploy
- **Advanced Polly** — bulkhead isolation + fallback policies (retry + circuit breaker already in Phase 9)
- **Azure AI Document Intelligence** — extract structured data from uploaded invoices/receipts in Blob Storage; Event Grid triggers Function → Document Intelligence API → enriches order metadata. Demonstrates Azure Cognitive Services integration without over-engineering.
- **DR / Business Continuity** — documented RTO/RPO targets per service; Azure SQL geo-replication strategy; Cosmos DB multi-region (mention only); backup/restore runbook
- **Performance / Load Testing** — Azure Load Testing or k6 for baseline performance; SLO validation under realistic load before production

### Outcome

Scalable, manageable production platform with enterprise-grade operations, advanced resilience, AI-powered document processing, DR planning, and load-tested SLOs.

---

## Phase 13 — Aspire & Developer Experience 📅

**Focus:** Developer inner-loop experience with .NET Aspire.

### Key Deliverables

- Adopt **.NET Aspire** for local orchestration and service composition
- **AppHost project** — replaces Docker Compose for local development
- **Resource definitions** — `builder.AddRedis()`, `builder.AddSqlServer()`, `builder.AddProject<OrdersAPI>()` etc.
- **Service discovery** — Aspire-managed service resolution (no hardcoded URLs)
- **Dashboard** — Aspire dashboard for local traces, logs, and metrics
- **Integration tests** — `DistributedApplicationTestingBuilder` for end-to-end tests against the Aspire graph
- Full end-to-end trace correlation across all services
- **Aspire manifest** → ACA deployment via `azd` or Bicep

### Outcome

Enterprise-grade, cloud-native system with excellent developer inner-loop experience and integration-tested service graph.

---

## Phase 14 — CQRS Read Model with Cosmos DB (MongoDB API) 📅

**Focus:** Separate read and write models for performance and scalability.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                    CQRS READ/WRITE SEPARATION                        │
│                                                                      │
│  WRITE PATH                           READ PATH                     │
│  ─────────                            ─────────                     │
│                                                                      │
│  ┌──────────┐    ┌─────────────┐      ┌──────────┐    ┌──────────┐ │
│  │ Command  │───►│  Handler    │      │  Query   │───►│ Cosmos DB│ │
│  │ (POST/   │    │ (validates, │      │  (GET)   │    │ MongoDB  │ │
│  │  PUT/    │    │  writes)    │      └──────────┘    │ API      │ │
│  │  DELETE) │    └─────────────┘                      │ (fast    │ │
│  └──────────┘          │                          │  reads)  │ │
│                        │                          └──────────┘ │
│                        │                                ▲       │
│               ┌────────▼─────────┐                          │       │
│               │  SQL Server      │                          │       │
│               │  (Source of      │                          │       │
│               │   Truth)         │                          │       │
│               │  ┌────────────┐  │                          │       │
│               │  │ Outbox     │  │                          │       │
│               │  │ Messages   │──┼──────────┐               │       │
│               │  └────────────┘  │          │               │       │
│               └──────────────────┘          │               │       │
│                                             │               │       │
│                                  ┌──────────▼─────────┐     │       │
│                                  │  Event Bus          │     │       │
│                                  │  (Service Bus)      │     │       │
│                                  └──────────┬──────────┘     │       │
│                                             │               │       │
│                                  ┌──────────▼─────────┐     │       │
│                                  │  Projection         │     │       │
│                                  │  Handlers           │─────┘       │
│                                  │  (update MongoDB)   │             │
│                                  └──────────┬──────────┘             │
│                                             │                        │
│                                  ┌──────────▼─────────┐              │
│                                  │  Hangfire Jobs      │              │
│                                  │  • Rebuild projs    │              │
│                                  │  • Fix inconsist.   │              │
│                                  │  • Backfill data    │              │
│                                  └─────────────────────┘              │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Deliverables

**1. Read Models (Azure Cosmos DB for MongoDB API)**
- Denormalized documents: Orders with Customer + Payment info, optimized for UI queries
- `TenantId` as **partition key** — natural fit for multi-tenancy; included in every document; query filters applied per tenant
- Same MongoDB .NET driver — code runs against Cosmos DB for MongoDB API with zero changes
- **RU provisioning** — autoscale with configurable max RU cap per collection

**2. Projection Handlers**
- Consume events: `OrderCreated`, `PaymentProcessed`, `CustomerUpdated`
- Build/update denormalized Cosmos DB documents in near-real-time

**3. Background Jobs (Hangfire)**
- Rebuild projections on demand
- Fix inconsistencies between SQL and Cosmos DB
- Backfill missing data after schema changes
- **Distributed locking (job-specific showcase)** — optional singleton coordination for projection rebuild/backfill jobs when duplicate execution across multiple instances would create operational inconsistency. Keep this as a concrete example (for example, `RebuildOrdersProjectionJob`) rather than introducing a generic lock abstraction; prefer idempotency first

**4. Multi-Tenancy**
- `TenantId` as partition key in every Cosmos DB document
- All read queries filtered by tenant — same pattern as EF global filters

### Rules (Critical)

- **No dual write** — never write to SQL + Cosmos DB in the same request
- **Always:** Write → SQL → Outbox → Event Bus → Projection → Cosmos DB
- **Cosmos DB is NOT the source of truth** — SQL Server is authoritative
- **Eventual consistency** — reads may lag behind writes by seconds

### Read Model Versioning

- Every Cosmos DB document includes a `_schemaVersion` field (integer)
- Projection handlers write the current schema version; older documents coexist with newer ones
- **Backward-compatible projections** — query code handles missing fields with sensible defaults
- On major schema change, a Hangfire job rebuilds the projection from event history, bumping `_schemaVersion`
- **Projection lag metric** — OTel gauge tracking seconds between last SQL write and corresponding Cosmos DB update; alert if > threshold
- **Cosmos DB change feed** — noted as an alternative to Service Bus for driving projections (can be evaluated if latency requirements tighten)

### Outcome

True CQRS with read/write separation, high-performance queries via Cosmos DB (MongoDB API), scalable read layer with `TenantId` partitioning, and eventually consistent system.

---

## Comparison Matrix

| Feature | Baseline (Monolith) | Phase 9 (YARP Local) | Phase 10 (ACA Cloud) | Phase 14 (Final State) |
|---------|--------------------|--------------------|--------------------|-----------------------|
| **Deployment** | 2 App Services | Docker Compose (7 containers) | ACA (auto-scaling) | ACA + Cosmos DB |
| **Communication** | In-process | Events + HTTP | Service Bus + Event Grid + HTTP | Service Bus + Event Grid + HTTP |
| **Data** | Single shared DB | Single shared DB | Single shared DB | DB per service + Cosmos DB |
| **Scaling** | Vertical only | Per-container | Per-service auto-scale | Per-service + read replicas |
| **Identity** | Key Vault (basic) | N/A (local) | Entra ID + JWT + MI | Entra ID + JWT + MI |
| **Observability** | App Insights | OTel + local traces | OTel + Azure Monitor | Full distributed traces |
| **Resilience** | None | Polly basics (retry + CB) | Polly + advanced + DLQ | Polly + dead-letter + retry |
| **API Gateway** | N/A | YARP (local) | APIM (public) + YARP (internal) | APIM + YARP |
| **Dev Experience** | VS F5 | Docker Compose | ACA deploy | .NET Aspire |

---

## Migration Strategy

### Incremental Approach

The monolith remains operational throughout. Each phase adds capability without breaking production.

```
Baseline (Monolith) ─── ✅ Running on Azure App Service
     │
     ├── Phases 1-6  ─── ✅ Internal modernization (CQRS, OTel, tenancy, caching)
     │
     ├── Phase 7     ─── 📅 Tenant enforcement & security hardening
     │
     ├── Phase 8     ─── 📅 Event-driven core (Outbox + events inside monolith)
     │
     ├── Phase 9     ─── 📅 Extract services locally (YARP + Docker Compose)
     │
     ├── Phase 10    ─── 📅 Deploy to ACA + Service Bus + APIM + Functions
     │
     ├── Phase 11    ─── 📅 Split databases (each service owns its data)
     │
     ├── Phase 12    ─── 📅 Platform engineering (App Config, CI/CD, dashboards)
     │
     ├── Phase 13    ─── 📅 Aspire orchestration + advanced deployments
     │
     └── Phase 14    ─── 📅 CQRS read model (Cosmos DB) — final architecture
```

### Why This Order?

| Transition | Why it must come first |
|------------|----------------------|
| Phase 7 before 8 | Tenant safety must be enforced before events carry tenant context |
| Phase 8 before 9 | Events must exist before services can communicate asynchronously |
| Phase 9 before 10 | Validate microservices locally before deploying to cloud |
| Phase 10 before 11 | Cloud infrastructure must exist before splitting databases |
| Phase 11 before 12 | Data ownership enables per-service CI/CD pipelines |
| Phase 12 before 13 | Platform foundations needed before Aspire adoption |
| Phase 13 before 14 | Aspire orchestration simplifies MongoDB integration |

---

## Learning Objectives by Phase

### Phases 1-6 ✅ Achieved
- [x] Azure App Service deployment + CI/CD with GitHub Actions
- [x] Infrastructure as Code (Bicep) + Application Insights
- [x] Clean Architecture + CQRS with `Result<T>` pattern
- [x] `IAppDbContext` abstraction + SharedKernel
- [x] OpenTelemetry observability (auto-instrumentation + custom ActivitySources)
- [x] Multi-tenancy skeleton (EF global filters, `X-Tenant-Id` header)
- [x] Structured test projects (Domain, Application, API, Integration)
- [x] Caching pipeline, API versioning `/api/v1/`, health checks, CancellationToken, TimeProvider
- [x] Roslyn analyzers (Roslynator, Meziantou, SonarAnalyzer) — build-time code quality enforcement
- [x] Architecture tests (`NetArchTest.Rules`) — enforcing Clean Architecture layer boundaries
- [x] Central Package Management — `Directory.Packages.props` as single source of truth for all NuGet versions

### Phase 7-8 📅 Hardening & Events
- [ ] Tenant enforcement + audit logging
- [ ] Security headers + liveness/readiness health checks
- [ ] ProblemDetails (RFC 9457) + global exception middleware
- [ ] DDD tactical patterns: aggregate root, state machine (`Order` status transitions), value objects (`Address`, `Money`), strongly-typed IDs (`OrderId`, `CustomerId`), domain invariants via `Result<T>`
- [ ] Optimistic concurrency — EF Core `RowVersion` + `ConcurrencyException` handling in command handlers
- [ ] Domain events + integration events
- [ ] Outbox pattern + background event publisher
- [ ] Inbox pattern (idempotent consumers) + event versioning
- [ ] Parallel event handler execution (`Task.WhenAll` + `AggregateException` aggregation)

### Phase 9-10 📅 Microservices & Cloud
- [ ] Module isolation: per-module project structure (Domain/Features/Infrastructure/PublicApi per module)
- [ ] PublicApi contracts (`IOrderModuleApi`, `IInventoryModuleApi`) — inter-module communication via contracts only
- [ ] Per-module DB schemas in shared database + `IModuleDatabaseMigrator` per module
- [ ] Module self-registration (`AddOrdersModule()`) + `AssemblyReference.cs` markers
- [ ] Architecture tests (NetArchTest) enforcing inter-module boundaries
- [ ] Specification pattern — composable, testable query objects per module (replaces inline LINQ in handlers)
- [ ] YARP reverse proxy + service extraction from isolated modules
- [ ] Gateway cross-cutting (CORS, rate limiting, request logging, size limits)
- [ ] SharedContracts project for inter-service event schemas + DTOs
- [ ] Docker Compose orchestration (including Redis)
- [ ] Polly v8 basics (retry, circuit breaker, timeout) from day one
- [ ] Graceful shutdown + structured concurrency
- [ ] Azure Container Apps deployment
- [ ] Azure API Management (APIM) as public gateway (Consumption tier)
- [ ] Azure Service Bus messaging backbone + DLQ handling
- [ ] Azure Event Grid for platform/infrastructure events
- [ ] Azure Functions for DLQ reprocessing (Service Bus trigger, isolated process)
- [ ] Azure Blob Storage for order attachments (invoices, receipts) + Event Grid integration
- [ ] Azure Cache for Redis (managed)
- [ ] Azure Entra ID + JWT authentication
- [ ] Blue-green + canary deployments via ACA revisions
- [ ] Cost governance (scale-to-zero, budget alerts)

### Phase 11-12 📅 Autonomy & Operations
- [ ] Database per service + data ownership
- [ ] Choreography vs Saga decision framework
- [ ] Azure Durable Functions project — orchestrator + activity functions for Saga workflows
- [ ] Database migration strategy (EF bundles + init containers)
- [ ] Performance conventions (`AsNoTracking`, indexing review, EF Core 8 `SqlQuery<T>` for complex queries, bulk operations)
- [ ] Per-service CI/CD pipelines
- [ ] Observability dashboards + SLOs
- [ ] Advanced Polly (bulkhead, fallback)
- [ ] Azure App Configuration + feature flags
- [ ] Azure AI Document Intelligence (invoice extraction from Blob Storage uploads)
- [ ] DR / Business Continuity (RTO/RPO targets, geo-replication strategy)
- [ ] Performance / Load Testing (Azure Load Testing or k6)

### Phase 13-14 📅 Maturity & CQRS
- [ ] .NET Aspire orchestration + resource definitions + service discovery
- [ ] Aspire integration tests (`DistributedApplicationTestingBuilder`)
- [ ] Cosmos DB (MongoDB API) read models + projection handlers
- [ ] Partition key strategy (`TenantId`) + autoscale RU provisioning
- [ ] Read model versioning (`_schemaVersion`) + projection lag metric
- [ ] Cosmos DB change feed awareness (alternative projection driver)
- [ ] Hangfire background jobs for projection rebuilds
- [ ] Narrow distributed-locking showcase for one Hangfire rebuild/backfill job (non-generic singleton coordination)
- [ ] Snapshot pattern — periodic aggregate snapshots for fast rebuild from event history

---

## Final Architecture State (After Phase 14)

| Capability | Implementation |
|-----------|----------------|
| **Architecture** | Clean Architecture + CQRS + Event-Driven Microservices (modular monolith → microservices extraction) |
| **Gateway** | APIM (public, north-south) + YARP (internal, east-west) with JWT validation |
| **Communication** | Azure Service Bus (async domain events) + Event Grid (platform events) + HTTP (sync queries) |
| **Write DB** | SQL Server (source of truth) per service |
| **Read DB** | Azure Cosmos DB for MongoDB API (denormalized projections, TenantId partition key) |
| **Identity** | Azure Entra ID + JWT + Managed Identity |
| **Multi-tenancy** | Enforced at every layer (API, events, DB, Cosmos DB partition key) |
| **Observability** | OpenTelemetry + App Insights + Azure Monitor dashboards |
| **Resilience** | Polly (retry, circuit breaker, timeout, bulkhead) + dead-letter queues |
| **Performance** | `AsNoTracking` convention, indexed tenant queries, EF Core 8 `SqlQuery<T>` for complex queries, bulk operations |
| **Cache** | Azure Cache for Redis (distributed cache + session state) |
| **Error Handling** | ProblemDetails (RFC 9457) + global exception middleware |
| **Domain Modeling** | DDD aggregate roots, state machines, value objects, domain invariants via `Result<T>` |
| **Module Boundaries** | Per-module PublicApi contracts, `AssemblyReference.cs` markers, NetArchTest enforcement |
| **Code Quality** | Roslyn analyzers (Roslynator, Meziantou, SonarAnalyzer) — build-time enforcement |
| **Events** | Versioned schemas (inbox + outbox) + choreography with Saga escalation + parallel dispatch |
| **Workflows** | Azure Durable Functions — orchestrator/activity pattern for Saga workflows with compensating actions |
| **Serverless** | Azure Functions for DLQ reprocessing + scheduled health checks + Durable orchestrations |
| **File Storage** | Azure Blob Storage (order attachments, private endpoint) |
| **AI / Cognitive** | Azure AI Document Intelligence (invoice data extraction) |
| **Orchestration** | .NET Aspire (local) + Azure Container Apps (cloud) |
| **CI/CD** | Per-service GitHub Actions + health check deployment gates |
| **Deployments** | Blue-green + canary via ACA revisions |

---

## Gap Analysis: Patterns Evaluated & Deferred

_Patterns from industry reference architectures evaluated against the 14-phase plan. Items below were considered and deliberately deferred or excluded — documented here so the reasoning is preserved._

| Pattern | Decision | Phase | Rationale |
|---|---:|---|---|
| Explicit `IUnitOfWork` interface | Skipped | N/A | `IAppDbContext` already exposes `SaveChangesAsync()` and DbSets — separate `IUnitOfWork` would duplicate abstraction in the monolith. |
| Repository per aggregate root | Skipped / Deferred | Phase 9 | Repositories add indirection in a monolith; useful when modules own persistence (Phase 9+). |
| Dapper for CQRS read side | Deferred | Phase 14 | Performance/read-model optimization — not needed until dedicated read stores or heavy denormalized queries. |
| `EFCore.BulkExtensions` or `ExecuteSqlInterpolated` for bulk writes | Deferred | Phase 11 | Bulk write optimizations are useful only once service-owned databases and real batch import/export scenarios exist. Premature use would bypass normal EF change tracking and complicate write-side behavior before throughput data justifies it. |
| `IConfigureNamedOptions<T>` (JWT setup) | Skipped | Phase 10 | Implementation detail applied when Entra ID/JWT is wired; not a design-level requirement. |
| Local Keycloak (IdP) | Deferred | Phase 9 | Requires Docker Compose infra; defer until local microservice orchestration exists. |
| `DelegatingHandler` for external HTTP | Deferred | Phase 9 | Relevant for inter-service `HttpClient` use; implement when services call each other. |
| Optimistic concurrency (`RowVersion`) | Added | Phase 7 | Critical for multi-tenant concurrent writes — detect and surface `ConcurrencyException` to handlers. |
| Strongly-typed IDs (`OrderId`, `CustomerId`) | Added | Phase 7 | Lightweight safety to prevent Guid parameter-swap bugs; use EF value converters for persistence. |
| SaveChangesAsync domain event dispatch (ChangeTracker) | Added | Phase 8 | Ensures domain events are only published after successful persistence (in-process or to Outbox). |
| Value Objects (Money, Address) | Covered | Phase 7 | Already planned as DDD tactical patterns. |


### Deliberately Skipped (Not Needed)

| Pattern | Why Skipped |
|---------|------------|
| **Explicit `IUnitOfWork` interface** (separate from DbContext) | `IAppDbContext` already serves this purpose — exposes `DbSet`s + `SaveChangesAsync()`. Adding a separate `IUnitOfWork` with only `SaveChangesAsync()` duplicates the abstraction without adding testability or flexibility. Both approaches are valid; this plan prefers one abstraction over two. Bookify's choice reflects MediatR conventions; our hand-rolled CQRS doesn't require it. |
| **Repository per aggregate root** (generic `Repository<T>` base) | Handlers call `_dbContext.Orders.FindAsync()` directly — adding a repository wrapper introduces indirection without value in a monolith where EF Core already provides unit-of-work + change tracking. Repositories become useful in Phase 9 (module isolation) as per-module persistence boundaries; the plan already implies them there. Adding them earlier is premature abstraction. |
| **Dapper for CQRS read side** (`ISqlConnectionFactory` + raw SQL for queries) | The read side currently targets the same SQL database with EF `AsNoTracking()` queries. Dapper's performance advantage matters at scale or with complex denormalized reads — neither applies until Phase 14 (MongoDB read models). Adding `ISqlConnectionFactory` now creates a second data-access path that must be maintained alongside EF Core with no measurable benefit. Phase 14's Cosmos DB read models achieve the CQRS read-side separation more completely. |
| **`IConfigureNamedOptions<T>`** (for JWT Bearer setup) | Clean pattern for injecting `IOptions<T>` into authentication configuration, but Phase 10 (Entra ID + JWT) is the earliest it becomes relevant. Not worth a plan bullet — will be applied as an implementation detail when JWT auth is wired. |
| **Vertical Slice Architecture (VSA)** | Feature-folder CQRS already delivers VSA's cohesion benefit — each feature's command, handler, validator, and DTO are co-located in `Features/{Domain}/`. VSA eliminates layer boundaries, which would break `NetArchTest` architecture tests (Phase 5), remove reusable pipeline behaviors (`ValidationBehavior`, `LoggingBehavior`, `CachingBehavior`), and prevent Phase 9 module isolation (can't extract `Orders.Domain` if domain logic is tangled with EF Core). Clean Architecture + feature folders = high cohesion AND low coupling; VSA trades the latter for the former. |

### Deferred to Later Phase (Will Add When Relevant)

| Pattern | Deferred To | Why Not Now |
|---------|-------------|-------------|
| **Local Identity Provider (Keycloak)** | Phase 9 (Docker Compose) | Docker Compose infrastructure doesn't exist until Phase 9. Adding Keycloak before that means managing a standalone Docker dependency just for auth testing — unnecessary when Azure Entra ID is already configured for the deployed app. Phase 9's Docker Compose is the natural home for local Keycloak alongside the other service containers. |
| **`DelegatingHandler` for external HTTP** (auto-inject auth tokens on outgoing calls) | Phase 9 (inter-service HTTP) | No inter-service HTTP calls exist until Phase 9 (YARP + microservices). The existing OpenPay adapter is a direct SDK call, not `HttpClient`. Phase 9's Polly v8 section (retry, circuit breaker, timeout) is where `HttpClientFactory` + `DelegatingHandler` patterns belong — they work together. |
| **`EFCore.BulkExtensions` or `ExecuteSqlInterpolated`** (bulk writes/imports) | Phase 11 (service-owned databases) | Bulk operations are a performance tool for true batch import/export or backfill scenarios, not a default write path. Before Phase 11, the system still centers on standard EF Core transactional writes, aggregate behavior, and normal `SaveChangesAsync()` flows. Introduce bulk writes only after service-owned databases exist and throughput measurements justify bypassing normal change tracking for specific batch workloads. |
| **Distributed locking / singleton job coordination** | Phase 14 (Hangfire rebuilds/backfills) | Not needed for normal request handling or event consumers because Inbox/Outbox idempotency and messaging semantics come first. Becomes relevant only for true singleton maintenance jobs such as projection rebuilds, backfills, or repair tasks where duplicate execution across multiple instances has real operational cost. Keep it as a single concrete example, not a shared locking framework. |
| **MCP server integration** (GitHub API, Azure CLI, DB queries via AI tooling) | Phase 9+ (microservices) | Current context infrastructure (copilot-instructions.md, 6 instruction files, 3 repo memory files, reusable prompts) covers ~90% of what MCP would provide for a monolith. MCP becomes valuable when cross-service context is needed — querying live infrastructure state across multiple ACA services, reading PR comments for multi-repo changes, or running cross-service health checks. Revisit when Docker Compose orchestration (Phase 9) or ACA deployment (Phase 10) creates the need for live external context that static memory files can't provide. |

### Already Covered (Analysis Missed It)

| Pattern | Where Covered |
|---------|---------------|
| **Value Objects** (`Money`, `Address`, etc.) | Phase 7 — DDD Tactical Patterns section |
| **Factory methods + private constructors** | Phase 7 — "`Order` entity with private constructor, `Create()` factory method returning `Result<Order>`" |
| **Entity state machine** (guard clauses returning `Result`) | Phase 7 — `Pay()`, `Ship()`, `Deliver()`, `Cancel()` each returning `Result<T>` |
| **Bogus/Faker for seed data** | Already in codebase — `Bogus` package in Infrastructure project, used for dev data seeding |
| **Domain event dispatch** | Phase 8 — Outbox pattern + automatic `SaveChangesAsync` dispatch via `ChangeTracker` |

### Added After Gap Analysis

| Pattern | Added To | Rationale |
|---------|----------|----------|
| **Optimistic concurrency** (EF `RowVersion` + `ConcurrencyException`) | Phase 7 | Genuine gap — any multi-tenant system with concurrent writes needs row versioning. Critical for Order aggregate where parallel requests (e.g., simultaneous `Pay()` and `Cancel()`) must be detected and failed safely. |
| **Strongly-typed IDs** (`OrderId`, `CustomerId` as `readonly record struct`) | Phase 7 | Eliminates `Guid` parameter-swap bugs at compile time. Lightweight pattern (one-line record struct + EF value converter) with high safety payoff. Natural companion to Value Objects. |
| **SaveChangesAsync domain event dispatch** (ChangeTracker extraction) | Phase 8 | Was implied by Outbox pattern but not explicitly documented. Made explicit: extract events from `ChangeTracker.Entries<Entity>()` after `base.SaveChangesAsync()` — ensures events only fire on successful persistence. |
| **Specification pattern** (composable query objects) | Phase 9 | Encapsulates reusable EF Core query logic (`Where`/`Include`/`OrderBy`) into named, testable specifications. Not useful in monolith (inline LINQ suffices); becomes valuable when per-module repositories need shared query definitions across handlers. |
| **Snapshot pattern** (point-in-time entity state capture) | Phase 14 | Enables fast aggregate rebuild from event history: load latest snapshot + replay recent events instead of full replay. Paired with Hangfire periodic snapshot jobs. Not needed until event volumes justify optimization. |

### Twelve-Factor App Compliance

_Every factor is already covered across the 14-phase plan — documented here for completeness._

| # | Factor | Where Covered | Status |
|---|--------|---------------|--------|
| 1 | **Codebase** — one repo, multiple deploys | GitHub repo + branch→env mapping (`dev`→dev, `staging`→staging, `main`→prod) | ✅ |
| 2 | **Dependencies** — explicitly declared | CPM (`Directory.Packages.props`), all NuGet packages versioned centrally (Phase 6) | ✅ |
| 3 | **Config** — env vars, not code | `sharedsettings.{dev,stg,prod}.json`, `ASPNETCORE_ENVIRONMENT`, Key Vault for secrets | ✅ |
| 4 | **Backing Services** — treat as attached resources | Azure SQL, Redis (Phase 6), Service Bus (Phase 10) — all via connection strings, swappable | ✅ |
| 5 | **Build, Release, Run** — strict separation | GitHub Actions: build → test → publish → deploy. 9 workflows. Docker images. | ✅ |
| 6 | **Processes** — stateless | `IDistributedCache` (Phase 6) — Redis or in-memory. No in-process session state. | ✅ |
| 7 | **Port Binding** — self-contained | Kestrel, Docker port mapping (5010–5043), ACA ingress (Phase 10) | ✅ |
| 8 | **Concurrency** — scale out via processes | ACA auto-scale + scale-to-zero (Phase 10), per-service scaling | ✅ |
| 9 | **Disposability** — fast startup, graceful shutdown | `IHostApplicationLifetime` drain pattern (Phase 9) | ✅ |
| 10 | **Dev/Prod Parity** — keep environments similar | Docker Compose mirrors prod (Phase 9), `sharedsettings` per env, same Bicep IaC all envs | ✅ |
| 11 | **Logs** — stream to stdout | Serilog Console sink (Phase 3), structured logging with `TraceId` + `TenantId` | ✅ |
| 12 | **Admin Processes** — one-off tasks as code | EF migrations (`run-database-migrations.ps1`), PowerShell bootstrap scripts, Hangfire jobs (Phase 14) | ✅ |

> All 12 factors are addressed. The plan doesn't explicitly name-drop "Twelve-Factor" as a concept, but every principle is implemented organically across Phases 1–14.

---

## References

### Documentation
- [AZURE-PROGRESS-EVALUATION.md](./AZURE-PROGRESS-EVALUATION.md) - Detailed learning plan
- [Documentation/README.md](./Documentation/README.md) - Central documentation hub
- [Documentation/04-Enterprise-Architecture/ACA-Migration-Plan.md](./Documentation/04-Enterprise-Architecture/ACA-Migration-Plan.md) - Container Apps operational runbook (13-phase)

### Azure Resources
- **Current Deployment:** https://pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net
- **Azure Portal:** https://portal.azure.com
- **Resource Group:** rg-orderprocessing-dev

### External References
- YARP Documentation: https://microsoft.github.io/reverse-proxy/
- Azure Container Apps: https://learn.microsoft.com/azure/container-apps/
- Azure API Management: https://learn.microsoft.com/azure/api-management/
- Azure Functions: https://learn.microsoft.com/azure/azure-functions/
- Azure Durable Functions: https://learn.microsoft.com/azure/azure-functions/durable/
- Azure Service Bus: https://learn.microsoft.com/azure/service-bus-messaging/
- Azure Event Grid: https://learn.microsoft.com/azure/event-grid/
- Azure Blob Storage: https://learn.microsoft.com/azure/storage/blobs/
- Azure AI Document Intelligence: https://learn.microsoft.com/azure/ai-services/document-intelligence/
- Azure Cosmos DB for MongoDB: https://learn.microsoft.com/azure/cosmos-db/mongodb/
- .NET Aspire: https://learn.microsoft.com/dotnet/aspire/
- Hangfire: https://www.hangfire.io/
- NetArchTest: https://github.com/BenMorris/NetArchTest
- Microservices Patterns: https://microservices.io/patterns/

---

## Appendix: Azure .NET Job Profile Coverage (Informative)

_This section maps the architecture plan to common Azure .NET senior role requirements. It is informative only — no actionable items._

### Coverage Scorecard

| Job Skill Area | Status | Where Covered |
|---|---|---|
| **C# / .NET Core** | ✅ Covered | .NET 8 throughout all 14 phases |
| **ASP.NET / ASP.NET Core** | ✅ Covered | API (controllers, middleware, pipeline), UI (MVC), YARP gateway |
| **Entity Framework** | ✅ Covered | EF Core, global query filters, migrations, `IAppDbContext`, DB per service (Phase 11) |
| **Azure App Services** | ✅ Covered | Baseline deployment — already running in production |
| **Azure Functions** | ✅ Covered | Phase 10 — DLQ reprocessor (Service Bus trigger), timer-triggered health checks; Phase 11 — Durable Functions orchestrations (Saga workflows) |
| **Azure Storage (Blob)** | ✅ Covered | Phase 10 — order attachments, managed identity, Event Grid integration |
| **Azure SQL Database** | ✅ Covered | Baseline → Phase 14 — source of truth, per-service DBs in Phase 11 |
| **Azure Cosmos DB (NoSQL)** | ✅ Covered | Phase 14 — MongoDB API, TenantId partition key, projections |
| **Cloud-native / Microservices** | ✅ Covered | Phases 9-14 — CQRS, event-driven, outbox/inbox, saga, scale-to-zero |
| **Scalability** | ✅ Covered | ACA auto-scale, Cosmos DB autoscale RU, canary/blue-green, Redis |
| **Integration** | ✅ Covered | Service Bus, Event Grid, Blob → Document Intelligence, OpenPay adapter |
| **CI/CD Pipelines** | ✅ Covered | GitHub Actions (9 workflows), per-service pipelines (Phase 12), OIDC deploy |
| **Git / Source Control** | ✅ Covered | GitHub repo, branch→environment mapping, PR workflows |
| **RESTful APIs** | ✅ Covered | All phases — versioned `/api/v1/`, Swagger, thin controllers |
| **Third-party API Integration** | ✅ Covered | OpenPay adapter (existing), Document Intelligence API (Phase 12) |
| **OAuth / OpenID Connect** | ✅ Covered | Phase 10 — Entra ID + JWT + OIDC (GitHub Actions already uses OIDC) |
| **Security Best Practices** | ✅ Covered | Phase 7 (headers, HSTS), Phase 10 (WAF, managed identity, private endpoints, Key Vault) |
| **Identity Management** | ✅ Covered | Entra ID, managed identity, JWT propagation, Key Vault RBAC (Phase 12) |
| **Data Encryption / Secrets** | ✅ Covered | Key Vault, private endpoints, TLS/HSTS — no plaintext credentials |
| **IaC (ARM / Bicep)** | ✅ Covered | Bicep IaC in `infra/` and `bicep/` folders (Bicep compiles to ARM) |
| **Azure Kubernetes Service (AKS)** | ⚠️ Equivalent | Plan uses **Azure Container Apps** (runs on AKS under the hood — same container concepts) |
| **Azure DevOps** | ⚠️ Equivalent | Plan uses **GitHub Actions** (identical CI/CD concepts, different tool) |

### Gap Analysis

**AKS vs ACA** — The plan uses Azure Container Apps, which is built on Kubernetes and covers ~70% of the same orchestration concepts (ingress, scaling rules, revisions, managed identity). ACA is Microsoft's recommended choice for .NET app teams that don't need custom Kubernetes operators, Helm charts, or cluster-level administration. Most Azure .NET roles accept ACA experience as equivalent.

**Azure DevOps vs GitHub Actions** — The plan uses GitHub Actions for all CI/CD. Azure DevOps pipelines use different YAML syntax but identical concepts (stages, jobs, steps, service connections, environments, approvals). The repo already has 9 workflows demonstrating advanced patterns (OIDC auth, reusable workflows, environment gates, manual dispatch). The CI/CD skill set transfers directly.

### Verdict

All technical skills from a typical Azure .NET senior role are fully covered or have strong equivalents in the plan. The two ⚠️ items (AKS, Azure DevOps) are low-risk because ACA is the modern successor to AKS for application teams, and GitHub Actions is the direct competitor to Azure DevOps Pipelines with identical concepts.

---

**Last Updated:** March 22, 2026  
**Status:** Phases 1-6 Complete ✅ | Phase 7 Next 📅 | Phases 8-14 Planned 📅
