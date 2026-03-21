# Architecture Evolution: Monolith to Enterprise Microservices

**Last Updated:** March 21, 2026  
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
- **Roslyn analyzers** — `Roslynator.Analyzers`, `Meziantou.Analyzer`, `SonarAnalyzer.CSharp` in `Directory.Packages.props`; enforces code quality, security patterns, and anti-pattern detection at build time

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
- **Domain invariants** — enforced inside aggregate methods (e.g. cannot ship an unpaid order), returning `Result<T>.Failure` with descriptive `Error` — no exceptions for business rules

### Builds On

- Phase 4 (multi-tenancy skeleton — `ITenantProvider`, EF global filters)
- Phase 6 (basic `/health` endpoint, CachingBehavior pipeline)

### Outcome

Secure, observable, tenant-enforced system with rich domain model, standardized error handling — ready for event-driven decoupling.

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

### Rules

- Events are **immutable** value objects — never modified after creation
- Outbox writes in the **same transaction** as the domain change (no dual-write)
- Background publisher is **idempotent** — Inbox table deduplicates by `MessageId` before handler execution
- **Event schema changes** must be backward-compatible (additive fields only; breaking changes = new version)
- **Parallel dispatch** — all handlers for a given event execute concurrently; failures are aggregated, not swallowed

### Outcome

Loose coupling, async workflows, idempotent delivery, parallel event handling, and a microservice-ready event backbone with versioned schemas.

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
- **Architecture tests updated** — `NetArchTest.Rules` (from Phase 5) now enforces inter-module boundaries: modules cannot reference each other's internals, only PublicApi contracts

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

### Phase 7-8 📅 Hardening & Events
- [ ] Tenant enforcement + audit logging
- [ ] Security headers + liveness/readiness health checks
- [ ] ProblemDetails (RFC 9457) + global exception middleware
- [ ] DDD tactical patterns: aggregate root, state machine (`Order` status transitions), value objects (`Address`, `Money`), domain invariants via `Result<T>`
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

**Last Updated:** March 21, 2026  
**Status:** Phases 1-6 Complete ✅ | Phase 7 Next 📅 | Phases 8-14 Planned 📅
