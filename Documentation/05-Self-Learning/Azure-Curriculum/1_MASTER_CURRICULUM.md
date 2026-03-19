# Azure Developer Master Curriculum - Single Source of Truth

**Your Complete Learning Journey: Azure Fundamentals → ACA Migration**  
**Start Date:** _[Your Start Date]_  
**Daily Commitment:** 1-2 hours/day  
**Total Duration:** ~12-16 weeks

---

## 🎯 WHAT'S NEXT? (Your Current Focus)

**✅ COMPLETED SO FAR (Days 1-31):**
- ✅ Azure fundamentals (Portal, CLI, resource management)
- ✅ App Service deployment with OIDC authentication
- ✅ GitHub Actions CI/CD workflows (9 workflows: bootstrap, initial setup, deploy API/UI, infra deploy, validate, docker health)
- ✅ Bicep Infrastructure as Code (modules + parameters)
- ✅ Multi-environment setup (dev/staging/prod)
- ✅ Advanced CI/CD: parallel dispatch, health check retries (3×60s), bootstrap summary with endpoints table

**🔥 YOUR NEXT 3 PRIORITIES:**

### Priority 1: Azure Data & Resilience (Days 32-56)
**Why:** Connect your app to real Azure data services using passwordless auth — the foundation for everything that follows  
**Tasks:**
- Days 32-43: Azure SQL + EF Core + `DefaultAzureCredential` + Polly + Health Checks
- Days 44-52: Azure Functions + Service Bus (microservice pub/sub in C#)
- Days 53-56: Key Vault + `IOptions<T>` + Worker Services + Outbox Pattern

### Priority 2: Azure Services Deep Dive + Containers (Days 57-86)
**Why:** Master advanced Azure services, then containerise with confidence  
**Tasks:**
- Days 57-65: Azure Functions Advanced (Durable) + Serilog structured logging
- Days 66-72: Cosmos DB (with C# SDK + `DefaultAzureCredential`) + Azure Cache for Redis
- Days 73-86: .NET Aspire orchestration + Docker + Integration Tests (TestContainers) + ACR

### Priority 3: ACA + Auth + Enterprise (Days 87-112)
**Why:** Migrate to containers with full enterprise security and observability  
**Tasks:**
- Days 87-93: ACA deployment via Aspire (`azd up`) + Log Analytics + ingress
- Days 94-96: APIM JWT validation + `JwtBearer` middleware + RBAC in C#
- Days 97-100: Security scanning (Trivy, SBOM) + Azure Defender + Azure Policy
- Days 101-112: Front Door + APIM versioning + SRE practices + Final ACA migration

---

## 📝 TODAY'S STEP-BY-STEP GUIDE

**Operational guide has been moved to:**  
📄 `Documentation/02-Azure-Learning-Guides/AZURE_DEPLOYMENT_GUIDE.md`

The complete step-by-step deployment guide is now maintained in the Azure Deployment Guide for easier regular access. This includes:
- Task 1: Read workflow documentation
- Task 2: Run dry run test (with detailed steps)
- Task 3: Analyze what-if output
- Task 4: Real deployment (optional)
- Task 5: Document your experience

**Quick link:** See section "📋 Manual Infrastructure Deployment - Step-by-Step Guide" in AZURE_DEPLOYMENT_GUIDE.md

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

**Save to:** Personal learning journal or `Documentation/05-Self-Learning/Azure-Curriculum/02-Daily-Progress/November-2025/21-Nov-2025.md`

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
1. **This Document (MASTER_CURRICULUM.md)** - Your daily tracker and curriculum overview
2. **[Azure_Learning_Guide_Complete.md](./Azure_Learning_Guide_Complete.md)** - Foundational Azure concepts and early deployment
3. **[ACA Migration Plan](../../04-Enterprise-Architecture/ACA-Migration-Plan.md)** - Enterprise migration roadmap (17 phases)
4. **[Containerization Learning Path](../../02-Azure-Learning-Guides/Containerization-ACA-Aspire-Learning-Path.md)** - Hands-on Docker, ACR, ACA (8 modules)
5. **[Quick Command Reference](../../../QUICK-COMMAND-REFERENCE.md)** - All essential commands: Git, Azure CLI, Azure SQL, EF Core migrations, Docker, GitHub Actions, troubleshooting

---

## 🎯 Learning Path Overview

### Phase 1: Azure Fundamentals (Weeks 1-4)
**Source:** `Azure_Learning_Guide_Complete.md`  
**Focus:** Core Azure concepts, CLI, Portal, basic deployments

### Phase 2: Enterprise App Service Deployment (Weeks 5-8)
**Source:** `Azure_Learning_Guide_Complete.md` + `AZURE_DEPLOYMENT_GUIDE.md`  
**Focus:** OIDC, CI/CD, App Service, Bicep basics

### Phase 3: Container & ACA Transition (Weeks 9-16)
**Source:** `Containerization-ACA-Aspire-Learning-Path.md` + `ACA-Migration-Plan.md`  
**Focus:** Docker, ACR, ACA, enterprise security, observability

---

## 📅 Daily Progress Tracker

### ✅ Weeks 1-2: Azure Fundamentals (Days 1-14) — [Daily Progress](02-Daily-Progress/week-01-02-azure-fundamentals.md)
**Reference:** Azure_Learning_Guide_Complete.md (Days 1-14)

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

*(Continue Days 8-14 per Azure_Learning_Guide_Complete.md)*

---

### ✅ Weeks 3-4: App Service & OIDC Deployment (Days 15-28) — [Daily Progress](02-Daily-Progress/week-03-04-appservice-oidc.md)
**Reference:** Azure_Learning_Guide_Complete.md (Days 15-28)

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
**Reference:** AZURE_DEPLOYMENT_GUIDE.md
- [x] Run `setup-github-oidc.ps1` script
- [x] Create App Registration in Entra ID
- [x] Add federated credentials for dev/staging/main
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
*(Refer to Azure_Learning_Guide_Complete.md Days 22-28 for serverless functions, event-driven patterns)*

---

### ✅ Weeks 5-8: IaC, CI/CD + Azure SQL Baseline (Days 29-34) — [Daily Progress](02-Daily-Progress/week-05-08-iac-data.md)
**Reference:** Azure_Learning_Guide_Complete.md + infra/ folder

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
**Reference:** `.github/workflows/infra-deploy.yml` + `README-INFRA-DEPLOY.md` + `AZURE_DEPLOYMENT_GUIDE.md` (Manual workflow trigger & dry run parameters section)
- [x] Add what-if step for PR reviews
- [x] Deploy on branch push (dev/staging/main)
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
- [x] Enable SQL logging in development (`LogTo`, `EnableSensitiveDataLogging`, `EnableDetailedErrors` guarded by `IsDevelopment()`)
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
- [ ] Enable system-assigned managed identity on App Service
- [ ] Create SQL contained user: `CREATE USER [<app-service-name>] FROM EXTERNAL PROVIDER`
- [ ] Grant roles: `ALTER ROLE db_datareader ADD MEMBER [<app-service-name>]`
- [ ] Verify passwordless connection from Azure App Service logs
- [ ] **Time:** 1.5 hours | **Completed:** ___/___/___

#### Day 36: 🆕 DefaultAzureCredential in C# (Azure-first .NET)
> **Why now:** First time C# code connects to Azure without any stored password or secret
- [x] Add `Azure.Identity` NuGet package
- [ ] Replace SQL password auth with access token via `DefaultAzureCredential`
- [ ] Understand credential chain: `EnvironmentCredential → ManagedIdentityCredential → VisualStudioCredential → AzureCliCredential`
- [ ] Test locally: `az login` → CLI credential picked up automatically
- [ ] Test in Azure: Managed Identity credential used automatically
- [ ] **Time:** 2 hours | **Completed:** ___/___/___ (Azure.Identity added + used for Key Vault; SQL passwordless not yet done)

#### Day 37: Connect API to Azure SQL — Passwordless End-to-End
- [ ] Update `DbContext` to supply `DefaultAzureCredential` access token for Azure SQL
- [ ] Verify no SQL username/password anywhere in config or environment variables
- [ ] Deploy updated API and confirm successful connection in Application Insights
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 38: Azure SQL — Resilience Baseline
- [ ] Test what happens when SQL is briefly unavailable (stop/start via Portal)
- [ ] Observe EF Core default retry (`EnableRetryOnFailure`)
- [ ] Document failure modes and plan Polly layering (Day 39)
- [ ] **Time:** 1 hour | **Completed:** ___/___/___

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

#### Day 42: 🆕 ASP.NET Core Health Checks (Azure-first .NET)
> **Why now:** Required for App Service health probe verification and ACA readiness probes later
- [ ] Add `Microsoft.Extensions.Diagnostics.HealthChecks.EntityFrameworkCore` NuGet package
- [ ] Register health checks: `AddHealthChecks().AddDbContextCheck<AppDbContext>()`
- [ ] Map endpoints: `app.MapHealthChecks("/health")` (liveness) and `/health/ready` (readiness + DB check)
- [ ] **Time:** 1.5 hours | **Completed:** ___/___/___

#### Day 43: Health Checks — Azure Integration
- [ ] Configure App Service health check probe to use `/health` endpoint
- [ ] Add custom health check for Service Bus connectivity
- [ ] View health status in Azure Portal → App Service → Health Check
- [ ] **Time:** 1 hour | **Completed:** ___/___/___

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
- [ ] Create `XYDataLabs.OrderProcessingSystem.Worker` project (Worker Service template)
- [ ] Implement `BackgroundService` that processes order events via `ServiceBusProcessor`
- [ ] Register as `IHostedService` in DI
- [ ] Deploy as a separate Azure App Service (Worker)
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 56: 🆕 Outbox Pattern — Reliable Messaging (Azure-first .NET)
> **Why now:** Without Outbox, a DB write can succeed but the Service Bus publish can silently fail — losing the event
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
- [ ] Create Storage Account with Queue service
- [ ] Implement queue producer (add messages)
- [ ] Implement queue consumer (process messages)
- [ ] Compare Storage Queues vs Service Bus features
- [ ] Understand when to use each service
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 59: 🆕 Queue-Triggered Functions
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
**Reference:** AZURE-TOP-7-SERVICES-ANALYSIS.md

#### Day 65: 🆕 Serilog Structured Logging (Azure-first .NET)
> **Why now:** Unstructured logs are unreadable in Docker and ACA containers — Serilog must be in place before containerising
- [x] Add `Serilog.AspNetCore`, `Serilog.Sinks.ApplicationInsights`, `Serilog.Enrichers.Environment` NuGet packages
- [x] Replace default logging with Serilog in `Program.cs` using `UseSerilog()`
- [x] Configure sinks: Console (structured JSON) + Application Insights
- [ ] Add enrichers: `WithMachineName()`, `WithEnvironmentName()`, `WithCorrelationId()`
- [x] Use structured properties (not string interpolation): `Log.Information("Order {OrderId} placed for {CustomerId}", orderId, customerId)`
- [ ] Verify correlation IDs flow across service calls in App Insights
- [ ] **Time:** 2 hours | **Completed:** ___/___/___ (Serilog + Console/File/AppInsights sinks done; dedicated enricher packages + correlation IDs pending)

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
- [ ] Create new project: `XYDataLabs.OrderProcessingSystem.ProductCatalogAPI`
- [ ] Use Cosmos DB for product storage
- [ ] Implement search and filtering endpoints
- [ ] Add pagination for large result sets
- [ ] Add to YARP Gateway routing (`products.localhost`)
- [ ] **Time:** 3 hours | **Completed:** ___/___/___

#### Day 68: Cosmos DB Performance Optimization
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
- [ ] Create Cosmos DB-triggered Azure Function
- [ ] Process change feed events
- [ ] Sync data between SQL and Cosmos DB
- [ ] Implement event-driven inventory updates
- [ ] Monitor change feed lag
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

---

### Week 10 (continued): 🆕 Azure Cache for Redis
**Reference:** AZURE-TOP-7-SERVICES-ANALYSIS.md

#### Day 71: Redis Fundamentals & Integration
- [ ] Provision Azure Cache for Redis (Basic tier)
- [ ] Understand caching patterns (Cache-Aside, Write-Through, Write-Behind)
- [ ] Add StackExchange.Redis NuGet package to Orders API
- [ ] Implement connection multiplexer singleton
- [ ] Cache product catalog data with 5-minute TTL
- [ ] Test cache hit/miss scenarios
- [ ] Monitor Redis metrics in Azure Portal
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 72: Advanced Redis Patterns
- [ ] Implement distributed session state across microservices
- [ ] Build rate limiting with sliding window (10 req/min per user)
- [ ] Use Redis Pub/Sub for real-time order notifications
- [ ] Implement cache invalidation on Order updates
- [ ] Add cache warming on application startup
- [ ] Performance comparison: API with/without Redis
- [ ] Document caching strategy and TTL decisions
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

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
- [ ] Add Aspire service defaults to Orders API
- [ ] Register Orders API in App Host
- [ ] Configure environment variables via Aspire
- [ ] Test service discovery: Orders API → SQL Database
- [ ] View telemetry in Aspire dashboard (traces, logs, metrics)
- [ ] Remove manual Docker Compose configuration
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 75: Add All Microservices to Aspire
- [ ] Register Inventory API in App Host
- [ ] Register Notifications API in App Host
- [ ] Register UI in App Host
- [ ] Configure service-to-service communication
- [ ] Test end-to-end flow through Aspire orchestration
- [ ] Verify distributed tracing across all services
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 76: Aspire + SQL Database Integration
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

#### Day 80: Docker Basics + Integration Testing (Azure-first .NET)
> **Why integration testing now:** Before pushing real container images to ACR you need a reliable test suite
- [ ] Verify Docker Desktop running
- [ ] Create multi-stage Dockerfile for Orders API
- [ ] Build image: `docker build -t orderprocessing-api:local`
- [ ] Understand Aspire uses Docker under the hood
- [ ] 🆕 Add `Microsoft.AspNetCore.Mvc.Testing` + `Testcontainers.MsSql` + `Testcontainers.Redis` NuGet packages
- [ ] 🆕 Create `IntegrationTests` project with `WebApplicationFactory<Program>` test base
- [ ] 🆕 Write integration test: spin up SQL + Redis containers, run API, POST `/orders`, assert response
- [ ] 🆕 Add integration test step to GitHub Actions CI workflow (runs before pushing to ACR)
- [ ] **Time:** 3 hours | **Completed:** ___/___/___

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

### Week 12: Azure Container Apps (ACA) with Aspire Deployment
**Reference:** Containerization-ACA-Aspire-Learning-Path.md → Module 3

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
- [ ] Connect to Azure SQL Database (not Aspire-managed)
- [ ] Connect to Azure Cache for Redis (not Aspire-managed)
- [ ] Use Azure Key Vault for secrets in ACA
- [ ] Test production-ready configuration
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 93: Review & Compare
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
**Reference:** AZURE-TOP-7-SERVICES-ANALYSIS.md
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

#### Day 94: API Versioning — APIM + C# (Azure-first .NET)
- [ ] Configure version sets in APIM (header-based: `Api-Version: v1`)
- [ ] 🆕 Add `Asp.Versioning.Http` NuGet package (official API versioning for ASP.NET Core)
- [ ] 🆕 Configure `AddApiVersioning()` + `AddApiExplorer()` in `Program.cs`
- [ ] 🆕 Annotate controllers with `[ApiVersion("1.0")]` and `[ApiVersion("2.0")]`
- [ ] 🆕 Implement Problem Details RFC 7807 standardised error responses: `AddProblemDetails()` in `Program.cs`
- [ ] APIM backend updated to route to versioned ACA endpoints
- [ ] Test: `v1` endpoint returns old schema; `v2` endpoint returns expanded schema
- [ ] **Time:** 2.5 hours | **Completed:** ___/___/___

#### Day 95: Developer Portal
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
- [ ] Docker containerization (Next: Week 9)
- [ ] Azure Container Registry (ACR) (Week 10)
- [ ] Azure Container Apps (ACA) (Week 11)
- [ ] OpenTelemetry observability (Week 12)
- [ ] Key Vault secrets management (Week 13)
- [ ] Trivy vulnerability scanning (Week 13)
- [ ] SBOM generation (Week 13)
- [ ] Azure Front Door + WAF (Week 14)
- [ ] Blue/green deployments (Week 15)
- [ ] SRE practices (SLOs, runbooks) (Week 15)
- [ ] .NET Aspire (optional) (Week 16)

### Enterprise Practices Mastered
- [x] **OIDC authentication (no secrets in CI)** ✅
- [x] **Multi-environment deployments (dev/staging/prod)** ✅
- [x] **Infrastructure as Code with Bicep modules** ✅
- [ ] Supply chain security (scan, SBOM, sign) (Week 13)
- [ ] Centralized secrets with Key Vault (Week 13)
- [ ] Structured logging and tracing (Week 12)
- [ ] Alerting and incident response (Week 12)
- [ ] Cost management and budgets (Week 16)
- [ ] Azure Policy and governance (Week 13)
- [ ] Disaster recovery and rollback (Week 15)

---

## 📈 Progress Summary

**Total Days Planned:** 112 days (~16 weeks)  
**Days Completed:** 31 / 112  
**Percentage Complete:** 28%  

**Current Phase:** Azure Data & Resilience (Days 32-56)  
**Current Day:** Day 32 — Azure SQL Database via Bicep  
**Last Completed Task:** Day 31 extended — 9 GitHub Actions workflows live across dev/staging/prod; bootstrap summary with endpoints table; health check retries (60s wait + 3×60s attempts); parallel dispatch with 3-min lookup timeout (commit `b7ecbce`)  
**Next Milestone:** Deploy Azure SQL via Bicep, connect API with DefaultAzureCredential (Days 32-37)  

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

---

---

## 🚀 QUICK ACTION ITEMS (START HERE)

### 🔥 TODAY'S PRIORITY (Day 32 — Azure SQL Database)
**Goal:** Provision Azure SQL Database via Bicep and connect the Orders API with passwordless managed identity auth

**MUST DO TODAY:**
1. ⏳ **Create `infra/modules/sql.bicep`** — SQL Server + database module
2. ⏳ **Add SQL module to `infra/main.bicep`** with firewall rules
3. ⏳ **Deploy** via `az deployment group create -g rg-orderprocessing-dev -f infra/main.bicep -p infra/parameters/dev.json`
4. ⏳ **Configure EF Core migrations** against the deployed Azure SQL instance
5. ⏳ **Enable Managed Identity** on App Service and grant SQL access

**Why This Matters:**
- First real Azure data service connected to your app
- Sets up the passwordless auth pattern (`DefaultAzureCredential`) used for all subsequent Azure services
- Foundation for Service Bus, Cosmos DB, Key Vault patterns that follow

---

### This Week's Focus (Days 32-43: Azure SQL → Polly → Health Checks)
**Goal:** Connect the API to Azure SQL passwordlessly, add resilience with Polly, and expose health endpoints

**Sequence:**
1. Days 32-35: Azure SQL via Bicep + EF Core migrations + Managed Identity
2. Days 36-37: `DefaultAzureCredential` in C# — fully passwordless connection
3. Days 38-41: Polly retry + circuit breaker for transient failures
4. Days 42-43: ASP.NET Core Health Checks + App Service health probe integration

**Preparation for Service Bus (Days 48-50):**
- Azure Service Bus requires a namespace — Bicep template planned for Day 48
- The pub/sub C# pattern (Day 49) is the most critical .NET-in-Azure skill in this phase

### Resources You Have
✅ **Migration Strategy:** `Documentation/04-Enterprise-Architecture/ACA-Migration-Plan.md`  
✅ **Hands-on Guide:** `Documentation/02-Azure-Learning-Guides/Containerization-ACA-Aspire-Learning-Path.md`  
✅ **Current File:** This master curriculum for daily tracking

---

**Last Updated:** March 20, 2026  
**Next Review:** Weekly on Sundays  
**Progress:** 31/112 days (28% complete) — Day 32 starting
