# Archive: Weeks 5-8 — IaC, CI/CD Hardening + Azure SQL Baseline (Days 29-34)
**Archived:** 20/03/2026 | **Status:** ✅ All Complete
**Source:** 1_MASTER_CURRICULUM.md — Week 5-8 block (up to and including Day 34)

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

#### Day 31: GitHub Actions - Infra Deployment ✅ (Extended)
**Reference:** `.github/workflows/infra-deploy.yml` + `README-INFRA-DEPLOY.md` + `AZURE_DEPLOYMENT_GUIDE.md` (Manual workflow trigger & dry run parameters section)
- [x] Add what-if step for PR reviews
- [x] Deploy on branch push (dev/staging/main)
- [x] Validate deployments
- [x] **Enhanced:** Added workflow_dispatch for manual runs
- [x] **Enhanced:** Interactive parameter selection via GitHub UI
- [x] **Enhanced:** Dry run mode for safe testing
- [x] **TODO TODAY:** Test manual workflow with dry run
- [x] **TODO TODAY:** Review what-if output
- [x] **Optional:** Deploy with dry run = false
- [x] **Time:** 2 hours | **Completed:** ✅

---

### Week 5-8 (continued): Azure Data & Resilience — Completed Days

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
