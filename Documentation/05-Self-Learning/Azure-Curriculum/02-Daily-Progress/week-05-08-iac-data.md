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

**Detailed Activity:**
- Learned Bicep module structure: extract reusable resource definitions into `.bicep` files with `param`/`output` blocks
- Created `infra/modules/appservice.bicep` — reusable App Service + Plan module accepting env-specific params
- Referenced it from `infra/main.bicep` using `module name './modules/appservice.bicep' = { params: {...} }`
- Key concept: module outputs (e.g. `output appServiceId string = app.id`) allow cross-module resource wiring

#### Day 30: Parameter Files ✅
- [x] Create `dev.json`, `staging.json`, `prod.json`
- [x] Parameterize environment-specific values
- [x] Deploy to multiple environments
- [x] **Time:** 1 hour | **Completed:** ✅ Done

**Detailed Activity:**
- Created `infra/parameters/dev.json`, `staging.json`, `prod.json` with environment-specific SKU tiers and resource name suffixes
- Parameterized app name prefix, location, SQL tier, App Service SKU, Key Vault config
- Deployed to multiple environments by switching `--parameters` file — same Bicep, different configs
- Pattern: `az deployment sub create --parameters @parameters/dev.json`

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

**Detailed Activity:**
- Added `what-if` step in `infra-deploy.yml` so PR reviewers can see planned changes before merge
- Configured path-based push triggers for dev/staging/main branches (only fires when `infra/` changes)
- Added `workflow_dispatch` with input dropdowns — lets you trigger manually from GitHub UI without editing YAML
- Added `dryRun` boolean input: when `true`, runs `--what-if` only and skips real deployment
- Tested: triggered from Actions tab → selected environment=dev, dryRun=true → saw what-if diff in logs ✅
- Created `README-INFRA-DEPLOY.md` documenting the workflow and all input parameters

---

### Week 5-8 (continued): Azure Data & Resilience — Completed Days

#### Day 32: Azure SQL Database — Provision via Bicep ✅
- [x] Create `infra/modules/sql.bicep` (SQL Server + database)
- [x] Add SQL module to `infra/main.bicep` with firewall rules
- [x] Deploy via `az deployment sub create` — `orderprocessing-sql-dev` + `OrderProcessingSystem_Dev` live in Azure Portal
- [x] Verify database in Azure Portal ✅ confirmed in `rg-orderprocessing-dev`
- [x] **Time:** 1.5 hours | **Completed:** ✅

**Detailed Activity:**
- Created `infra/modules/sql.bicep` — defines `Microsoft.Sql/servers` + `databases` + firewall rules
- Added SQL module call in `infra/main.bicep`, passing admin credentials and environment-specific DB name
- Ran `az deployment sub create` → provisioned `orderprocessing-sql-dev.database.windows.net` in `rg-orderprocessing-dev`
- Database `OrderProcessingSystem_Dev` visible in Azure Portal ✅
- Firewall rule added for local IP (needed for EF migrations on Day 33)

#### Day 33: EF Core Migrations Against Azure SQL ✅
- [x] Configure EF Core connection string for Azure SQL
- [x] Run `dotnet ef migrations add InitialCreate`
- [x] Apply migrations: `dotnet ef database update` — all 6 migrations applied to `OrderProcessingSystem_Dev`
- [x] Seed test data and verify via Azure Portal Data Explorer — 120 Customers, 13 tables confirmed
- [x] **Time:** 1.5 hours | **Completed:** ✅

**Detailed Activity:**
- Updated `Resources/Configuration/sharedsettings.dev.json` with Azure SQL connection string for `orderprocessing-sql-dev.database.windows.net`
- Ran `dotnet ef migrations add InitialCreate --project Infrastructure --startup-project API` — generated first migration
- Applied all 6 migrations: `dotnet ef database update` → tables created in `OrderProcessingSystem_Dev`
- Confirmed via Azure Portal → SQL Database → Query editor: 13 tables created, 120 Customer rows seeded ✅
- Key command: `dotnet ef database update --connection "<azure-sql-connection-string>"`

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

**Detailed Activity:**

**1. SQL Connection Strings**
- Added connection strings in `sharedsettings.dev.json`, `sharedsettings.staging.json`, `sharedsettings.prod.json`
- Each environment points to its own Azure SQL server; local (`sharedsettings.local.json`) points to local SQL

**2. EF Core SQL Logging (StartupHelper.cs)**
- Added in `StartupHelper.cs` (Infrastructure project), guarded by `IsDevelopment()`:
```csharp
if (builder.Environment.IsDevelopment())
{
    options.LogTo(Console.WriteLine, LogLevel.Information)
           .EnableSensitiveDataLogging()
           .EnableDetailedErrors();
}
```

**3. Key Gotcha — `dev` ≠ `"Development"`**
- Azure App Service sets `ASPNETCORE_ENVIRONMENT=dev` (lowercase, matches branch name)
- `IsDevelopment()` checks for exact string `"Development"` — NOT `"dev"`
- Result: SQL logging is **OFF on Azure** — intentional (SQL params must not appear in Azure logs)
- SQL logging only fires locally when running with `--environment Development` (VS F5 or `dotnet run`)

**4. Actual Local Console Output Confirmed**
```
[03:23:48 INF] [dev] [Local] Request: GET /api/Customer/GetAllCustomersByName
info: RelationalEventId.CommandExecuted[20101]
      Executed DbCommand (20ms) [Parameters=[], CommandType='Text', CommandTimeout='30']
[03:23:48 INF] [dev] [Local] Response: 200 in 587.2204 ms
```

**5. Azure Swagger Verified**
- Opened `pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net/swagger`
- Called `GET /api/Customer/GetAllCustomersByName?name=at&pageNumber=1&pageSize=10` → 120 customers returned ✅

**6. Copilot Infrastructure Built**
- Created `.github/instructions/` skill files: ef-migrations, azure-workflows, bicep, curriculum, architecture
- Each auto-attaches context for relevant files via `applyTo:` pattern
- Created `docs/architecture/decisions/` ADR framework (ADR-000 template + ADR-001 through ADR-005)
- Created `/memories/architect-patterns.md`, `/memories/repo/azure-resources.md`, `/memories/repo/dotnet-conventions.md`
- Created `.github/prompts/day-complete.prompt.md` — auto-routing day-end updates to correct documents

**What this enables next:** Day 35 (Managed Identity for SQL) — replace SQL admin password in connection string with passwordless Azure AD token
