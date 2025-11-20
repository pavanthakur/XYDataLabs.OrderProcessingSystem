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
- ✅ GitHub Actions CI/CD workflows
- ✅ Bicep Infrastructure as Code (modules + parameters)
- ✅ Multi-environment setup (dev/staging/prod)

**🔥 YOUR NEXT 3 PRIORITIES:**

### Priority 1: Complete Azure Fundamentals (Days 32-56)
**Why:** Build strong foundation before containers  
**Tasks:**
- Days 32-40: Azure SQL Database, Entity Framework migrations
- Days 41-48: Azure Functions, Event Grid, Service Bus
- Days 49-56: Azure Key Vault, security best practices

### Priority 2: Start Docker Journey (Days 57-63) - Week 9
**Why:** Core skill for ACA migration  
**Starting Point:** See "Week 9: Docker & Containerization Fundamentals" below  
**First Steps:**
1. Install Docker Desktop
2. Run your first container: `docker run hello-world`
3. Dockerize your API with multi-stage Dockerfile
4. Test locally before Azure deployment

### Priority 3: Create ACA Migration Plan Timeline
**Why:** Know your full journey ahead  
**Action:** Review the complete 16-week plan below and set realistic dates

---

## 📚 Document Navigation

**This is your ONE source of truth.** Track all progress here.

### Primary Learning Documents
1. **This Document (MASTER_CURRICULUM.md)** - Your daily tracker and curriculum overview
2. **[Azure_Learning_Guide_Complete.md](./Azure_Learning_Guide_Complete.md)** - Foundational Azure concepts and early deployment
3. **[ACA Migration Plan](../../04-Enterprise-Architecture/ACA-Migration-Plan.md)** - Enterprise migration roadmap (17 phases)
4. **[Containerization Learning Path](../../02-Azure-Learning-Guides/Containerization-ACA-Aspire-Learning-Path.md)** - Hands-on Docker, ACR, ACA (8 modules)

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

### Week 1-2: Azure Fundamentals
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

### Week 3-4: App Service & OIDC Deployment
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

### Week 5-8: Infrastructure as Code & CI/CD Hardening
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

#### Day 31: GitHub Actions - Infra Deployment ✅
**Reference:** `.github/workflows/infra-deploy.yml`
- [x] Add what-if step for PR reviews
- [x] Deploy on branch push (dev/staging/main)
- [x] Validate deployments
- [x] **Time:** 2 hours | **Completed:** ✅ Done

#### Day 32-56: Continue Azure_Learning_Guide_Complete.md curriculum
*(Serverless, databases, security, monitoring - follow existing guide)*

---

### Week 9: Docker & Containerization Fundamentals
**Reference:** Containerization-ACA-Aspire-Learning-Path.md → Module 1

#### Day 57: Docker Installation & Hello World
- [ ] Verify Docker Desktop running
- [ ] Run `docker run hello-world`
- [ ] Understand images, containers, registries
- [ ] **Time:** 1 hour | **Completed:** ___/___/___

#### Day 58: Multi-Stage Dockerfiles
- [ ] Study multi-stage build pattern
- [ ] Create Dockerfile for API (Task 1.1)
- [ ] Build image: `docker build -t orderprocessing-api:local`
- [ ] **Time:** 1.5 hours | **Completed:** ___/___/___

#### Day 59: Run API Container Locally
- [ ] Run API container: `docker run -p 8080:8080`
- [ ] Test health endpoint: `curl localhost:8080/health`
- [ ] View logs: `docker logs <container>`
- [ ] **Time:** 1 hour | **Completed:** ___/___/___

#### Day 60: Dockerize UI
- [ ] Create Dockerfile for UI (Task 1.2)
- [ ] Build and run UI container on port 8081
- [ ] Configure API_BASE_URL env var
- [ ] **Time:** 1.5 hours | **Completed:** ___/___/___

#### Day 61: Docker Compose
- [ ] Create `docker-compose.yml` (Task 1.3)
- [ ] Run full stack: `docker-compose up`
- [ ] Test API → UI integration
- [ ] **Time:** 1.5 hours | **Completed:** ___/___/___

#### Day 62: Docker Best Practices
- [ ] Add `.dockerignore`
- [ ] Optimize layer caching
- [ ] Add health checks to Dockerfiles
- [ ] **Time:** 1 hour | **Completed:** ___/___/___

#### Day 63: Review & Lab
- [ ] Rebuild all images from scratch
- [ ] Document image sizes and build times
- [ ] Weekend deep dive: explore Docker networking
- [ ] **Time:** 2-3 hours | **Completed:** ___/___/___

---

### Week 10: Azure Container Registry (ACR)
**Reference:** Containerization-ACA-Aspire-Learning-Path.md → Module 2

#### Day 64: Provision ACR via Bicep
- [ ] Create `infra/modules/acr.bicep` (Task 2.1)
- [ ] Add ACR to `infra/main.bicep`
- [ ] Deploy: `az deployment sub create`
- [ ] **Time:** 1.5 hours | **Completed:** ___/___/___

#### Day 65: ACR Authentication
- [ ] Login to ACR: `az acr login --name <acr>`
- [ ] Tag image: `docker tag <image> <acr>.azurecr.io/<image>:v1`
- [ ] Push image: `docker push <acr>.azurecr.io/<image>:v1`
- [ ] **Time:** 1 hour | **Completed:** ___/___/___

#### Day 66: CI/CD - Build & Push Containers
**Reference:** Task 2.2
- [ ] Create `.github/workflows/container-build.yml`
- [ ] Add OIDC login step
- [ ] Build and push API image on commit
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 67: Push UI Image via CI
- [ ] Extend workflow to build UI
- [ ] Tag images with `:sha` and `:latest`
- [ ] Verify images in ACR Portal
- [ ] **Time:** 1.5 hours | **Completed:** ___/___/___

#### Day 68: Image Tagging Strategy
- [ ] Implement semantic versioning tags
- [ ] Add branch-based tags (dev, staging, prod)
- [ ] Document tagging conventions
- [ ] **Time:** 1 hour | **Completed:** ___/___/___

#### Day 69: ACR Security & Access
- [ ] Disable admin account (already done in Bicep)
- [ ] Assign AcrPull role to Managed Identity
- [ ] Test pull without admin credentials
- [ ] **Time:** 1 hour | **Completed:** ___/___/___

#### Day 70: Review & Lab
- [ ] Clean up old images in ACR
- [ ] Set up ACR retention policy
- [ ] Weekend: Explore ACR tasks and geo-replication
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

---

### Week 11: Azure Container Apps (ACA) Environment
**Reference:** Containerization-ACA-Aspire-Learning-Path.md → Module 3

#### Day 71: Log Analytics Workspace
**Reference:** ACA-Migration-Plan.md → Phase 3
- [ ] Create LAW via CLI or Bicep
- [ ] Understand workspace structure and queries
- [ ] Write first KQL query
- [ ] **Time:** 1.5 hours | **Completed:** ___/___/___

#### Day 72: ACA Environment Bicep Module
**Reference:** Task 3.1
- [ ] Create `infra/modules/aca/managedEnvironment.bicep`
- [ ] Wire LAW to ACA environment
- [ ] Deploy ACA environment
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 73: Container App Module
**Reference:** Task 3.2
- [ ] Create `infra/modules/aca/containerApp.bicep`
- [ ] Define ingress, scaling, resources
- [ ] Understand revision modes
- [ ] **Time:** 1.5 hours | **Completed:** ___/___/___

#### Day 74: Deploy API to ACA
**Reference:** Task 3.3
- [ ] Update `infra/main.bicep` to include API Container App
- [ ] Set minReplicas=1, maxReplicas=5
- [ ] Deploy and get FQDN output
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 75: Test API on ACA
- [ ] Access API via HTTPS FQDN
- [ ] View logs in Log Analytics
- [ ] Test autoscaling under load (optional)
- [ ] **Time:** 1.5 hours | **Completed:** ___/___/___

#### Day 76: Deploy UI to ACA
- [ ] Add UI Container App module to Bicep
- [ ] Configure API_BASE_URL env var pointing to API FQDN
- [ ] Deploy UI, test end-to-end
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 77: Review & Lab
- [ ] Compare App Service vs ACA (cost, performance, features)
- [ ] Document ACA ingress patterns
- [ ] Weekend: Experiment with internal ingress and VNET integration
- [ ] **Time:** 2-3 hours | **Completed:** ___/___/___

---

### Week 12: Observability & OpenTelemetry
**Reference:** Containerization-ACA-Aspire-Learning-Path.md → Module 4

#### Day 78: Install OpenTelemetry Packages
**Reference:** Task 4.1
- [ ] Add NuGet packages to API project
- [ ] Configure OpenTelemetry in `Program.cs`
- [ ] Wire to Application Insights connection string
- [ ] **Time:** 1 hour | **Completed:** ___/___/___

#### Day 79: Deploy & Verify Telemetry
- [ ] Rebuild API with OTel, push to ACR
- [ ] Deploy new revision to ACA
- [ ] View traces in Application Insights Transaction Search
- [ ] **Time:** 1.5 hours | **Completed:** ___/___/___

#### Day 80: Custom Metrics & Distributed Tracing
- [ ] Add custom spans and metrics
- [ ] Test distributed tracing (UI → API)
- [ ] Create Application Map in App Insights
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

#### Day 81: Log Analytics Queries
- [ ] Write KQL queries for container logs
- [ ] Filter by app, severity, time range
- [ ] Create saved queries
- [ ] **Time:** 1.5 hours | **Completed:** ___/___/___

#### Day 82: Alerts & Action Groups
**Reference:** ACA-Migration-Plan.md → Phase 3
- [ ] Create Action Group (email notification)
- [ ] Set metric alert (CPU > 80%)
- [ ] Set log alert (error rate threshold)
- [ ] **Time:** 1 hour | **Completed:** ___/___/___

#### Day 83: Workbooks & Dashboards
**Reference:** ACA-Migration-Plan.md → Phase 12b
- [ ] Create Azure Monitor workbook
- [ ] Add charts: request rate, latency, errors
- [ ] Pin to Azure Dashboard
- [ ] **Time:** 1.5 hours | **Completed:** ___/___/___

#### Day 84: Review & Lab
- [ ] Trigger alerts intentionally (load test)
- [ ] Analyze end-to-end transaction in App Insights
- [ ] Weekend: Set up availability tests (synthetic monitoring)
- [ ] **Time:** 2 hours | **Completed:** ___/___/___

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

#### Day 91: Review & Lab
- [ ] Remediate vulnerabilities found by Trivy
- [ ] Test Key Vault secret rotation
- [ ] Weekend: Set up Managed Identity for downstream services
- [ ] **Time:** 2-3 hours | **Completed:** ___/___/___

---

### Week 14: Networking & Edge
**Reference:** Containerization-ACA-Aspire-Learning-Path.md → Module 6 + ACA-Migration-Plan.md → Phase 7b

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

### Week 15: Reliability & SRE
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

### Week 16: .NET Aspire & Final Migration
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

**Current Phase:** Week 5-8: Infrastructure as Code & CI/CD Hardening  
**Current Week:** Week 5 (Days 29-35)  
**Last Completed Task:** GitHub Actions OIDC workflows created, Bicep infra scaffold completed  
**Next Milestone:** Complete Bicep modules and multi-environment deployment (Days 29-31)  

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

### This Week's Focus
**Goal:** Strengthen Azure fundamentals before moving to containers

**Day 32-35 (This Week):**
1. ⏳ Set up Azure SQL Database
2. ⏳ Configure Entity Framework migrations
3. ⏳ Deploy database via Bicep
4. ⏳ Test connection from App Service

**Preparation for Docker (Week 9):**
- 📖 Read: Docker basics in `Containerization-ACA-Aspire-Learning-Path.md`
- 📥 Install: Docker Desktop for Windows
- 📝 Review: Your existing Dockerfiles (if any)

### Resources You Have
✅ **Migration Strategy:** `Documentation/04-Enterprise-Architecture/ACA-Migration-Plan.md`  
✅ **Hands-on Guide:** `Documentation/02-Azure-Learning-Guides/Containerization-ACA-Aspire-Learning-Path.md`  
✅ **Current File:** This master curriculum for daily tracking

---

**Last Updated:** November 20, 2025  
**Next Review:** Weekly on Sundays  
**Progress:** 31/112 days (28% complete)
