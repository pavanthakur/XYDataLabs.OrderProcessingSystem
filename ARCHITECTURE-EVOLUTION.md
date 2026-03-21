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
- Security headers middleware:
  - `X-Content-Type-Options: nosniff`
  - `X-Frame-Options: DENY`
  - `Strict-Transport-Security` (HSTS)
- Enhanced OpenTelemetry: request duration metrics, tenant validation failure counters
- Split health checks into `/health/live` (liveness) and `/health/ready` (readiness with SQL + Redis)

### Builds On

- Phase 4 (multi-tenancy skeleton — `ITenantProvider`, EF global filters)
- Phase 6 (basic `/health` endpoint, CachingBehavior pipeline)

### Outcome

Secure, observable, tenant-enforced system ready for event-driven decoupling.

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
- **Background Publisher** — `IHostedService` that polls `OutboxMessages` and dispatches to the event bus
- **Event Dispatcher** — in-memory implementation (pluggable interface; swapped to Azure Service Bus in Phase 10)

### Rules

- Events are **immutable** value objects — never modified after creation
- Outbox writes in the **same transaction** as the domain change (no dual-write)
- Background publisher is **idempotent** — consumers must handle duplicate delivery

### Outcome

Loose coupling, async workflows, and a microservice-ready event backbone.

---

## Phase 9 — YARP Microservices Architecture (Local) 📅

**Focus:** Service decomposition + local orchestration with event-based communication.

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
│  Managed by Docker Compose (6 containers)                            │
└─────────────────────────────────────────────────────────────────────┘
```

### Solution Structure (10 Projects)

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
├── XYDataLabs.OrderProcessingSystem.UI               (Existing - Updated routing)
├── XYDataLabs.OrderProcessingSystem.Application      (Shared — temporary)
├── XYDataLabs.OrderProcessingSystem.Domain           (Shared — temporary)
├── XYDataLabs.OrderProcessingSystem.Infrastructure   (Shared — temporary)
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
```

### Communication Rules (Critical)

| Communication Type | Pattern | Example |
|--------------------|---------|---------|
| **Queries** (read) | Synchronous HTTP | UI → Gateway → Orders API `GET /api/v1/Order/{id}` |
| **Workflows** (write) | Asynchronous Events | `OrderCreated` → Event Bus → Inventory reserves stock |
| **Shared DB** | Temporary only | Will be split per service in Phase 11 |
| **Shared projects** | Temporary only | Application/Domain/Infrastructure shared until Phase 11 |

### Characteristics

✅ **Advantages:**
- Service isolation — independent deployment and scaling
- Clean URLs via YARP — no port management (`orders.localhost`, `inventory.localhost`)
- Event-driven workflows — services communicate via events, not direct HTTP calls
- Fault isolation — one service failure doesn't crash entire system
- Production pattern — same as Azure Container Apps architecture
- Service-level observability — per-service metrics and tracing

⚠️ **Challenges:**
- Increased complexity (6 containers vs 2)
- Network latency between services
- Distributed transactions complexity
- Requires resilience patterns (retries, circuit breakers)
- Docker Compose orchestration required

### Outcome

Working microservices locally with correct event-based communication model.

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
│  │  │         (Public Ingress - HTTPS + JWT validation)         │  │ │
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
└─────────────────────────────────────────────────────────────────────┘
```

### Key Deliverables

- Deploy to **Azure Container Apps** (managed environment, auto-scaling, scale-to-zero)
- **Azure Container Registry (ACR)** — build and push container images
- **Azure Service Bus** — replace in-memory event bus with durable topics + subscriptions
- **Observability** — App Insights + OpenTelemetry distributed tracing across all services
- **Secrets** — Azure Key Vault with managed identity (no credentials in config)
- **Private networking** — VNet integration, private endpoints for SQL and Key Vault

### Security

- **Identity:** Azure Entra ID (Azure AD) for authentication
- **JWT auth** — token validation at gateway, token propagation to downstream services
- **Managed Identity** — services access Key Vault and SQL without stored credentials
- **OIDC** — GitHub Actions deploys via federated credentials (existing pattern)

### Messaging Backbone

- **Azure Service Bus** replaces the in-memory event dispatcher from Phase 8
- Topics: `order-events`, `inventory-events`, `notification-events`
- Each service subscribes to relevant topics
- Dead-letter queues for failed message processing

> **Operational Detail:** See [ACA-Migration-Plan.md](./Documentation/04-Enterprise-Architecture/ACA-Migration-Plan.md) for the 13-phase operational runbook covering governance, identity hardening, ACR setup, canary deployments, and decommissioning.

### Outcome

Secure, scalable cloud-native microservices with durable messaging.

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

### Rules

- No direct database queries across service boundaries
- If Orders needs inventory status, it subscribes to `InventoryUpdated` events and maintains a local projection
- Cross-service reads use lightweight HTTP queries (via gateway) for real-time needs

### Outcome

Independent, fully decoupled services with clear data ownership boundaries.

---

## Phase 12 — Platform Engineering & DevOps 📅

**Focus:** Operational excellence and production-grade infrastructure.

### Key Deliverables

- **Central configuration** — Azure App Configuration for feature flags and shared settings
- **Secrets management** — Azure Key Vault with RBAC (migrate from access policies)
- **Resilience** — Polly v8 integration (retry, circuit breaker, timeout, bulkhead)
- **Observability dashboards** — Azure Monitor workbooks with per-service metrics, SLIs/SLOs
- **Distributed tracing** — full correlation across Service Bus messages and HTTP requests
- **Per-service CI/CD pipelines** — independent build/test/deploy per service
- **Health check gates** — deployment blocked if `/health/ready` fails post-deploy

### Outcome

Scalable, manageable production platform with enterprise-grade operations.

---

## Phase 13 — Aspire & Final Maturity 📅

**Focus:** Developer experience + system maturity with .NET Aspire.

### Key Deliverables

- Adopt **.NET Aspire** for local orchestration and service composition
- **AppHost project** — replaces Docker Compose for local development
- **Service discovery** — Aspire-managed service resolution (no hardcoded URLs)
- **Dashboard** — Aspire dashboard for local traces, logs, and metrics
- Advanced deployment patterns:
  - **Blue-green deployments** — zero-downtime with ACA revisions
  - **Canary releases** — gradual traffic shifting
- Full end-to-end trace correlation across all services
- **Aspire manifest** → ACA deployment via `azd` or Bicep

### Outcome

Enterprise-grade, cloud-native system with excellent developer inner-loop experience.

---

## Phase 14 — CQRS Read Model with NoSQL (MongoDB) 📅

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
│  │ Command  │───►│  Handler    │      │  Query   │───►│ MongoDB  │ │
│  │ (POST/   │    │ (validates, │      │  (GET)   │    │ (fast    │ │
│  │  PUT/    │    │  writes)    │      └──────────┘    │  reads)  │ │
│  │  DELETE) │    └─────┬───────┘                      └──────────┘ │
│  └──────────┘          │                                    ▲       │
│                        │                                    │       │
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

**1. Read Models (MongoDB)**
- Denormalized documents: Orders with Customer + Payment info, optimized for UI queries
- `TenantId` included in every document; query filters applied per tenant

**2. Projection Handlers**
- Consume events: `OrderCreated`, `PaymentProcessed`, `CustomerUpdated`
- Build/update denormalized MongoDB documents in near-real-time

**3. Background Jobs (Hangfire)**
- Rebuild projections on demand
- Fix inconsistencies between SQL and MongoDB
- Backfill missing data after schema changes

**4. Multi-Tenancy**
- `TenantId` field in every MongoDB document
- All read queries filtered by tenant — same pattern as EF global filters

### Rules (Critical)

- **No dual write** — never write to SQL + MongoDB in the same request
- **Always:** Write → SQL → Outbox → Event Bus → Projection → MongoDB
- **MongoDB is NOT the source of truth** — SQL Server is authoritative
- **Eventual consistency** — reads may lag behind writes by seconds

### Outcome

True CQRS with read/write separation, high-performance queries via MongoDB, scalable read layer, and eventually consistent system.

---

## Comparison Matrix

| Feature | Baseline (Monolith) | Phase 9 (YARP Local) | Phase 10 (ACA Cloud) | Phase 14 (Final State) |
|---------|--------------------|--------------------|--------------------|-----------------------|
| **Deployment** | 2 App Services | Docker Compose (6 containers) | ACA (auto-scaling) | ACA + MongoDB |
| **Communication** | In-process | Events + HTTP | Service Bus + HTTP | Service Bus + HTTP |
| **Data** | Single shared DB | Single shared DB | Single shared DB | DB per service + MongoDB |
| **Scaling** | Vertical only | Per-container | Per-service auto-scale | Per-service + read replicas |
| **Identity** | Key Vault (basic) | N/A (local) | Entra ID + JWT + MI | Entra ID + JWT + MI |
| **Observability** | App Insights | OTel + local traces | OTel + Azure Monitor | Full distributed traces |
| **Resilience** | None | Basic retry | Polly + circuit breakers | Polly + dead-letter + retry |
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
     ├── Phase 10    ─── 📅 Deploy to Azure Container Apps + Service Bus
     │
     ├── Phase 11    ─── 📅 Split databases (each service owns its data)
     │
     ├── Phase 12    ─── 📅 Platform engineering (Polly, CI/CD, dashboards)
     │
     ├── Phase 13    ─── 📅 Aspire orchestration + advanced deployments
     │
     └── Phase 14    ─── 📅 CQRS read model (MongoDB) — final architecture
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

### Phase 7-8 📅 Hardening & Events
- [ ] Tenant enforcement + audit logging
- [ ] Security headers + liveness/readiness health checks
- [ ] Domain events + integration events
- [ ] Outbox pattern + background event publisher

### Phase 9-10 📅 Microservices & Cloud
- [ ] YARP reverse proxy + service decomposition
- [ ] Docker Compose orchestration
- [ ] Azure Container Apps deployment
- [ ] Azure Service Bus messaging backbone
- [ ] Azure Entra ID + JWT authentication

### Phase 11-12 📅 Autonomy & Operations
- [ ] Database per service + data ownership
- [ ] Resilience patterns (Polly)
- [ ] Per-service CI/CD pipelines
- [ ] Observability dashboards + SLOs

### Phase 13-14 📅 Maturity & CQRS
- [ ] .NET Aspire orchestration + service discovery
- [ ] Blue-green / canary deployments
- [ ] MongoDB read models + projection handlers
- [ ] Hangfire background jobs for projection rebuilds

---

## Final Architecture State (After Phase 14)

| Capability | Implementation |
|-----------|----------------|
| **Architecture** | Clean Architecture + CQRS + Event-Driven Microservices |
| **Gateway** | YARP reverse proxy with JWT validation |
| **Communication** | Azure Service Bus (async) + HTTP (sync queries) |
| **Write DB** | SQL Server (source of truth) per service |
| **Read DB** | MongoDB (denormalized projections) |
| **Identity** | Azure Entra ID + JWT + Managed Identity |
| **Multi-tenancy** | Enforced at every layer (API, events, DB, MongoDB) |
| **Observability** | OpenTelemetry + App Insights + Azure Monitor dashboards |
| **Resilience** | Polly (retry, circuit breaker, timeout) + dead-letter queues |
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
- Azure Service Bus: https://learn.microsoft.com/azure/service-bus-messaging/
- .NET Aspire: https://learn.microsoft.com/dotnet/aspire/
- MongoDB .NET Driver: https://www.mongodb.com/docs/drivers/csharp/
- Hangfire: https://www.hangfire.io/
- Microservices Patterns: https://microservices.io/patterns/

---

**Last Updated:** March 21, 2026  
**Status:** Phases 1-6 Complete ✅ | Phase 7 Next 📅 | Phases 8-14 Planned 📅
