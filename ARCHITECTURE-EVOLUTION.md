# Architecture Evolution: Monolith to Microservices

**Last Updated:** January 26, 2026  
**Current Status:** Phase 1 Complete, Ready for Phase 2

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
├── XYDataLabs.OrderProcessingSystem.API          (Monolithic API)
│   ├── Controllers/
│   │   ├── OrderController.cs
│   │   ├── CustomerController.cs
│   │   └── InfoController.cs
│   └── Program.cs
├── XYDataLabs.OrderProcessingSystem.UI           (MVC Web App)
├── XYDataLabs.OrderProcessingSystem.Application  (Business Logic)
├── XYDataLabs.OrderProcessingSystem.Domain       (Entities)
├── XYDataLabs.OrderProcessingSystem.Infrastructure (Data Access)
├── XYDataLabs.OrderProcessingSystem.Utilities    (Shared)
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
├── XYDataLabs.OrderProcessingSystem.Utilities        (Shared)
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

**Last Updated:** January 26, 2026  
**Status:** Phase 1 Complete ✅ | Phase 2 Planned 📅 | Phase 3 Future 📅
