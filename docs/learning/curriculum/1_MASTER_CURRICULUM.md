# Azure Developer Master Curriculum - Single Source of Truth

**Your Complete Learning Journey: Azure Fundamentals → ACA Migration**  
**Start Date:** _[Your Start Date]_  
**Daily Commitment:** 1-2 hours/day  
**Total Duration:** ~12-16 weeks

---

## 🎯 WHAT'S NEXT? (Your Current Focus)

**✅ COMPLETED SO FAR (Days 1-38 + Architecture Phases 1-6):**
- ✅ Azure fundamentals (Portal, CLI, resource management)
- ✅ App Service deployment with OIDC authentication
- ✅ GitHub Actions CI/CD workflows (10 workflows: bootstrap, initial setup, deploy API/UI, infra deploy, validate, ADR validate)
- ✅ Bicep Infrastructure as Code (modules + parameters)
- ✅ Multi-environment setup (dev/staging/prod)
- ✅ Advanced CI/CD: parallel dispatch, health check retries (3×60s), bootstrap summary with endpoints table
- ✅ Azure SQL Database provisioned via Bicep, EF Core migrations applied (Days 32-33)
- ✅ DefaultAzureCredential end-to-end — Managed Identity in Azure, CLI locally (Days 35-37)
- ✅ SQL resilience baseline — EnableRetryOnFailure + Polly planning (Day 38)
- ✅ **Architecture Phases 1-6 complete:** Structural Foundation, Hand-Rolled CQRS, Observability (Serilog + OTel), Multi-Tenancy Skeleton, Test Restructure, Polish & Hardening (health checks, Redis caching, API versioning)

**🔥 YOUR NEXT 3 PRIORITIES:**

### Priority 1: Azure Data & Resilience (Days 32-56) — *enables Architecture Phases 7, 8*
**Why:** Connect your app to real Azure data services using passwordless auth — the foundation for everything that follows  
**Tasks:**
- Days 32-38: ✅ Azure SQL + EF Core + `DefaultAzureCredential` (complete)
- Days 39-43: 🔄 Polly + Health Checks + 🏗️ **Phase 7** (tenant enforcement active; audit logging in progress)
- Days 44-52: Azure Functions + Service Bus + 🏗️ **Phase 8** (Event-Driven Foundation)
- Days 53-56: Key Vault + `IOptions<T>` + Worker Services + Outbox Pattern

### Priority 2: Azure Services Deep Dive + Containers (Days 57-86) — *enables Architecture Phases 8.5, 9, 14*
**Why:** Master advanced Azure services, then containerise with confidence  
**Tasks:**
- Days 57-59: Azure Functions Advanced + 🏗️ **Phase 8.5** (Multi-Provider Payment)
- Days 60-65: Durable Functions + Serilog (✅ partial — Phase 3)
- Days 66-72: Cosmos DB + 🏗️ **Phase 14** (CQRS Read Model) + Redis (✅ Phase 6)
- Days 73-86: .NET Aspire + 🏗️ **Phase 9** (YARP Microservices) + Docker + ACR

### Priority 3: ACA + Auth + Enterprise (Days 87-112) — *enables Architecture Phases 10-13*
**Why:** Migrate to containers with full enterprise security and observability  
**Tasks:**
- Days 87-93: ACA deployment + 🏗️ **Phase 10** (Azure Container Apps)
- Days 94-98: APIM + 🏗️ **Phase 12** (Platform Engineering)
- Days 99-105: Front Door + SRE + 🏗️ **Phase 11** (Data Ownership & Autonomy)
- Days 106-112: .NET Aspire → ACA + 🏗️ **Phase 13** (Aspire & Final Maturity)

---

## 🏗️ Architecture Phases — Integrated into Curriculum

Phases 1–6 are complete. Remaining phases are interleaved into the curriculum days below.  
See `ARCHITECTURE-EVOLUTION.md` for full phase details.

| Phase | Name | Curriculum Days | Status |
|-------|------|----------------|--------|
| 1 | Structural Foundation | – | ✅ Complete |
| 2 | Hand-Rolled CQRS | – | ✅ Complete |
| 3 | Observability (OpenTelemetry) | Day 65 (auto-✅) | ✅ Complete |
| 4 | Multi-Tenancy Skeleton | – | ✅ Complete |
| 5 | Test Restructure | Day 80 (auto-✅) | ✅ Complete |
| 6 | Polish & Hardening | Days 42-43, 71-72, 94 (auto-✅) | ✅ Complete |
| 7 | Tenant Enforcement & Ops | Days 42–43 (DDD + Ops) | 🔄 In Progress |
| 8 | Event-Driven Foundation | Days 51, 55–56 | 📅 Planned |
| 8.5 | Multi-Provider Payment | Days 58–59 | 📅 Planned |
| 9 | YARP Microservices | Days 74–76, 78 | 📅 Planned |
| 10 | Azure Container Apps | Days 87–93 | 📅 Planned |
| 11 | Data Ownership & Autonomy | Days 100, 102 | 📅 Planned |
| 12 | Platform Engineering | Days 95, 97 | 📅 Planned |
| 13 | Aspire & Final Maturity | Days 106–109 | 📅 Planned |
| 14 | CQRS Read Model (Cosmos DB) | Days 67–68, 70 | 📅 Planned |

### Azure Service Coverage (Jan 2026 analysis snapshot)

Rationale for this coverage model: `docs/architecture/decisions/ADR-014-azure-service-coverage-rationale.md`

| Service | Status | Curriculum Days |
|---------|--------|-----------------|
| App Service / Container Apps | ✅ Excellent | Week 1-4, 11 |
| Key Vault | ✅ Excellent | Week 4, 13 |
| Azure Functions | ✅ Good | Week 7 |
| Service Bus / Queues | ⚠️ Partial | Week 7 (add Storage Queues) |
| Azure SQL Database | ✅ Excellent | Week 4 |
| Cosmos DB (NoSQL) | ✅ Added | Week 8 (Days 66-70) |
| API Management (APIM) | ✅ Added | Week 14 (Days 94-101) |

---

## 📝 TODAY'S STEP-BY-STEP GUIDE

**Operational guide has been moved to:**  
📄 `docs/guides/deployment/azure-deployment-guide.md`

The complete step-by-step deployment guide is now maintained in the Azure Deployment Guide for easier regular access. This includes:
- Task 1: Read workflow documentation
- Task 2: Run dry run test (with detailed steps)
- Task 3: Analyze what-if output
- Task 4: Real deployment (optional)
- Task 5: Document your experience

**Quick link:** See `../../guides/deployment/azure-deployment-guide.md` for the step-by-step manual infrastructure deployment guide.

**Verification:**
```powershell
# Check resources via CLI
az resource list -g rg-orderprocessing-dev -o table

# Test API endpoint
curl https://pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net

# Test UI endpoint
curl https://pavanthakur-orderprocessing-ui-xyapp-dev.azurewebsites.net
```

### ✅ Task 5: Document Your Experience (10 mins)
**Create note with:**
- ✅ What worked?
- ❌ What failed? (if anything)
- 🤔 What was confusing?
- 💡 What did you learn?
- 📝 Screenshots of workflow run

**Save to:** Personal learning journal

---

## 🎓 Learning Outcomes from Today

After completing today's tasks, you will have:
1. ✅ Hands-on experience with GitHub Actions manual workflows
2. ✅ Understanding of Azure what-if analysis
3. ✅ Ability to deploy infrastructure on-demand
4. ✅ Knowledge of parameter-driven deployments
5. ✅ Confidence in multi-environment setup

**This prepares you for:**
- Future infrastructure updates
- Environment-specific deployments
- Testing infrastructure changes safely
- Container infrastructure (ACR, ACA) in Weeks 10-11

---

## 📚 Document Navigation

**This is your ONE source of truth.** Track all progress here.

### Primary Learning Documents
1. **This Document (MASTER_CURRICULUM.md)** - Your daily tracker and curriculum overview (all foundational Azure concepts are inline below)
2. **[ACA Migration Plan](../../guides/deployment/aca-migration-plan.md)** - Enterprise migration roadmap (17 phases)
3. **[Containerization Learning Path](../reference/containerization-aca-aspire-learning-path.md)** - Hands-on Docker, ACR, ACA (8 modules)
4. **[Quick Command Reference](../../reference/quick-command-reference.md)** - All essential commands: Git, Azure CLI, Azure SQL, EF Core, Docker, GitHub App, troubleshooting

---

## 🎯 Learning Path Overview

### Phase 1: Azure Fundamentals (Weeks 1-4)
**Source:** Inline curriculum (Days 1-14)  
**Focus:** Core Azure concepts, CLI, Portal, basic deployments

### Phase 2: Enterprise App Service Deployment (Weeks 5-8)
**Source:** Inline curriculum (Days 15-28) + `docs/guides/deployment/azure-deployment-guide.md`  
**Focus:** OIDC, CI/CD, App Service, Bicep basics

### Phase 3: Container & ACA Transition (Weeks 9-16)
**Source:** `docs/learning/reference/containerization-aca-aspire-learning-path.md` + `docs/guides/deployment/aca-migration-plan.md`  
**Focus:** Docker, ACR, ACA, enterprise security, observability

---

## 📅 Daily Progress Tracker

### ✅ Weeks 1-2: Azure Fundamentals (Days 1-14) — Complete

#### Day 1: Azure Portal & Resource Groups ✅
- [x] Read Azure Portal overview
- [x] Create first resource group via Portal
- [x] Explore Portal navigation and dashboards
- [x] **Time:** 1 hour | **Completed:** ✅ Done

#### Day 2: Azure CLI Basics ✅
- [x] Verify Azure CLI installation (`az --version`)
- [x] Login: `az login`
- [x] List subscriptions: `az account list`
- [x] Create RG via CLI: `az group create`
- [x] **Time:** 1 hour | **Completed:** ✅ Done

#### Day 3: Resource Tagging & Organization ✅
- [x] Learn tagging strategy (env, app, owner)
- [x] Apply tags to existing resources
- [x] Query resources by tags
- [x] **Time:** 1 hour | **Completed:** ✅ Done

#### Day 4: Azure Storage Accounts ✅
- [x] Create storage account via Portal
- [x] Upload blob, create container
- [x] Generate SAS token, test access
- [x] **Time:** 1 hour | **Completed:** ✅ Done

#### Day 5: Virtual Networks Basics ✅
- [x] Create VNet with subnets
- [x] Understand address spaces, NSGs
- [x] Deploy VM in VNet (optional)
- [x] **Time:** 1.5 hours | **Completed:** ✅ Done

#### Day 6: Azure Monitor & Application Insights ✅
- [x] Enable App Insights on sample app
- [x] View metrics, logs, traces
- [x] Set up basic alert rule
- [x] **Time:** 1 hour | **Completed:** ✅ Done

#### Day 7: Review & Weekend Lab ✅
- [x] Complete Week 1-2 exercises
- [x] Deploy end-to-end test environment
- [x] Document learnings in personal notes
- [x] **Time:** 2-3 hours | **Completed:** ✅ Done

*(Days 8-14: continue Azure fundamentals — ARM templates, cost analysis, governance basics, IaC principles)*

---

### ✅ Weeks 3-4: App Service & OIDC Deployment (Days 15-28) — Complete

#### Day 15: App Service Plans Overview ✅
- [x] Understand SKUs (Free, Basic, Standard, Premium)
- [x] Create App Service Plan (F1 for dev)
- [x] Deploy sample .NET 8 app
- [x] **Time:** 1 hour | **Completed:** ✅ Done

#### Day 16: GitHub Actions Basics ✅
- [x] Create `.github/workflows` directory
- [x] Write first workflow (hello-world)
- [x] Trigger workflow on push
- [x] **Time:** 1 hour | **Completed:** ✅ Done

#### Day 17: OIDC Setup (Part 1) ✅
**Reference:** `docs/guides/deployment/azure-deployment-guide.md`
- [x] Run `setup-github-oidc.ps1` script
- [x] Create App Registration in Entra ID
- [x] Add federated credentials for the default branch policy (`dev`/`staging`/`main`)
- [x] **Time:** 1.5 hours | **Completed:** ✅ Done

#### Day 18: OIDC Setup (Part 2) & GitHub Secrets ✅
- [x] Assign Contributor role to Service Principal
- [x] Add secrets to GitHub (CLIENTID, TENANTID, SUBSCRIPTIONID)
- [x] Test OIDC login in workflow
- [x] **Time:** 1.5 hours | **Completed:** ✅ Done

#### Day 19: Deploy API to App Service ✅
- [x] Create workflow for API deployment
- [x] Build .NET project in CI
- [x] Deploy to App Service (staging slot)
- [x] **Time:** 2 hours | **Completed:** ✅ Done

#### Day 20: Deploy UI to App Service ✅
- [x] Create UI deployment workflow
- [x] Configure environment variables for API URL
- [x] Test end-to-end flow
- [x] **Time:** 2 hours | **Completed:** ✅ Done

#### Day 21: Bicep Basics ✅
- [x] Install Bicep CLI
- [x] Write first Bicep file (storage account)
- [x] Deploy via `az deployment group create`
- [x] **Time:** 1.5 hours | **Completed:** ✅ Done

#### Day 22-28: Complete App Service Module
*(Days 22-28: advanced App Service — deployment slots, scaling, monitoring, diagnostics)*

---

### ✅ Weeks 5-8: IaC, CI/CD + Azure SQL Baseline (Days 29-34) — [Implementation Notes](../implementation-notes/implementation-notes-days-29-38.md)
**Reference:** `infra/` folder + `docs/guides/deployment/azure-deployment-guide.md`

#### Day 29: Bicep Modules ✅
- [x] Understand module structure
- [x] Create reusable App Service module
- [x] Reference module from main.bicep
- [x] **Time:** 1.5 hours | **Completed:** ✅ Done

#### Day 30: Parameter Files ✅
- [x] Create `dev.json`, `staging.json`, `prod.json`
- [x] Parameterize environment-specific values
- [x] Deploy to multiple environments
- [x] **Time:** 1 hour | **Completed:** ✅ Done

#### Day 31: GitHub Actions - Infra Deployment ✅ (Extended)
**Reference:** `.github/workflows/infra-deploy.yml` + `README-INFRA-DEPLOY.md` + `docs/guides/deployment/azure-deployment-guide.md` (Manual workflow trigger & dry run parameters section)
- [x] Add what-if step for PR reviews
- [x] Implement GitHub Actions infra deployment across dev/staging/prod environments
- [x] Validate deployments
- [x] **Enhanced:** Added workflow_dispatch for manual runs
- [x] **Enhanced:** Interactive parameter selection via GitHub UI
- [x] **Enhanced:** Dry run mode for safe testing
- [x] **Time:** 2 hours | **Completed:** ✅

#### Day 32: Azure SQL Database — Provision via Bicep ✅
- [x] Create `infra/modules/sql.bicep` (SQL Server + database)
- [x] Add SQL module to `infra/main.bicep` with firewall rules
- [x] Deploy via `az deployment sub create` — `orderprocessing-sql-dev` + `OrderProcessingSystem_Dev` live in Azure Portal
- [x] Verify database in Azure Portal ✅ confirmed in `rg-orderprocessing-dev`
- [x] **Time:** 1.5 hours | **Completed:** ✅

#### Day 33: EF Core Migrations Against Azure SQL ✅
- [x] Configure EF Core connection string for Azure SQL
- [x] Run `dotnet ef migrations add InitialCreate`
- [x] Apply migrations: `dotnet ef database update` — all 6 migrations applied to `OrderProcessingSystem_Dev`
- [x] Seed test data and verify via Azure Portal Data Explorer — 120 Customers, 13 tables confirmed
- [x] **Time:** 1.5 hours | **Completed:** ✅

#### Day 34: Environment-Specific SQL Configuration + Copilot Infrastructure ✅
- [x] Configure SQL connection strings in `Resources/Configuration/sharedsettings.{dev,staging,prod}.json`
- [x] Enable SQL logging in development (`LogTo`, `EnableSensitiveDataLogging`, `EnableDetailedErrors` gated by `Observability:EnableEfSensitiveDataLogging` config flag in `ObservabilityOptions`)
- [x] Set up `.github/instructions/` skill files (ef-migrations, azure-workflows, bicep, curriculum, architecture)
- [x] Created `docs/architecture/decisions/` ADR framework (ADR-000 template + ADR-001 to ADR-005)
- [x] Created `/memories/architect-patterns.md` — career-wide Azure/.NET/Angular/Docker patterns
- [x] Created `/memories/repo/azure-resources.md` and `dotnet-conventions.md`
- [x] Created `.github/prompts/day-complete.prompt.md` — auto-routing agent prompt
- [x] Test connection from App Service in Azure Portal — verified via Swagger (`GetAllCustomersByName` returned data) + local EF Core SQL logs confirmed
- [x] **Time:** 4 hours | **Completed:** ✅ 20/03/2026

---

### Week 5-8 (continued): Azure Data & Resilience (Days 35-56)

#### Day 35: SQL Security — Enable Managed Identity
- [x] Enable system-assigned managed identity on App Service
- [x] Create SQL contained user: `CREATE USER [<app-service-name>] FROM EXTERNAL PROVIDER`
- [x] Grant roles: `ALTER ROLE db_datareader ADD MEMBER [<app-service-name>]`, `ALTER ROLE db_datawriter ADD MEMBER [<app-service-name>]`, `ALTER ROLE db_ddladmin ADD MEMBER [<app-service-name>]`
- [x] Verify passwordless connection from Azure App Service logs
- [x] **Time:** 1.5 hours | **Completed:** 2026-03-20

#### Day 36: 🆕 DefaultAzureCredential in C# (Azure-first .NET)
> **Why now:** First time C# code connects to Azure without any stored password or secret
- [x] Add `Azure.Identity` NuGet package
- [x] Replace SQL password auth with access token via `DefaultAzureCredential`
- [x] Understand credential chain: `EnvironmentCredential → ManagedIdentityCredential → VisualStudioCredential → AzureCliCredential`
- [x] Test locally: `az login` → CLI credential picked up automatically
- [x] Test in Azure: Managed Identity credential used automatically
- [x] **Time:** 2 hours | **Completed:** 2026-03-20

#### Day 37: Connect API to Azure SQL — Passwordless End-to-End
- [x] Update `DbContext` to supply `DefaultAzureCredential` access token for Azure SQL
- [x] Verify Azure SQL access is passwordless (`Authentication=Active Directory Default`); local/Docker fallback configs retain placeholder admin credentials for break-glass tooling only
- [x] Deploy updated API and confirm successful connection in Application Insights
- [x] **Time:** 2 hours | **Completed:** 2026-03-20

#### Day 38: Azure SQL — Resilience Baseline
- [x] Test what happens when SQL is briefly unavailable (stop/start via Portal)
- [x] Observe EF Core default retry (`EnableRetryOnFailure`)
- [x] Document failure modes and plan Polly layering (Day 39)
- [x] **Time:** 1 hour | **Completed:** 2026-03-20

#### Day 39: 🆕 Polly — Retry & Circuit Breaker (Azure-first .NET)
> **Why now:** Azure SQL + downstream services fail transiently — structured retries are essential
- [ ] Add `Microsoft.Extensions.Http.Polly` NuGet package
- [ ] Configure `IHttpClientFactory` with Polly retry policy (3 retries, exponential backoff with jitter)
- [ ] Add circuit breaker policy (5 consecutive failures → open for 30 seconds)
- [ ] Test: simulate transient failure and observe retry behaviour in logs
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 40: Polly — Timeout & Fallback Policies
- [ ] Add timeout policy (10 seconds for external HTTP calls)
- [ ] Add fallback policy (return cached/default data when all retries exhausted)
- [ ] Combine policies with `PolicyWrap`
- [ ] Log retry attempts to Application Insights as custom events
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 41: Resilience Testing in Azure
- [ ] Use Azure Portal → App Service → "Stop" to simulate downstream failure
- [ ] Observe Polly circuit breaker opening after threshold
- [ ] Observe automatic recovery when service resumes
- [ ] Document resilience patterns for interview readiness
- [ ] **Time:** 1.5 hours | **Completed:** ___/___/___

#### Day 42: 🆕 ASP.NET Core Health Checks (Azure-first .NET) ✅ *(Delivered by Architecture Phase 6)*
> **Why now:** Required for App Service health probe verification and ACA readiness probes later
>
> ✅ `/health` with SQL check implemented during Architecture Phase 6 (Polish & Hardening)
>
> 🏗️ **Architecture Phase 7a** — Extend this day: `TenantValidationBehavior`, ProblemDetails RFC 9457, global exception middleware
> 
> **Status:** ✅ Implemented in code and covered by focused unit/integration tests.
>
> **DDD Tactical Patterns (Phase 7 — part 1):**
> 
> **Status:** ✅ `Order` aggregate now uses a private constructor, `Create()` factory, and explicit `Created → Paid → Shipped → Delivered → Cancelled` transitions backed by a domain-local result primitive.
>
> **DDD Tactical Patterns (Phase 7 — part 1):**
> - Aggregate root — `Order` with private constructor, `Create()` factory method returning a domain-local result
> - State machine — `Order.Pay()`, `Ship()`, `Deliver()`, `Cancel()` with explicit transition methods
> - Value objects — `Address` and `Money` as immutable `record` types with self-validation
> - Domain invariants enforced inside aggregate methods (e.g. cannot ship an unpaid order), returning `Result<T>.Failure` — never exceptions for business rules
> - Aggregate boundary rule — aggregates enforce only their own transactional invariants; no injected infrastructure services
- [x] Add `Microsoft.Extensions.Diagnostics.HealthChecks.EntityFrameworkCore` NuGet package
- [x] Register health checks: `AddHealthChecks().AddDbContextCheck<AppDbContext>()`
- [x] Map endpoints: `app.MapHealthChecks("/health")` (liveness) and `/health/ready` (readiness + DB check)
- [x] **Time:** 1.5 hours | **Completed:** ✅ (Phase 6)

#### Day 43: Health Checks — Azure Integration ✅ *(Delivered by Architecture Phase 6)*
> 🏗️ **Architecture Phase 7b** — Extend this day: Security headers middleware, `AuditLog` table, split `/health/live` + `/health/ready`, enhanced OTel metrics
> 
> **Status:** 🔄 Security headers, `AuditLog` table, query/API surface, migration, and tenant-isolation tests are implemented; enhanced OTel metrics remain pending.
>
> **DDD Tactical Patterns (Phase 7 — part 2):**
> - Strongly-typed IDs — `OrderId`, `CustomerId`, `ProductId` as `readonly record struct` wrappers around `Guid` + EF Core value converters for transparent persistence
> - Optimistic concurrency — `RowVersion` (`byte[]` / `[Timestamp]`) is implemented on `Order`; broader rollout remains pending
> - Architecture tests updated for DDD invariant enforcement (NetArchTest)
> - `X-Tenant-Code` header rename — earlier phases used `X-Tenant-Id`; Phase 7 adopts the canonical `X-Tenant-Code` per `ARCHITECTURE.md` §3/§14
- [x] Configure App Service health check probe to use `/health` endpoint
- [ ] Add custom health check for Service Bus connectivity
- [x] View health status in Azure Portal → App Service → Health Check
- [x] **Time:** 1 hour | **Completed:** ✅ (Phase 6, Service Bus check deferred to Day 50)

#### Day 44: Azure Functions — HTTP Trigger
- [ ] Create first HTTP-triggered Function (order processing trigger)
- [ ] Deploy Function App to Azure via Bicep
- [ ] Monitor invocations with Application Insights
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 45: Azure Functions — Timer Trigger & Output Bindings
- [ ] Create Timer-triggered Function (scheduled order cleanup)
- [ ] Use output binding to write to Azure SQL
- [ ] Test locally with Azure Functions Core Tools
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 46: Azure Functions — Deployment & OIDC
- [ ] Create GitHub Actions workflow for Function App deployment
- [ ] Use OIDC login (same pattern as App Service)
- [ ] Configure Function App settings via Bicep
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 47: Azure Functions — Monitoring & Cold Start
- [ ] View Function invocations in Application Insights
- [ ] Understand cold start in Consumption plan
- [ ] Compare Consumption vs Premium plan (always-on)
- [ ] **Time:** 1.5 hours | **Completed:** ___/___/___

#### Day 48: Azure Service Bus — Namespace, Topics & Subscriptions
- [ ] Create Service Bus namespace (Standard tier) via Bicep
- [ ] Create Topic `order-events` with Subscriptions: `inventory-sub`, `notifications-sub`
- [ ] Grant Managed Identity `Azure Service Bus Data Sender` role on namespace
- [ ] Grant Managed Identity `Azure Service Bus Data Receiver` role for each subscription
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 49: 🆕 Microservice Pub/Sub in C# via Service Bus (Azure-first .NET)
> **Why now:** Real service-to-service decoupling — replace direct HTTP calls between microservices
- [ ] Add `Azure.Messaging.ServiceBus` NuGet package
- [ ] **Orders API (Publisher):** Use `ServiceBusClient` + `ServiceBusSender` with `DefaultAzureCredential` to publish `OrderPlacedEvent` to `order-events` Topic
- [ ] **Inventory API (Subscriber):** Use `ServiceBusProcessor` on `inventory-sub` to consume events
- [ ] **Notifications API (Subscriber):** Use `ServiceBusProcessor` on `notifications-sub`
- [ ] All three use `DefaultAzureCredential` — no connection strings in code
- [ ] Test end-to-end: place order → both APIs receive event independently
- [ ] **Time:** 3 hours | **Completed:** ___/___/___

#### Day 50: Service Bus — Dead Letter, Retry & Monitoring
- [ ] Implement dead-letter queue handling for failed messages
- [ ] Configure max delivery count (3 retries before dead-lettering)
- [ ] Monitor message counts (active, dead-lettered) in Azure Portal
- [ ] Verify end-to-end: order placed → Inventory updated + Notification sent
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 51: Event Grid — Reactive Architecture
> 🏗️ **Architecture Phase 8a** — Replace Event Grid with: Domain events + integration events architecture. Design `IDomainEvent`, `IIntegrationEvent` interfaces and event dispatcher.
>
> **Additional Phase 8 deliverables for this day:**
> - Inbox Pattern — `InboxMessages` table for idempotent consumers (deduplication by `MessageId` before processing)
> - Event Versioning — envelope with `SchemaVersion` field; convention: `OrderCreatedV1` → `OrderCreatedV2` with backward-compatible projection
- [ ] Create Event Grid Topic for Azure resource events
- [ ] Subscribe Azure Function to Event Grid events (blob upload → process)
- [ ] Compare: Service Bus (command/guaranteed delivery) vs Event Grid (system events/push)
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 52: Decision Matrix — Event Grid vs Service Bus vs Storage Queue
- [ ] Document architectural decision matrix with real examples from OrderProcessingSystem
- [ ] Understand when to use each service for the order processing scenarios
- [ ] **Time:** 1 hour | **Completed:** ___/___/___

#### Day 53: Azure Key Vault + Azure App Configuration
- [ ] Add additional secrets to existing Key Vault (API keys, feature flags)
- [ ] Provision Azure App Configuration store via Bicep
- [ ] Store feature flags and non-secret configuration in App Configuration
- [ ] **Time:** 1.5 hours | **Completed:** ___/___/___

#### Day 54: 🆕 IOptions\<T\> — Bind Secrets & Config in C# (Azure-first .NET)
> **Why now:** Key Vault and App Configuration are useless without strongly-typed C# classes to consume them
- [ ] Add `Azure.Extensions.AspNetCore.Configuration.Secrets` (Key Vault config provider)
- [ ] Add `Microsoft.Extensions.Configuration.AzureAppConfiguration` NuGet package
- [ ] Register both providers in `Program.cs` using `DefaultAzureCredential`
- [ ] Create `OrderSettings`, `ServiceBusSettings`, `DatabaseSettings` option classes
- [ ] Bind via `services.Configure<OrderSettings>(configuration.GetSection("Orders"))`
- [ ] Inject `IOptions<OrderSettings>` in services — no raw `IConfiguration` in business logic
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 55: 🆕 Worker Services + BackgroundService on Azure (Azure-first .NET)
> **Why now:** Long-running background polling from Service Bus needs a hosted Worker Service
>
> 🏗️ **Architecture Phase 8c** — Combine Worker Service with Outbox pattern: background worker reads `OutboxMessage` rows and publishes to Service Bus
>
> **Additional Phase 8 deliverables for this day:**
> - Automatic domain event dispatch — `SaveChangesAsync` override extracts `IDomainEvent`s from `ChangeTracker.Entries<Entity>()` after `base.SaveChangesAsync()` succeeds; events written to Outbox in same transaction
> - Parallel event handler execution — `EventPublisher` dispatches all `IEventHandler<T>` via `Task.WhenAll`; partial failures collected into `AggregateException`
- [ ] Create `XYDataLabs.OrderProcessingSystem.Worker` project (Worker Service template)
- [ ] Implement `BackgroundService` that processes order events via `ServiceBusProcessor`
- [ ] Register as `IHostedService` in DI
- [ ] Deploy as a separate Azure App Service (Worker)
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 56: 🆕 Outbox Pattern — Reliable Messaging (Azure-first .NET)
> **Why now:** Without Outbox, a DB write can succeed but the Service Bus publish can silently fail — losing the event
>
> 🏗️ **Architecture Phase 8d** — Test Outbox reliability: simulate Service Bus downtime → order saved → event delivered later when bus recovers
>
> **Phase 8 design rules:**
> - Events are immutable value objects — never modified after creation
> - Schema changes must be backward-compatible (additive fields only; breaking changes = new version)
> - Outbox writes in the same transaction as the domain change (no dual-write)
> - Background publisher is idempotent — Inbox table deduplicates by `MessageId` before handler execution
- [ ] Add `OutboxMessage` table to SQL database via EF migration
- [ ] In `PlaceOrder` handler: write to `Orders` + `OutboxMessage` in a single SQL transaction
- [ ] Create background worker that reads `OutboxMessage` rows, publishes to Service Bus, marks as processed
- [ ] Test: simulate Service Bus downtime — order saved, event delivered later when bus recovers
- [ ] **Time:** 3 hours | **Completed:** ___/___/___

---

### Week 9: Azure Functions Advanced & Event-Driven Architecture (Days 57-64)
> **Note:** Azure Functions basics (HTTP trigger, Timer trigger, OIDC deployment) are covered in Days 44-47. Days 57-64 build on the Service Bus work from Days 48-50 with advanced patterns.

#### Day 57: Queue-Triggered Azure Functions (Advanced Patterns)
- [ ] Create Queue-triggered Azure Function building on Day 48 Service Bus setup
- [ ] Handle poison messages with retry logic and dead-letter
- [ ] Monitor queue metrics in Application Insights
- [ ] Test at-least-once delivery semantics
- [ ] Implement dead-letter queue handling
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 58: 🆕 Azure Storage Queues vs Service Bus
> 🏗️ **Architecture Phase 8.5a** — Replace Storage Queues comparison with: Stripe adapter (second payment provider alongside OpenPay), per-tenant provider selection via `ITenantPaymentResolver`
- [ ] Create Storage Account with Queue service
- [ ] Implement queue producer (add messages)
- [ ] Implement queue consumer (process messages)
- [ ] Compare Storage Queues vs Service Bus features
- [ ] Understand when to use each service
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 59: 🆕 Queue-Triggered Functions
> 🏗️ **Architecture Phase 8.5b** — Replace with: `HttpClient`-based resilience with `IHttpClientFactory` + Polly policies for payment calls, idempotency keys for payment retries
- [ ] Create Queue-triggered Azure Function
- [ ] Handle poison messages with retry logic
- [ ] Monitor queue metrics in Application Insights
- [ ] Test at-least-once delivery semantics
- [ ] Implement dead-letter queue handling
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 60: Service Bus — Advanced Patterns (Sessions, Transactions, Deduplication)
> **Note:** Service Bus namespace creation and pub/sub between microservices was covered in Days 48-50. This day focuses on advanced patterns.
- [ ] Implement message sessions for ordered per-customer processing via `ServiceBusSessionProcessor`
- [ ] Use `ServiceBusReceiver` with `ReceiveMode.PeekLock` for transactional processing
- [ ] Test message deduplication using message ID
- [ ] Implement Service Bus-triggered Azure Function for order processing
- [ ] Document when to use sessions vs standard queues
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 61: Event Grid vs Service Bus (Interview Critical)
- [ ] Create Event Grid Topic
- [ ] Subscribe Azure Function to Event Grid events
- [ ] Publish order events to Event Grid (webhook push)
- [ ] Compare: Service Bus Queue vs Event Grid Topic
- [ ] Understand when to use each (commands vs events)
- [ ] Implement Azure Storage Blob trigger (Event Grid integration)
- [ ] Document architectural decision matrix
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 62-64: Azure Functions Advanced
- [ ] Implement Durable Functions for long-running workflows
- [ ] Call Inventory API from Functions (service-to-service)
- [ ] Trigger Notifications API from Functions
- [ ] Implement saga pattern with Durable Functions
- [ ] Test orchestration with approvals and timeouts
- [ ] **Time:** 6 hours (3 days × 2 hours) | **Completed:** ___/___/___

---

### Week 10: 🆕 Serilog + Cosmos DB + Redis (Days 65-72)
**Reference:** See *Azure Service Coverage* table above

#### Day 65: 🆕 Serilog Structured Logging (Azure-first .NET) ✅ *(Delivered by Architecture Phase 3)*
> **Why now:** Unstructured logs are unreadable in Docker and ACA containers — Serilog must be in place before containerising
>
> ✅ Serilog + Console/File/AppInsights sinks implemented during Architecture Phase 3. Remaining enrichers (`WithCorrelationId`) to be added.
- [x] Add `Serilog.AspNetCore`, `Serilog.Sinks.ApplicationInsights`, `Serilog.Enrichers.Environment` NuGet packages
- [x] Replace default logging with Serilog in `Program.cs` using `UseSerilog()`
- [x] Configure sinks: Console (structured JSON) + Application Insights
- [ ] Add enrichers: `WithMachineName()`, `WithEnvironmentName()`, `WithCorrelationId()`
- [x] Use structured properties (not string interpolation): `Log.Information("Order {OrderId} placed for {CustomerId}", orderId, customerId)`
- [ ] Verify correlation IDs flow across service calls in App Insights
- [ ] **Time:** 2 hours | **Completed:** ✅ (Phase 3 — enrichers + correlation IDs pending)

#### Day 66: Cosmos DB Fundamentals + SDK Integration (with DefaultAzureCredential)
- [ ] Provision Cosmos DB account (Core SQL API) via Bicep
- [ ] Create database and container with appropriate partition key
- [ ] Understand partition keys and Request Units (RUs)
- [ ] Insert first document via Azure Portal, query with Data Explorer
- [ ] Add `Microsoft.Azure.Cosmos` NuGet package
- [ ] Connect using `DefaultAzureCredential` (no connection strings)
- [ ] Create repository pattern for Cosmos DB
- [ ] Implement CRUD operations (Create, Read, Update, Delete)
- [ ] Query with LINQ and SQL syntax, handle partition key in operations
- [ ] **Time:** 3 hours | **Completed:** ___/___/___

#### Day 67: Product Catalog Microservice
> 🏗️ **Architecture Phase 14a** — CQRS read model design: projection handlers, Cosmos DB as read store for denormalized order views
>
> **Phase 14 background infrastructure:**
> - Hangfire background jobs — rebuild projections on demand, fix SQL↔Cosmos inconsistencies, backfill missing data after schema changes
> - Distributed locking (job-specific) — optional singleton coordination for projection rebuild jobs when duplicate execution would create operational inconsistency
- [ ] Create new project: `XYDataLabs.OrderProcessingSystem.ProductCatalogAPI`
- [ ] Use Cosmos DB for product storage
- [ ] Implement search and filtering endpoints
- [ ] Add pagination for large result sets
- [ ] Add to YARP Gateway routing (`products.localhost`)
- [ ] **Time:** 3 hours | **Completed:** ___/___/___

#### Day 68: Cosmos DB Performance Optimization
> 🏗️ **Architecture Phase 14b** — Implement MongoDB/Cosmos read projections for Orders (denormalized documents), tenant-scoped read models
>
> **Read model versioning:**
> - `_schemaVersion` integer field per Cosmos DB document — projection handlers write current version; older documents coexist with newer ones
> - Backward-compatible projections — query code handles missing fields with sensible defaults
> - On major schema change, Hangfire job rebuilds projection from event history, bumping `_schemaVersion`
- [ ] Optimize queries with partition keys
- [ ] Implement indexing policies
- [ ] Use change feed for event-driven patterns
- [ ] Monitor RU consumption and optimize
- [ ] Implement caching strategy
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 69: Multi-Region & Consistency Levels
- [ ] Configure geo-replication (secondary region)
- [ ] Understand 5 consistency levels (Strong, Bounded Staleness, Session, Consistent Prefix, Eventual)
- [ ] Test failover scenarios
- [ ] Compare costs vs benefits of multi-region
- [ ] Implement conflict resolution
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 70: Cosmos DB + Functions Integration
> 🏗️ **Architecture Phase 14c** — Change feed → read model sync, tenant-scoped documents, eventual consistency verification
>
> **Projection observability:**
> - Projection lag metric — OTel gauge tracking seconds between last SQL write and corresponding Cosmos DB update; alert if > threshold
> - `TenantId` as partition key in every Cosmos DB document — same tenant isolation pattern as EF global filters
- [ ] Create Cosmos DB-triggered Azure Function
- [ ] Process change feed events
- [ ] Sync data between SQL and Cosmos DB
- [ ] Implement event-driven inventory updates
- [ ] Monitor change feed lag
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

---

### Week 10 (continued): 🆕 Azure Cache for Redis
**Reference:** See *Azure Service Coverage* table above

#### Day 71: Redis Fundamentals & Integration ✅ *(Delivered by Architecture Phase 6)*
> ✅ `IDistributedCache` + Redis + MemoryCache fallback implemented during Architecture Phase 6 (Polish & Hardening)
- [x] Provision Azure Cache for Redis (Basic tier)
- [x] Understand caching patterns (Cache-Aside, Write-Through, Write-Behind)
- [x] Add StackExchange.Redis NuGet package to Orders API
- [x] Implement connection multiplexer singleton
- [x] Cache product catalog data with 5-minute TTL
- [x] Test cache hit/miss scenarios
- [x] Monitor Redis metrics in Azure Portal
- [x] **Time:** 2 hours | **Completed:** ✅ (Phase 6)

#### Day 72: Advanced Redis Patterns ✅ *(Delivered by Architecture Phase 6)*
> ✅ `CachingBehavior`, `ICacheable`, 5-min TTL on `GetAllCustomers` implemented during Architecture Phase 6
- [x] Implement distributed session state across microservices
- [x] Build rate limiting with sliding window (10 req/min per user)
- [ ] Use Redis Pub/Sub for real-time order notifications
- [x] Implement cache invalidation on Order updates
- [x] Add cache warming on application startup
- [x] Performance comparison: API with/without Redis
- [x] Document caching strategy and TTL decisions
- [x] **Time:** 2 hours | **Completed:** ✅ (Phase 6 — Pub/Sub deferred to microservices phase)

---

### Week 11: 🆕 .NET Aspire - Cloud-Native Orchestration ⭐ NEW
**Reference:** Official .NET Aspire documentation

#### Day 73: .NET Aspire Fundamentals
- [ ] Install .NET Aspire workload: `dotnet workload install aspire`
- [ ] Understand Aspire architecture (App Host, Service Defaults)
- [ ] Create Aspire App Host project: `XYDataLabs.OrderProcessingSystem.AppHost`
- [ ] Add Service Defaults project: `XYDataLabs.OrderProcessingSystem.ServiceDefaults`
- [ ] Run Aspire dashboard: explore built-in observability
- [ ] Understand service discovery and configuration
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 74: Migrate Orders API to Aspire
> 🏗️ **Architecture Phase 9a** — YARP gateway project: routing rules for Orders/Inventory/Notifications APIs
>
> **Prerequisite — Module isolation (before extraction):**
> - Per-module project structure: `Orders.Domain`, `Orders.Features`, `Orders.Infrastructure` (repeat for Inventory, Notifications)
> - PublicApi contracts: `IOrderModuleApi`, `IInventoryModuleApi` interfaces in dedicated `*.PublicApi` projects — modules depend ONLY on each other’s PublicApi
> - `AssemblyReference.cs` markers per project for reliable handler discovery
> - Module self-registration: `AddOrdersModule()`, `AddInventoryModule()` extension methods
> - Specification pattern — composable query objects (`OrderByStatusSpec`, `ActiveCustomersSpec`) replacing inline LINQ
> - Per-module DB schemas within shared database (`orders`, `inventory`, `notifications`)
- [ ] Add Aspire service defaults to Orders API
- [ ] Register Orders API in App Host
- [ ] Configure environment variables via Aspire
- [ ] Test service discovery: Orders API → SQL Database
- [ ] View telemetry in Aspire dashboard (traces, logs, metrics)
- [ ] Remove manual Docker Compose configuration
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 75: Add All Microservices to Aspire
> 🏗️ **Architecture Phase 9b** — Split Orders API → Orders microservice + Inventory microservice (separate projects, separate data stores)
>
> **Additional Phase 9 deliverables:**
> - Bounded-context and subdomain mapping — Orders, Inventory, Notifications as business contexts with clear responsibilities
> - Architecture tests (NetArchTest) enforcing inter-module boundaries: modules cannot reference each other’s internals, only PublicApi contracts
- [ ] Register Inventory API in App Host
- [ ] Register Notifications API in App Host
- [ ] Register UI in App Host
- [ ] Configure service-to-service communication
- [ ] Test end-to-end flow through Aspire orchestration
- [ ] Verify distributed tracing across all services
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 76: Aspire + SQL Database Integration
> 🏗️ **Architecture Phase 9c** — Notifications microservice + Docker Compose local orchestration for all services
>
> **Gateway cross-cutting concerns (Phase 9):**
> - CORS policy per downstream service configured in YARP
> - `System.Threading.RateLimiting` per tenant/client at gateway level
> - Request/response logging — structured audit trail at gateway entry point
> - Request size limits — prevent oversized payloads reaching downstream services
> - Auth token forwarding middleware (prepares for Phase 10 JWT)
- [ ] Add `Aspire.Hosting.SqlServer` package to App Host
- [ ] Register SQL Server container in App Host
- [ ] Connect Orders API to Aspire-managed SQL
- [ ] Use Aspire connection strings (no manual config)
- [ ] Test database connectivity through service discovery
- [ ] View SQL queries in Aspire dashboard
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 77: Aspire + Redis Integration
- [ ] Add `Aspire.Hosting.Redis` package to App Host
- [ ] Register Redis container in App Host
- [ ] Connect Orders API to Aspire-managed Redis
- [ ] Test caching through Aspire orchestration
- [ ] View Redis operations in dashboard
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 78: Aspire Observability Deep Dive
> 🏗️ **Architecture Phase 9d** — Event-based communication between microservices via Service Bus (orders → inventory → notifications)
- [ ] Explore OpenTelemetry integration (automatic)
- [ ] View distributed traces across microservices
- [ ] Analyze logs aggregation from all services
- [ ] Monitor metrics (HTTP requests, database calls)
- [ ] Export telemetry to Application Insights
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 79: Aspire Deployment Preparation
- [ ] Generate deployment manifests: `dotnet run --publisher manifest`
- [ ] Understand Aspire → Azure Container Apps deployment
- [ ] Review generated Bicep/YAML files
- [ ] Compare Aspire vs manual Docker Compose
- [ ] Document Aspire benefits (service discovery, observability, config)
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

---

### Week 11 (continued): Azure Container Registry (ACR) + Aspire Deployment
**Reference:** Containerization-ACA-Aspire-Learning-Path.md → Module 2

#### Day 80: Docker Basics + Integration Testing (Azure-first .NET) ✅ *(Partially delivered by Architecture Phase 5)*
> **Why integration testing now:** Before pushing real container images to ACR you need a reliable test suite
>
> ✅ Testcontainers + WebApplicationFactory integration test infrastructure delivered during Architecture Phase 5 (Test Restructure)
- [x] Verify Docker Desktop running
- [ ] Create multi-stage Dockerfile for Orders API
- [ ] Build image: `docker build -t orderprocessing-api:local`
- [ ] Understand Aspire uses Docker under the hood
- [x] 🆕 Add `Microsoft.AspNetCore.Mvc.Testing` + `Testcontainers.MsSql` + `Testcontainers.Redis` NuGet packages
- [x] 🆕 Create `IntegrationTests` project with `WebApplicationFactory<Program>` test base
- [x] 🆕 Write integration test: spin up SQL + Redis containers, run API, POST `/orders`, assert response
- [ ] 🆕 Add integration test step to GitHub Actions CI workflow (runs before pushing to ACR)
- [ ] **Time:** 3 hours | **Completed:** ✅ (Phase 5 — Docker image + CI integration pending)

#### Day 81: Provision ACR via Bicep + Authenticate
- [ ] Create `infra/modules/acr.bicep` (Task 2.1)
- [ ] Add ACR to `infra/main.bicep`
- [ ] Deploy: `az deployment sub create`
- [ ] Login to ACR: `az acr login --name <acr>`
- [ ] Tag image: `docker tag <image> <acr>.azurecr.io/<image>:v1`
- [ ] Push image: `docker push <acr>.azurecr.io/<image>:v1`
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 82: CI/CD - Build & Push Containers
**Reference:** Task 2.2
- [ ] Create `.github/workflows/container-build.yml`
- [ ] Add OIDC login step
- [ ] Build and push API image on commit
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 83: Push UI Image via CI
- [ ] Extend workflow to build UI
- [ ] Tag images with `:sha` and `:latest`
- [ ] Verify images in ACR Portal
- [ ] **Time:** 1.5 hours | **Completed:** ___/___/___

#### Day 84: Image Tagging Strategy
- [ ] Implement semantic versioning tags
- [ ] Add branch-based tags (dev, staging, prod)
- [ ] Document tagging conventions
- [ ] **Time:** 1 hour | **Completed:** ___/___/___

#### Day 85: ACR Security & Access
- [ ] Disable admin account (already done in Bicep)
- [ ] Assign AcrPull role to Managed Identity
- [ ] Test pull without admin credentials
- [ ] **Time:** 1 hour | **Completed:** ___/___/___

#### Day 86: Aspire to ACR Integration
- [ ] Build Aspire-managed services as container images
- [ ] Push Aspire-generated images to ACR
- [ ] Prepare for Container Apps deployment with Aspire manifests
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

---

### Week 12: Azure Container Apps (ACA) with Aspire Deployment — 🏗️ *Architecture Phase 10*
**Reference:** Containerization-ACA-Aspire-Learning-Path.md → Module 3
> 🏗️ **Architecture Phase 10** maps 1:1 to this week. ACA deployment IS the architecture phase.
>
> **Phase 10 Azure services beyond ACA basics:**
> - Azure Functions — Service Bus-triggered DLQ reprocessor (isolated process model); timer-triggered projection health checks
> - Azure Blob Storage — order file attachments (invoices, receipts) with managed identity access + private endpoint; `BlobCreated` events via Event Grid
> - Private networking — VNet integration, private endpoints for SQL, Key Vault, Redis, and Blob Storage; NSG rules for ACA VNet; private DNS zones
> - JWT authentication — Entra ID token validation at APIM (policy-based) and YARP gateway, token propagation to downstream services
> - Cost governance — scale-to-zero on all Container Apps, APIM Consumption tier (pay-per-call), autoscale RU caps on Cosmos DB, Azure Budget alerts per resource group
> - DLQ handling — alert threshold when DLQ depth exceeds configurable limit; poison message quarantine for messages that fail reprocessing N times

#### Day 87: Log Analytics Workspace
**Reference:** ACA-Migration-Plan.md → Phase 3
- [ ] Create LAW via CLI or Bicep
- [ ] Understand workspace structure and queries
- [ ] Write first KQL query
- [ ] **Time:** 1.5 hours | **Completed:** ___/___/___

#### Day 88: Deploy Aspire to ACA (Automated)
**Reference:** .NET Aspire Azure deployment
- [ ] Use `azd init` to initialize Azure Developer CLI
- [ ] Run `azd up` to deploy entire Aspire app to Container Apps
- [ ] Aspire automatically creates: ACA Environment, Container Apps, LAW
- [ ] Verify all microservices deployed (Orders, Inventory, Notifications, UI)
- [ ] Test service discovery in Azure Container Apps
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 89: Aspire Manifest to Bicep
**Reference:** Aspire deployment manifests
- [ ] Generate deployment manifest: `dotnet run --publisher manifest`
- [ ] Convert manifest to Bicep (manual or tool-assisted)
- [ ] Understand Aspire-generated resource definitions
- [ ] Compare `azd up` (automated) vs manual Bicep deployment
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 90: ACA Ingress & Networking
> 🏗️ **Phase 10 networking** — Private endpoints for SQL/KV/Redis/Blob, VNet integration for ACA environment, NSG rules, private DNS zones for internal service resolution
- [ ] Configure external ingress for UI and API
- [ ] Configure internal ingress for Inventory/Notifications APIs
- [ ] Test service-to-service communication in ACA
- [ ] View distributed traces in Application Insights
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 91: ACA Scaling & Performance
- [ ] Configure autoscaling rules (CPU, HTTP requests)
- [ ] Set minReplicas=1, maxReplicas=5 for each service
- [ ] Test scale-out under load (optional: use Azure Load Testing)
- [ ] Monitor scaling events in Log Analytics
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 92: Aspire + Azure Resources Integration
> 🏗️ **Phase 10 services** — Add Azure Blob Storage for order attachments, Azure Functions DLQ reprocessor (Service Bus trigger), Event Grid for blob lifecycle events
- [ ] Connect to Azure SQL Database (not Aspire-managed)
- [ ] Connect to Azure Cache for Redis (not Aspire-managed)
- [ ] Use Azure Key Vault for secrets in ACA
- [ ] Test production-ready configuration
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 93: Review & Compare
> 🏗️ **Phase 10 cost governance** — Scale-to-zero analysis, APIM Consumption tier costing, Azure Budget alerts per resource group, blue-green deployment with ACA revisions, canary release traffic shifting
- [ ] Compare App Service vs ACA vs Aspire local
- [ ] Document Aspire benefits (observability, service discovery, config)
- [ ] Cost analysis: ACA pricing model
- [ ] Decide: Aspire for development, ACA for production
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

> **Observability note:** OpenTelemetry, distributed tracing, custom metrics, KQL queries, alerts, and workbooks are covered as part of the .NET Aspire observability deep-dive in Days 78-79 and the ACA Log Analytics work in Day 87. The Aspire Service Defaults project wires OTel automatically.

---

### Week 13: Security & Supply Chain
**Reference:** Containerization-ACA-Aspire-Learning-Path.md → Module 5 + ACA-Migration-Plan.md → Phase 4b

#### Day 85: Key Vault Setup
**Reference:** ACA-Migration-Plan.md → Phase 3b
- [ ] Create Key Vault via Bicep
- [ ] Add secrets (API keys, connection strings)
- [ ] Grant ACA Managed Identity `Key Vault Secrets User` role
- [ ] **Time:** 1.5 hours | **Completed:** ___/___/___

#### Day 86: ACA Secret References
- [ ] Configure ACA to reference Key Vault secrets
- [ ] Remove inline secrets from Bicep
- [ ] Test secret retrieval in container
- [ ] **Time:** 1.5 hours | **Completed:** ___/___/___

#### Day 87: Trivy Image Scanning
**Reference:** Task 5.1
- [ ] Add Trivy scan step to CI workflow
- [ ] Scan API image for HIGH/CRITICAL vulnerabilities
- [ ] Fail build on critical CVEs
- [ ] **Time:** 1 hour | **Completed:** ___/___/___

#### Day 88: Generate SBOM
**Reference:** Task 5.2
- [ ] Install Syft in CI
- [ ] Generate SBOM for API image (SPDX JSON)
- [ ] Upload SBOM as GitHub artifact
- [ ] **Time:** 1 hour | **Completed:** ___/___/___

#### Day 89: Image Signing (Optional)
**Reference:** ACA-Migration-Plan.md → Phase 4b
- [ ] Install Notary v2 CLI
- [ ] Sign images with certificate
- [ ] Configure ACR content trust policies
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 90: Azure Policy & Defender
**Reference:** ACA-Migration-Plan.md → Phase 0
- [ ] Enable Microsoft Defender for Containers
- [ ] Review Defender recommendations
- [ ] Assign Azure Policy for required tags
- [ ] **Time:** 1.5 hours | **Completed:** ___/___/___

---

### Week 14: 🆕 Azure API Management (APIM)
**Reference:** See *Azure Service Coverage* table above
> **Sequence note:** This section follows ACA completion (Day 93). Days 91-98 here map to calendar Days 94-101 in the overall plan.

#### Day 91 (→94): APIM Fundamentals
- [ ] Provision API Management service (Developer tier)
- [ ] Understand APIM components: Gateway, Portal, Management API
- [ ] Import OpenAPI definition from Orders API
- [ ] Test API via APIM gateway URL
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 92: APIM Policies
- [ ] Implement rate limiting policy (10 requests/minute)
- [ ] Add CORS policy for UI domain
- [ ] Configure request/response transformation
- [ ] Test policies with Postman
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 93: Authentication & Authorization — APIM + C# (Azure-first .NET)
- [ ] Configure OAuth2 with Azure AD in APIM
- [ ] Implement JWT validation policy in APIM (gateway validates before forwarding)
- [ ] 🆕 Add `Microsoft.AspNetCore.Authentication.JwtBearer` NuGet package to Orders API
- [ ] 🆕 Configure `JwtBearer` middleware in `Program.cs` to validate Azure AD tokens independently
- [ ] 🆕 Implement policy-based RBAC: `IAuthorizationRequirement` for Admin/User roles
- [ ] 🆕 Annotate controllers with `[Authorize(Policy = "OrdersReadPolicy")]` and `[Authorize(Policy = "OrdersWritePolicy")]`
- [ ] Set up subscription keys for external consumers
- [ ] Test: no token → 401; Admin token → 200; User token → policy-based access
- [ ] **Time:** 3 hours | **Completed:** ___/___/___

#### Day 94: API Versioning — APIM + C# (Azure-first .NET) ✅ *(Partially delivered by Architecture Phase 6)*
> ✅ `Asp.Versioning.Mvc`, `/api/v1/`, Swagger grouped by version implemented during Architecture Phase 6
- [x] Configure version sets in APIM (header-based: `Api-Version: v1`)
- [x] 🆕 Add `Asp.Versioning.Http` NuGet package (official API versioning for ASP.NET Core)
- [x] 🆕 Configure `AddApiVersioning()` + `AddApiExplorer()` in `Program.cs`
- [x] 🆕 Annotate controllers with `[ApiVersion("1.0")]` and `[ApiVersion("2.0")]`
- [x] 🆕 Implement Problem Details (RFC 9457) standardised error responses: `AddProblemDetails()` in `Program.cs`
- [ ] APIM backend updated to route to versioned ACA endpoints
- [ ] Test: `v1` endpoint returns old schema; `v2` endpoint returns expanded schema
- [ ] **Time:** 2.5 hours | **Completed:** ✅ (Phase 6 — APIM routing pending)

#### Day 95: Developer Portal
> 🏗️ **Architecture Phase 12a** — .NET 10 upgrade assessment, Azure App Configuration, Polly v8 resilience hub
>
> **Additional Phase 12 deliverables:**
> - Azure AI Document Intelligence — extract structured data from uploaded invoices/receipts in Blob Storage; Event Grid triggers Function → Document Intelligence API → enriches order metadata
> - Advanced Polly — bulkhead isolation + fallback policies (retry + circuit breaker already from Phase 9)
> - Reference `ARCHITECTURE.md` §15 PCI DSS card handling rules when implementing Phase 8.5 payment work
- [ ] Customize developer portal branding
- [ ] Publish API documentation
- [ ] Create products and user groups
- [ ] Test self-service subscription workflow
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 96: APIM + Container Apps Integration
- [ ] Configure APIM backend to point to Container Apps
- [ ] Set up private VNet integration
- [ ] Implement circuit breaker policy
- [ ] Monitor API analytics in APIM
- [ ] **Time:** 2.5 hours | **Completed:** ___/___/___

#### Day 97: Advanced Monitoring
> 🏗️ **Architecture Phase 12b** — Per-service CI/CD pipelines, observability dashboards (Grafana or Azure Workbooks)
>
> **Additional Phase 12 deliverables:**
> - DR / Business Continuity — documented RTO/RPO targets per service; Azure SQL geo-replication strategy; backup/restore runbook
> - Performance / Load Testing — Azure Load Testing or k6 for baseline performance; SLO validation under realistic load
> - .NET 10 upgrade — update `global.json` TFM, bump `Directory.Packages.props`, verify Testcontainers + NetArchTest compatibility, update Dockerfiles and CI pipeline
- [ ] Enable Application Insights for APIM
- [ ] Create custom dashboards for API metrics
- [ ] Set up alerts for API failures and high latency
- [ ] Analyze API usage patterns and trends
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 98: Review & Production Readiness
- [ ] Document APIM architecture and routing
- [ ] Compare APIM vs YARP Gateway use cases
- [ ] Calculate cost implications for production
- [ ] Create APIM deployment Bicep template
- [ ] Weekend: Explore APIM self-hosted gateway
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

---

### Week 15: Networking & Edge (Front Door + WAF)
**Reference:** Containerization-ACA-Aspire-Learning-Path.md → Module 6 + ACA-Migration-Plan.md → Phase 7b
> **Sequence note:** This section follows APIM (Day 98). Days 92-98 here map to calendar Days 101-107 in the overall plan.

#### Day 92: Azure Front Door Basics
- [ ] Understand Front Door architecture (origin, endpoint, WAF)
- [ ] Create Front Door profile (Standard or Premium)
- [ ] Add ACA as origin
- [ ] **Time:** 1.5 hours | **Completed:** ___/___/___

#### Day 93: Front Door Bicep Module
**Reference:** Task 6.1
- [ ] Create `infra/modules/frontdoor.bicep`
- [ ] Configure origin group and health probes
- [ ] Deploy Front Door
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 94: WAF Policies
**Reference:** ACA-Migration-Plan.md → Phase 7b
- [ ] Create WAF policy with OWASP rules
- [ ] Enable rate limiting
- [ ] Test WAF blocks (SQL injection, XSS)
- [ ] **Time:** 1.5 hours | **Completed:** ___/___/___

#### Day 95: Custom Domain & TLS
- [ ] Add custom domain to Front Door
- [ ] Configure managed TLS certificate
- [ ] Update DNS (CNAME or Alias)
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 96: Traffic Routing
- [ ] Route traffic: Front Door → ACA
- [ ] Test HTTPS enforcement
- [ ] Measure latency via Front Door
- [ ] **Time:** 1 hour | **Completed:** ___/___/___

#### Day 97: VNET Integration (Optional)
- [ ] Understand ACA VNET integration
- [ ] Deploy ACA environment in custom VNET
- [ ] Configure private ingress
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 98: Review & Lab
- [ ] Document networking topology
- [ ] Test failover scenarios (origin down)
- [ ] Weekend: Explore Azure Application Gateway as alternative
- [ ] **Time:** 2-3 hours | **Completed:** ___/___/___

---

### Week 16: Reliability & SRE
**Reference:** Containerization-ACA-Aspire-Learning-Path.md → Module 8 + ACA-Migration-Plan.md → Phase 12b

#### Day 99: Blue/Green Deployment
**Reference:** Task 8.1
- [ ] Deploy new revision with `--traffic-weight 10`
- [ ] Monitor metrics (errors, latency)
- [ ] Shift traffic to 100% if stable
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 100: Canary Deployment
> 🏗️ **Architecture Phase 11a** — Database per service: remove shared `DbContext`, design eventual consistency across service boundaries
>
> **Phase 11 key deliverables:**
> - `XYDataLabs.OrderProcessingSystem.DurableFunctions` — separate Azure Functions project (isolated process) for Saga/Process Manager orchestrations
> - `OrderFulfilmentOrchestrator` with compensating rollback activities (`ReserveInventoryActivity`, `ProcessPaymentActivity`, `CompensatePaymentActivity`)
> - Choreography vs Saga decision: if failure in step N requires undoing steps 1…N-1, use Saga; otherwise choreography is sufficient
> - Fan-out/fan-in — parallel activity execution (e.g. validate all order line items concurrently)
- [ ] Deploy canary revision (20% traffic)
- [ ] Compare metrics: canary vs stable
- [ ] Rollback if issues detected
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 101: Define SLOs/SLIs
**Reference:** ACA-Migration-Plan.md → Phase 12b
- [ ] Define SLIs (latency p95, availability %)
- [ ] Set SLOs (e.g., 99.9% availability)
- [ ] Document error budgets
- [ ] **Time:** 1 hour | **Completed:** ___/___/___

#### Day 102: Synthetic Monitoring
> 🏗️ **Architecture Phase 11b** — Cross-service data queries via API composition, no shared DB access between services
>
> **Phase 11 operational patterns:**
> - Database migration strategy — EF Core bundles (`dotnet ef migrations bundle`) + ACA init containers; rollback via `--target` flag
> - Performance conventions: `AsNoTracking()` on all read queries, indexing review per service DB, `SqlQuery<T>` for complex/reporting queries
> - `NullTenantProvider` for non-request contexts (dedicated-DB seeding per `ARCHITECTURE.md` §10.1)
> - Bulk operations — `EFCore.BulkExtensions` or `ExecuteSqlInterpolated` for batch import/export
- [ ] Create Application Insights availability test
- [ ] Test API `/health` endpoint every 5 min
- [ ] Set up alerts for availability drops
- [ ] **Time:** 1 hour | **Completed:** ___/___/___

#### Day 103: Incident Runbooks
- [ ] Write rollback runbook
- [ ] Document on-call escalation
- [ ] Create incident response checklist
- [ ] **Time:** 1.5 hours | **Completed:** ___/___/___

#### Day 104: Chaos Engineering (Optional)
- [ ] Introduce controlled failure (kill container)
- [ ] Observe recovery and alerting
- [ ] Document learnings
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 105: Review & Lab
- [ ] Run full blue/green deployment drill
- [ ] Simulate incident and follow runbook
- [ ] Weekend: Explore Azure Chaos Studio
- [ ] **Time:** 2-3 hours | **Completed:** ___/___/___

---

### Week 17: Final Migration (ACA Cutover + Decommission)
**Reference:** Containerization-ACA-Aspire-Learning-Path.md → Module 7 + ACA-Migration-Plan.md → Phase 10-13

#### Day 106: .NET Aspire Overview
- [ ] Understand Aspire AppHost pattern
- [ ] Install .NET Aspire workload
- [ ] Create sample Aspire project
- [ ] **Time:** 1.5 hours | **Completed:** ___/___/___

#### Day 107: Convert to Aspire Host
**Reference:** Task 7.1
- [ ] Create `XYDataLabs.OrderProcessingSystem.AppHost` project
- [ ] Add service references (API, UI)
- [ ] Run locally with `dotnet run`
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 108: Deploy Aspire to ACA
- [ ] Generate Aspire manifest
- [ ] Deploy to ACA using azd or Bicep
- [ ] Verify service discovery
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 109: Final Blue/Green Cutover
**Reference:** ACA-Migration-Plan.md → Phase 10
> 🏗️ **Architecture Phase 13a** — Blue-green/canary with Aspire managed deployments
- [ ] Shift production traffic to ACA
- [ ] Monitor for ≥72 hours
- [ ] Keep App Service as fallback
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 110: Decommission App Service
**Reference:** ACA-Migration-Plan.md → Phase 11
- [ ] After stability window, scale App Service to 0
- [ ] Archive App Service Bicep definitions
- [ ] Delete App Service resources
- [ ] **Time:** 1 hour | **Completed:** ___/___/___

#### Day 111: Optimize & Cost Analysis
**Reference:** ACA-Migration-Plan.md → Phase 12
- [ ] Tune ACA autoscaling (KEDA)
- [ ] Review Azure Cost Analysis
- [ ] Set cost alerts and budgets
- [ ] **Time:** 1.5 hours | **Completed:** ___/___/___

#### Day 112: Final Documentation
**Reference:** ACA-Migration-Plan.md → Phase 13
- [ ] Update architecture diagrams
- [ ] Publish ops runbooks to repo
- [ ] Create deployment summary report
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

---

## 🎓 Completion Checklist

### Core Competencies Achieved
- [x] **Azure Portal and CLI proficiency** ✅
- [x] **App Service deployment with OIDC** ✅
- [x] **Bicep Infrastructure as Code** ✅
- [ ] Docker containerization (Week 11)
- [ ] Azure Container Registry (ACR) (Week 11)
- [ ] Azure Container Apps (ACA) (Week 12)
- [x] **OpenTelemetry observability** ✅ *(Architecture Phase 3)*
- [ ] Key Vault secrets management (Week 8)
- [ ] Trivy vulnerability scanning (Week 13)
- [ ] SBOM generation (Week 13)
- [ ] Azure Front Door + WAF (Week 15)
- [ ] Blue/green deployments (Week 16)
- [ ] SRE practices (SLOs, runbooks) (Week 16)
- [ ] .NET Aspire (Week 11)

### Enterprise Practices Mastered
- [x] **OIDC authentication (no secrets in CI)** ✅
- [x] **Multi-environment deployments (dev/staging/prod)** ✅
- [x] **Infrastructure as Code with Bicep modules** ✅
- [x] **Structured logging and tracing** ✅ *(Architecture Phase 3 — Serilog + OTel)*
- [x] **Health checks (liveness + readiness)** ✅ *(Architecture Phase 6)*
- [x] **API versioning** ✅ *(Architecture Phase 6)*
- [x] **Distributed caching (Redis)** ✅ *(Architecture Phase 6)*
- [x] **Integration testing (Testcontainers)** ✅ *(Architecture Phase 5)*
- [ ] Supply chain security (scan, SBOM, sign) (Week 13)
- [ ] Centralized secrets with Key Vault (Week 8)
- [ ] Alerting and incident response (Week 16)
- [ ] Cost management and budgets (Week 17)
- [ ] Azure Policy and governance (Week 13)
- [ ] Disaster recovery and rollback (Week 16)

---

## 📈 Progress Summary

**Total Days Planned:** 112 days (~16 weeks)  
**Days Completed:** 38 / 112  
**Percentage Complete:** 34%  

**Current Phase:** Azure Data & Resilience (Days 32-56)  
**Current Day:** Day 39 — Polly Retry & Circuit Breaker  
**Last Completed Task:** Day 38 — Azure SQL resilience baseline; EnableRetryOnFailure + Polly planning  
**Next Milestone:** Polly resilience + Health Checks (Days 39-43), then Azure Functions + Service Bus (Days 44-56)  
**Architecture Status:** Phases 1-6 ✅ complete; Phase 7 (Tenant Enforcement & Ops) is next  

---

## 📝 Daily Reflection Template

Use this format in personal notes after each session:

```
Date: ___/___/___
Time Spent: ___ hours
Tasks Completed: [x] Task 1, [x] Task 2
Challenges Faced: ___
Learnings: ___
Questions for Review: ___
Tomorrow's Focus: ___
```

---

## 🔗 Quick Links

- **Azure Portal:** https://portal.azure.com
- **GitHub Repository:** https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem
- **Azure CLI Docs:** https://learn.microsoft.com/cli/azure/
- **Bicep Reference:** https://learn.microsoft.com/azure/azure-resource-manager/bicep/
- **ACA Docs:** https://learn.microsoft.com/azure/container-apps/
- **.NET Aspire:** https://learn.microsoft.com/dotnet/aspire/

---

## 🎯 Success Metrics

Track these weekly:
- **Hours logged:** ___
- **Deployments completed:** ___
- **Bicep files created:** ___
- **CI/CD workflows working:** ___
- **Images pushed to ACR:** ___
- **Incidents resolved:** ___

---

## 📞 Support & Next Steps

**When Stuck:**
1. Re-read the specific task in the referenced document
2. Check Azure Portal → Notifications for error details
3. Review GitHub Actions logs
4. Search Azure docs for error codes
5. Ask for help (include error messages and context)

**After Completion:**
- Explore advanced topics: Dapr, KEDA, GitOps
- Contribute back: document learnings, share templates
- Obtain Azure certifications: AZ-204, AZ-400
