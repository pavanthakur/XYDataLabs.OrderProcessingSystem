# Architecture Evolution: Monolith to Microservices

**Last Updated:** March 21, 2026  
**Current Status:** Phase 1 Complete (with CQRS modernization), Ready for Phase 2

---

## 📊 Architecture Evolution Overview

This document tracks the architectural evolution of the XYDataLabs Order Processing System from a monolithic application to a microservices architecture using YARP (Yet Another Reverse Proxy).

---

## Phase 1: Monolith on Azure App Service ✅ COMPLETE

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

## Internal Architecture Modernization (6 Phases)

Independent of the Monolith → Microservices evolution above, the monolith's **internal code quality**
is being incrementally improved through 6 phases to become Aspire-ready and production-hardened.

| # | Phase | Focus | Status |
|---|-------|-------|--------|
| **1** | Structural Foundation | Utilities→SharedKernel rename, `Result<T>`, `IAppDbContext`, remove Application→Infrastructure dependency | ✅ **COMPLETE** |
| **2** | Hand-Rolled CQRS | CQRS abstractions, Dispatcher, pipeline behaviors, 12 handlers, controller refactoring, old service deletion | ✅ **COMPLETE** |
| **3** | Observability (OpenTelemetry) | `AddObservability()`, auto-instrumentation (HTTP/SQL/Runtime), App Insights + OTLP exporters, custom `ActivitySource`, correlation middleware | ✅ **COMPLETE** |
| **4** | Multi-Tenancy Skeleton | `ITenantProvider`, `TenantId` on `BaseAuditableEntity`, EF global query filters, `X-Tenant-Id` header | ✅ **COMPLETE** |
| **5** | Test Project Restructure | Split into Domain.Tests, Application.Tests, API.Tests, Integration.Tests (Testcontainers) | ✅ **COMPLETE** |
| **6** | Polish & Hardening | Redis `CachingBehavior`, API versioning `/api/v1/`, health checks, `CancellationToken`, `IOptions<T>` | 📅 Planned |

### Phase 1 — Structural Foundation ✅
- Renamed `Utilities` project → `SharedKernel` (project, .csproj refs, namespaces, .sln)
- Added `Result<T>` + `Error` types in `SharedKernel/Results/`
- Added `ApiResponse<T>` standard envelope
- Added `IAppDbContext` interface in `Application/Abstractions/`
- `OrderProcessingSystemDbContext` implements `IAppDbContext`
- Changed all services: concrete DbContext → `IAppDbContext`
- Removed Application → Infrastructure project reference
- Moved DI wiring to API composition root

### Phase 2 — Hand-Rolled CQRS ✅
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

### Phase 3 — Observability (OpenTelemetry) ✅
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

### Phase 4 — Multi-Tenancy Skeleton ✅
- `ITenantProvider` interface in `SharedKernel/Multitenancy/` (cross-cutting, avoids circular dependency)
- `TenantId` property added to both `BaseAuditableEntity` and `BaseAuditableCreateEntity` — covers all 13 entities
- EF Global Query Filters on all 13 entity `DbSet`s with `_tenantProvider == null ||` guard for design-time/test compat
- `SaveChangesAsync` override auto-stamps `TenantId` on Added entities (both base classes)
- `TenantMiddleware` extracts `X-Tenant-Id` header (default: `"default"`), stores in `HttpContext.Items`, enriches Serilog `LogContext`
- `HeaderTenantProvider` reads tenant from `HttpContext.Items` at DI scope resolution
- AppMasterData uses `.IgnoreQueryFilters()` for cross-tenant PaymentProviders
- Wired in API + UI `Program.cs` (Scoped DI, middleware before `CorrelationMiddleware`)
- Build: 0 errors, 31/31 tests passing

### Phase 5 — Test Project Restructure ✅
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

### Phase 6 — Polish & Hardening 📅
- `ICacheService` + Redis implementation
- `CachingBehavior` CQRS pipeline (queries opt in via `ICacheable`)
- API versioning: `/api/v1/[controller]`
- Health checks (SQL, Redis, external deps)
- `CancellationToken` on all handler signatures
- `TimeProvider` abstraction, `IOptions<T>` for settings
- Update required unit test project related to latest modified changes

---

## Phase 2: YARP Microservices Architecture 📅 PLANNED (Week 5-6)

### Timeline
- **Duration:** Weeks 5-6 (Days 41-56)
- **Start Date:** To be determined
- **Learning Focus:** Microservices, YARP Gateway, Service Decomposition, Docker Compose

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
│  │  • inventory.localhost   → Inventory API (NEW)                 │  │
│  │  • notifications.localhost → Notifications API (NEW)           │  │
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
│  └──────────────┘ └────────────┘ └─────────────────┘ └────────────┘│
│        │                │                  │                         │
│        └────────────────┼──────────────────┘                         │
│                         │                                            │
│              ┌──────────▼──────────┐                                 │
│              │   SQL Database      │                                 │
│              │   (Shared for now)  │                                 │
│              └─────────────────────┘                                 │
│                                                                      │
│  Managed by Docker Compose (5 containers)                            │
└─────────────────────────────────────────────────────────────────────┘
```

### Solution Structure (10 Projects Planned)

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
├── XYDataLabs.OrderProcessingSystem.Application      (Shared)
├── XYDataLabs.OrderProcessingSystem.Domain           (Shared)
├── XYDataLabs.OrderProcessingSystem.Infrastructure   (Shared)
├── XYDataLabs.OrderProcessingSystem.SharedKernel     (Shared)
└── XYDataLabs.OpenPayAdapter                         (Shared)
```

### Docker Compose Configuration

```yaml
# docker-compose.microservices.yml (Planned)
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

### Characteristics

✅ **Advantages:**
- **Service Isolation:** Independent deployment and scaling
- **Technology Freedom:** Each service can use different stack
- **Clean URLs:** No port management (orders.localhost, inventory.localhost)
- **Parallel Development:** Teams can work independently
- **Fault Isolation:** One service failure doesn't crash entire system
- **Production Pattern:** Same as Azure Container Apps architecture
- **Easier Testing:** Mock services independently
- **Better Observability:** Service-level metrics and tracing

⚠️ **Challenges:**
- Increased complexity (5 containers vs 2)
- Network latency between services
- Distributed transactions complexity
- More moving parts to monitor
- Requires resilience patterns (retries, circuit breakers)
- Docker Compose orchestration required

### Implementation Plan (Days 41-56)

| Days | Task | Deliverables |
|------|------|--------------|
| **41-42** | Setup YARP Gateway | `Gateway` project, basic routing config |
| **43-46** | Build Inventory API | `InventoryAPI` project, stock endpoints |
| **47-50** | Build Notifications API | `NotificationsAPI` project, email/SMS |
| **51-53** | Docker Compose Integration | `docker-compose.microservices.yml` |
| **54-56** | Service Communication Patterns | Polly integration, circuit breakers |

---

## Phase 3: Azure Container Apps Migration 📅 FUTURE (Week 9-10)

### Timeline
- **Duration:** Weeks 9-10 (Days 71-84)
- **Prerequisites:** Phase 2 complete, microservices architecture validated locally

### Architecture Diagram (Planned)

```
┌─────────────────────────────────────────────────────────────────────┐
│                         AZURE CLOUD                                  │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │           Azure Container Apps Environment                      │ │
│  │                                                                 │ │
│  │  ┌──────────────────────────────────────────────────────────┐  │ │
│  │  │              YARP Gateway Container App                   │  │ │
│  │  │         (Public Ingress - HTTPS enabled)                  │  │ │
│  │  └────────┬──────────┬──────────┬──────────┬────────────────┘  │ │
│  │           │          │          │          │                    │ │
│  │  ┌────────▼─────┐ ┌──▼─────────┐ ┌────────▼────────┐ ┌───▼───┐ │ │
│  │  │  Orders App  │ │Inventory   │ │ Notifications   │ │ UI    │ │ │
│  │  │              │ │   App      │ │      App        │ │  App  │ │ │
│  │  │ (Internal)   │ │(Internal)  │ │   (Internal)    │ │(Public)│ │
│  │  └──────────────┘ └────────────┘ └─────────────────┘ └───────┘ │ │
│  │         │                │                  │                    │ │
│  └─────────┼────────────────┼──────────────────┼────────────────────┘ │
│            │                │                  │                      │
│  ┌─────────▼────────────────▼──────────────────▼───────────────────┐ │
│  │                 Azure SQL Database                               │ │
│  │            (Private Endpoint - VNet Integration)                 │ │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  ┌──────────────────────┐         ┌──────────────────────┐          │
│  │  Key Vault           │         │  Application         │          │
│  │  (Private Endpoint)  │         │  Insights            │          │
│  └──────────────────────┘         └──────────────────────┘          │
│                                                                      │
│  ┌──────────────────────┐         ┌──────────────────────┐          │
│  │  Azure Container     │         │  Azure Monitor       │          │
│  │  Registry (ACR)      │         │  (Logging & Metrics) │          │
│  └──────────────────────┘         └──────────────────────┘          │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Features (Planned)

- **Auto-scaling:** Scale each service independently based on load
- **Blue-Green Deployments:** Zero-downtime deployments
- **Dapr Integration:** Service-to-service communication with Dapr runtime
- **Managed Identity:** Secure access to Key Vault and SQL Database
- **Private Endpoints:** Enhanced security (no public database access)
- **OpenTelemetry:** Distributed tracing across all services
- **Cost Optimization:** Pay per request, scale to zero when idle

---

## Comparison Matrix

| Feature | Phase 1 (Monolith) | Phase 2 (YARP Local) | Phase 3 (Container Apps) |
|---------|-------------------|---------------------|------------------------|
| **Deployment Complexity** | ⭐ Low | ⭐⭐⭐ Medium | ⭐⭐⭐⭐ High |
| **Scaling Flexibility** | ⭐⭐ Limited | ⭐⭐⭐ Good | ⭐⭐⭐⭐⭐ Excellent |
| **Development Speed** | ⭐⭐⭐⭐⭐ Fast | ⭐⭐⭐ Medium | ⭐⭐⭐ Medium |
| **Technology Freedom** | ⭐ None | ⭐⭐⭐⭐ High | ⭐⭐⭐⭐⭐ Highest |
| **Cost (Dev)** | ⭐⭐⭐⭐ Low | ⭐⭐⭐⭐⭐ Free | ⭐⭐⭐ Medium |
| **Cost (Prod)** | ⭐⭐⭐ Medium | N/A | ⭐⭐ Optimized |
| **Observability** | ⭐⭐⭐ Good | ⭐⭐⭐⭐ Very Good | ⭐⭐⭐⭐⭐ Excellent |
| **Learning Value** | ⭐⭐ Basic | ⭐⭐⭐⭐ High | ⭐⭐⭐⭐⭐ Highest |

---

## Migration Strategy

### Why Not Replace Phase 1?

**Important:** Phase 2 (YARP microservices) is a **learning exercise**, not a replacement for Phase 1.

✅ **Keep Phase 1 Running:**
- Production-ready monolith working successfully
- Azure App Service provides mature PaaS experience
- Lower operational complexity for current scale
- Existing monitoring and alerting established

✅ **Build Phase 2 Separately:**
- Learn microservices patterns without production risk
- Validate architecture locally before cloud deployment
- Understand YARP Gateway concepts
- Practice Docker Compose orchestration

✅ **Plan Phase 3 Migration:**
- Only migrate to Container Apps when:
  - Business needs independent service scaling
  - Team size supports distributed development
  - Traffic justifies the complexity
  - Learning goals achieved

### Recommended Approach

```
Phase 1 (Production) ──────────────► Continue Running
                                     │
                                     │ Keep operational
                                     ▼
Phase 2 (Learning)   ──────────────► Build in Parallel
                                     │
                                     │ Validate locally
                                     ▼
Phase 3 (Migration)  ──────────────► Deploy when ready
```

---

## Learning Objectives by Phase

### Phase 1 ✅ Achieved
- [x] Azure App Service deployment
- [x] CI/CD with GitHub Actions
- [x] Infrastructure as Code (Bicep)
- [x] Application Insights monitoring
- [x] SQL Database on Azure
- [x] Key Vault integration (partial)
- [x] Clean Architecture principles
- [x] CQRS with Result<T> pattern (internal modernization Phases 1-2)
- [x] IAppDbContext abstraction (no concrete DbContext in Application)
- [x] SharedKernel with ApiResponse<T> standard envelope

### Phase 2 📅 Next Goals
- [ ] Microservices decomposition
- [ ] YARP reverse proxy configuration
- [ ] Service-to-service communication
- [ ] Docker Compose orchestration
- [ ] Resilience patterns (Polly)
- [ ] Circuit breakers
- [ ] Health checks and monitoring

### Phase 3 📅 Future Goals
- [ ] Azure Container Apps deployment
- [ ] Azure Container Registry
- [ ] Dapr for service mesh
- [ ] Distributed tracing (OpenTelemetry)
- [ ] Auto-scaling configuration
- [ ] Blue-green deployments
- [ ] Private endpoints and VNet integration

---

## References

### Documentation
- [AZURE-PROGRESS-EVALUATION.md](./AZURE-PROGRESS-EVALUATION.md) - Detailed learning plan with YARP guide
- [Documentation/README.md](./Documentation/README.md) - Central documentation hub
- [Documentation/04-Enterprise-Architecture/ACA-Migration-Plan.md](./Documentation/04-Enterprise-Architecture/ACA-Migration-Plan.md) - Container Apps migration strategy

### Azure Resources
- **Current Deployment:** https://pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net
- **Azure Portal:** https://portal.azure.com
- **Resource Group:** rg-orderprocessing-dev

### External References
- YARP Documentation: https://microsoft.github.io/reverse-proxy/
- Azure Container Apps: https://learn.microsoft.com/azure/container-apps/
- Microservices Patterns: https://microservices.io/patterns/

---

**Last Updated:** March 21, 2026  
**Status:** Phase 1 Complete ✅ (incl. internal modernization Phases 1-2 of 6) | Phase 2 Planned 📅 | Phase 3 Future 📅
