# Quick Command Reference Guide
**Last Updated:** March 20, 2026 (Day 34 + Copilot infrastructure session)

All commands in one place. Also available as topic-specific deep dives in this canonical `docs/reference/` subtree:

| Topic | File |
|-------|------|
| Git, validation, daily workflow | [git-workflow.md](git-workflow.md) |
| Azure CLI, Bicep, OIDC, GitHub workflows | [azure-infra.md](azure-infra.md) |
| Azure SQL, EF Core, sqlcmd | [azure-sql-ef.md](azure-sql-ef.md) |
| Local dev, dotnet run, Docker | [local-dev.md](local-dev.md) |

---

## 🚀 Daily Development Workflow

### **1. Start Your Day**
```powershell
# Navigate to project
cd Q:\GIT\TestAppXY_OrderProcessingSystem

# Check current branch and status
git status
git branch

# Pull latest changes
git pull origin dev

# Check for merge conflicts
git log --oneline --graph --all --decorate -10
```

### **2. Before Making Changes**
```powershell
# Create feature branch (optional but recommended)
git checkout -b feature/your-feature-name

# Verify you're on correct branch
git branch --show-current
```

---

## ✅ Validation Commands (CRITICAL — Use Before Every Commit)

### **Pre-Commit Validation Checklist**
```powershell
# 1. Validate workflow configurations (MANDATORY for workflow changes)
./Resources/Azure-Deployment/validate-workflow-config.ps1

# 2. Test branch-to-environment mapping (for infrastructure changes)
./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment dev

# 3. Validate documentation local links (when docs/ changed)
node scripts/validate-doc-links.js

# 4. Validate shared settings consistency (before config changes)
./Resources/Azure-Deployment/validate-sharedsettings-diff.ps1

# 5. Check for errors in solution (before committing code)
dotnet build XYDataLabs.OrderProcessingSystem.sln

# 6. Run unit tests (before committing code)
dotnet test XYDataLabs.OrderProcessingSystem.UnitTest/
```

### **Exit Code Interpretation**
- **Exit Code 0** = ✅ PASS - Safe to proceed
- **Exit Code 1** = ❌ FAIL - Fix issues before committing
- **Exit Code 2** = ⚠️ WARNING - Review discrepancies

---

## 📝 Git Workflow Commands

### **Standard Commit Flow**
```powershell
# 1. Check what files changed
git status

# 2. Review specific changes
git diff                                    # All changes
git diff .github/workflows/                 # Specific folder

# 3. Stage changes
git add .                                   # All files
git add .github/workflows/specific-file.yml # Specific file

# 4. Review staged changes
git diff --staged

# 5. Commit with descriptive message
git commit -m "feat: Add new feature description"
git commit -m "fix: Correct configuration bug"
git commit -m "docs: Update documentation"

# 6. Push to remote
git push origin dev
git push origin feature/your-feature-name
```

### **Sync Branches**
```powershell
# Sync dev with main
git checkout main
git pull origin main
git merge dev --no-ff -m "Merge dev changes to main"
git push origin main
git checkout dev

# Sync dev from main (get main updates into dev)
git checkout dev
git pull origin dev
git merge main --no-ff -m "Merge main updates into dev"
git push origin dev
```

### **Emergency Rollback**
```powershell
# Undo last commit (keep changes)
git reset --soft HEAD~1

# Undo last commit (discard changes) - DANGEROUS
git reset --hard HEAD~1

# Undo changes to specific file
git checkout HEAD -- filename

# View commit history to find rollback point
git log --oneline -10
git reset --hard <commit-hash>
```

---

## 🔧 Azure & Infrastructure Commands

### **Dry-Run Testing (No Azure Changes)**
```powershell
# Test environment mapping
./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment dev
./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment staging
./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment prod
./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment all

# Validate workflow before running in GitHub
./Resources/Azure-Deployment/validate-workflow-config.ps1
```

`test-branch-env-mapping.ps1` reads its defaults from `Resources/Azure-Deployment/branch-policy.json`.

### **Azure CLI Commands**
```powershell
# Login to Azure
az login

# Check current subscription
az account show

# List all subscriptions
az account list --output table

# Switch subscription
az account set --subscription "subscription-id-or-name"

# Check OIDC app and credentials
az ad app list --display-name "GitHub-Actions-OIDC" --output table
az ad app federated-credential list --id <app-object-id>

# List resource groups
az group list --output table

# List resources in a resource group
az resource list --resource-group rg-orderprocessing-dev --output table

### SQL provisioning helpers (repo scripts)

```powershell
# Retrieve SQL admin password from Key Vault (used by provisioning script when not provided)
az keyvault secret show --vault-name kv-orderprocessing-dev --name sql-admin-password --query value -o tsv

# Open local firewall for dev (script handles IP detection + cleanup)
.\Resources\Azure-Deployment\open-local-sql-firewall.ps1 -Environment dev

# Close local firewall when done
.\Resources\Azure-Deployment\open-local-sql-firewall.ps1 -Environment dev -Close
```
```

### **Run Azure Workflows (GitHub CLI)**
```powershell
# Authenticate gh if not already
gh auth login

# Verify workflow names exist
gh workflow list | Select-String "Azure Initial Setup|Azure Bootstrap"

# ─── Azure Initial Setup (Phase 0/1a/1b: OIDC + secrets) ───

# Run full initial setup on dev (recommended first-time):
gh workflow run "Azure Initial Setup" `
    --ref dev `
    -f environment=all `
    -f setupGitHubApp=true `
    -f setupOidc=true `
    -f configureSecrets=true

# Configure secrets only (OIDC already done):
gh workflow run "Azure Initial Setup" `
    --ref dev `
    -f environment=dev `
    -f setupGitHubApp=false `
    -f setupOidc=false `
    -f configureSecrets=true

# ─── Azure Bootstrap & Deploy (Phase 2 + Deploy + Phase X) ───

# Bootstrap dev (after initial setup):
gh workflow run "Azure Bootstrap & Deploy" `
    --ref dev `
    -f environment=dev `
    -f bootstrapInfra=true `
    -f deployApi=true `
    -f deployUi=true `
    -f cleanupInfra=false

# Cleanup dev environment (⚠️ DESTRUCTIVE — deletes all resources):
gh workflow run "Azure Bootstrap & Deploy" `
    --ref dev `
    -f environment=dev `
    -f cleanupInfra=true

# Monitor workflow runs
gh run list -L 5
gh run watch --exit-status
gh run view <run-id> --log
```

### **GitHub Secrets Management**
```powershell
# List repository secrets
gh secret list

# List environment secrets
gh secret list --env dev
gh secret list --env staging
gh secret list --env prod

# Set a secret
gh secret set SECRET_NAME --body "secret-value"
gh secret set SECRET_NAME --env dev --body "secret-value"
```

---

## 🗄️ Azure SQL Commands (Day 32+)

### **SQL Server & Database Info**
```powershell
# Get SQL Server FQDN
az sql server show `
  --name orderprocessing-sql-dev `
  --resource-group rg-orderprocessing-dev `
  --query fullyQualifiedDomainName -o tsv
# Output: orderprocessing-sql-dev.database.windows.net

# List SQL databases
az sql db list --server orderprocessing-sql-dev --resource-group rg-orderprocessing-dev --output table

# Check SQL Server firewall rules
az sql server firewall-rule list --server orderprocessing-sql-dev --resource-group rg-orderprocessing-dev --output table
```

### **Firewall — Open/Close for Local Development**
```powershell
# Detect your public IP
$myIp = (Invoke-RestMethod -Uri "https://api.ipify.org")
Write-Host "Your IP: $myIp"

# Add firewall rule for local machine
az sql server firewall-rule create `
  --server orderprocessing-sql-dev `
  --resource-group rg-orderprocessing-dev `
  --name "dev-machine" `
  --start-ip-address $myIp `
  --end-ip-address $myIp

# Remove firewall rule after local work (good practice)
az sql server firewall-rule delete `
  --server orderprocessing-sql-dev `
  --resource-group rg-orderprocessing-dev `
  --name "dev-machine"
```
> ⚠️ Always remove the firewall rule after finishing local work.

### **EF Core Migrations Against Azure SQL**
```powershell
cd q:\GIT\TestAppXY_OrderProcessingSystem

# Retrieve password from Key Vault (auto-generated by bootstrap — never hardcoded)
$sqlPwd = az keyvault secret show --vault-name kv-orderprocessing-dev --name sql-admin-password --query value -o tsv
$azureCs = "Server=tcp:orderprocessing-sql-dev.database.windows.net,1433;Initial Catalog=OrderProcessingSystem_Dev;User ID=sqladmin;Password=$sqlPwd;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

# Apply all pending migrations to Azure SQL
dotnet ef database update `
  --project XYDataLabs.OrderProcessingSystem.Infrastructure `
  --startup-project XYDataLabs.OrderProcessingSystem.API `
  --connection $azureCs

# Add a new migration
dotnet ef migrations add <MigrationName> `
  --project XYDataLabs.OrderProcessingSystem.Infrastructure `
  --startup-project XYDataLabs.OrderProcessingSystem.API

# List all applied migrations
dotnet ef migrations list `
  --project XYDataLabs.OrderProcessingSystem.Infrastructure `
  --startup-project XYDataLabs.OrderProcessingSystem.API
```

### **Verify Tables & Seed Data via sqlcmd**
```powershell
# List all tables
# Get password from KV first: $sqlPwd = az keyvault secret show --vault-name kv-orderprocessing-dev --name sql-admin-password --query value -o tsv
sqlcmd -S orderprocessing-sql-dev.database.windows.net `
  -d OrderProcessingSystem_Dev -U sqladmin -P $sqlPwd `
  -Q "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME" -N -C

# Check migration history
sqlcmd -S orderprocessing-sql-dev.database.windows.net `
  -d OrderProcessingSystem_Dev -U sqladmin -P $sqlPwd `
  -Q "SELECT MigrationId FROM __EFMigrationsHistory ORDER BY MigrationId" -N -C

# Check row counts
sqlcmd -S orderprocessing-sql-dev.database.windows.net `
  -d OrderProcessingSystem_Dev -U sqladmin -P $sqlPwd `
  -Q "SELECT 'Customers' AS [Table], COUNT(*) AS [Rows] FROM Customers UNION ALL SELECT 'Products', COUNT(*) FROM Products UNION ALL SELECT 'Orders', COUNT(*) FROM Orders" -N -C
```

### **SSMS Connection Details (dev)**
| Field | Value |
|---|---|
| Server | `orderprocessing-sql-dev.database.windows.net` |
| Database | `OrderProcessingSystem_Dev` |
| Auth | SQL Server Authentication |
| Login | `sqladmin` |
| Password | `az keyvault secret show --vault-name kv-orderprocessing-dev --name sql-admin-password --query value -o tsv` |

### **Day 33 Result (March 20, 2026)**
- Applied 6 migrations to `OrderProcessingSystem_Dev` ✅
- 13 tables created (Customers, Products, Orders, OrderProducts, BillingCustomers + more)
- 120 customers seeded ✅

---

## 🧪 Build & Test Commands

### **Solution Build**
```powershell
# Clean build
dotnet clean
dotnet build XYDataLabs.OrderProcessingSystem.sln

# Release build
dotnet build XYDataLabs.OrderProcessingSystem.sln --configuration Release

# Restore NuGet packages
dotnet restore
```

### **Run Tests**
```powershell
# Run all unit tests
dotnet test XYDataLabs.OrderProcessingSystem.UnitTest/

# Run tests with detailed output
dotnet test XYDataLabs.OrderProcessingSystem.UnitTest/ --verbosity detailed

# Run specific test
dotnet test --filter "FullyQualifiedName~TestMethodName"

# Generate test coverage report
dotnet test /p:CollectCoverage=true /p:CoverletOutputFormat=opencover
```

### **Run Applications Locally**
```powershell
# Run API (default: http://localhost:5010)
cd XYDataLabs.OrderProcessingSystem.API
dotnet run

# Run UI (default: http://localhost:5012)
cd XYDataLabs.OrderProcessingSystem.UI
dotnet run

# Run with specific environment
$env:ASPNETCORE_ENVIRONMENT = "Development"
dotnet run
```

> **Visual Studio (recommended for debugging):** Press F5 — sets `ASPNETCORE_ENVIRONMENT=Development` automatically.

### **Port Allocations**
| Mode | API | UI |
|------|-----|-----|
| Local VS (F5) | http://localhost:5010 | http://localhost:5012 |
| Docker dev | http://localhost:5020 | http://localhost:5022 |
| Docker stg | http://localhost:5030 | http://localhost:5032 |

---

## 🔍 EF Core SQL Logging — Local Dev Only

> **Why logging only fires locally:** Azure App Service has `ASPNETCORE_ENVIRONMENT=dev` (lowercase).  
> `IsDevelopment()` checks for the exact string `"Development"` — returns **false** on Azure.  
> SQL logging is intentionally OFF on Azure to prevent sensitive data in cloud logs.  
> Locally (Visual Studio F5), `IsDevelopment()` = **true** → logging fires.

**Expected console output when running locally:**
```
info: RelationalEventId.CommandExecuted[20101]
      Executed DbCommand (20ms) [Parameters=[], CommandType='Text', CommandTimeout='30']
      SELECT [c].[CustomerId], [c].[Name], [c].[Email]
      FROM [Customers] AS [c]
```

**Code location:** `XYDataLabs.OrderProcessingSystem.Infrastructure/StartupHelper.cs`
```csharp
if (builder.Environment.IsDevelopment())
{
    options.LogTo(Console.WriteLine, LogLevel.Information)
           .EnableSensitiveDataLogging()
           .EnableDetailedErrors();
}
```

---

## 🐳 Docker Commands

### **Project Docker Scripts (preferred)**
```powershell
# Start — dev environment
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile http

# Start — strict CI-grade startup
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile http -Strict

# Clean rebuild
.\Resources\Docker\start-docker.ps1 -Environment dev -Profile https -Reset
```

### **Docker Compose**
```powershell
# Start all services
docker-compose up -d

# Stop all services
docker-compose down

# View logs
docker-compose logs -f service-name

# Rebuild and start
docker-compose up -d --build
```

### **Docker Container Management**
```powershell
# List running containers
docker ps

# View logs
docker logs container-name --follow

# Remove container
docker rm -f container-name

# Clean up unused images
docker image prune -a
```

---

## 📊 Validation Script Details

### **validate-workflow-config.ps1**
**Purpose:** Validates GitHub Actions workflow configurations  
**When to use:** EVERY TIME before committing workflow changes
```powershell
./Resources/Azure-Deployment/validate-workflow-config.ps1
./Resources/Azure-Deployment/validate-workflow-config.ps1 -WorkflowFile ".github/workflows/custom.yml"
```

### **test-branch-env-mapping.ps1**
**Purpose:** Dry-run test of branch-to-environment mapping  
**When to use:** Before running Azure bootstrap workflow
```powershell
./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment dev
./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment all
```

### **validate-sharedsettings-diff.ps1**
**Purpose:** Validates configuration consistency across environments  
**When to use:** Before committing configuration file changes
```powershell
./Resources/Azure-Deployment/validate-sharedsettings-diff.ps1
# Exit 0 = All aligned | Exit 2 = Discrepancies (review output)
```

---

## 🔍 Troubleshooting Commands

### **Git Issues**
```powershell
# Check remote URL
git remote -v

# Fix remote URL
git remote set-url origin https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem.git

# Abort merge
git merge --abort
```

### **Build Issues**
```powershell
# Clear NuGet cache
dotnet nuget locals all --clear

# Clean and rebuild
dotnet clean
Remove-Item -Recurse -Force bin, obj
dotnet restore
dotnet build
```

### **Azure CLI Issues**
```powershell
az cache purge
az logout
az login
az --version
```

---

## 📋 Pre-Flight Checklist (Before Important Operations)

### **Before Committing Code Changes**
- [ ] `git status` - Review changed files
- [ ] `dotnet build` - Ensure solution builds
- [ ] `dotnet test` - Run unit tests
- [ ] `git diff` - Review actual changes
- [ ] Write descriptive commit message

### **Before Committing Workflow Changes**
- [ ] `./Resources/Azure-Deployment/validate-workflow-config.ps1` - MANDATORY
- [ ] Review validator output for all PASS
- [ ] Commit only if validator exits with code 0

### **Before Running Azure Bootstrap**
- [ ] `./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment dev` - Dry run
- [ ] Verify parameter files exist and are correct
- [ ] Check Azure subscription is correct (`az account show`)
- [ ] Review GitHub Actions workflow inputs before clicking "Run workflow"

### **Before Deploying to Production**
- [ ] All tests pass in dev + staging environments
- [ ] Code review completed
- [ ] Documentation updated
- [ ] Rollback procedure documented

---

## 🎯 Common Development Scenarios

### **Scenario 1: Updating Application Code**
```powershell
dotnet build
dotnet test
cd XYDataLabs.OrderProcessingSystem.API
dotnet run
# Then: git add . && git commit -m "feat: ..." && git push origin dev
```

### **Scenario 2: Updating Workflow Configuration**
```powershell
./Resources/Azure-Deployment/validate-workflow-config.ps1   # MANDATORY
# If exit 0: git add .github/workflows/ && git commit && git push
# If exit 1: Fix issues and re-run validator
```

### **Scenario 3: Updating Configuration Files**
```powershell
./Resources/Azure-Deployment/validate-sharedsettings-diff.ps1
# Review discrepancies, then: git add Resources/Configuration/ && git commit
```

### **Scenario 4: First-Time Azure Bootstrap**
```powershell
./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment dev
az login
az account show
# Then go to GitHub Actions UI:
# 1. Run "Azure Initial Setup" (one-time OIDC + secrets)
# 2. Run "Azure Bootstrap & Deploy" — branch: dev, environment: dev
```

### **Scenario 5: Syncing Branches**
```powershell
git checkout dev
git pull origin dev
./Resources/Azure-Deployment/validate-workflow-config.ps1  # If workflow changed
git checkout main
git pull origin main
git merge dev --no-ff -m "Merge: Release v1.2.3"
git push origin main
git checkout dev
```

---

## ⚡ Pre-Commit Checklist (Quick Reference)

### Code Changes
- [ ] `git status` — review changed files
- [ ] `dotnet build` — build passes
- [ ] `dotnet test` — tests pass
- [ ] `git diff` — review changes

### Workflow Changes (MANDATORY)
- [ ] `./Resources/Azure-Deployment/validate-workflow-config.ps1` — exit code 0
- [ ] Verify `bootstrap-dev` uses `dev` environment / `dev.json`
- [ ] Verify `bootstrap-staging` uses `staging` environment / `staging.json`
- [ ] Verify `bootstrap-prod` uses `prod` environment / `prod.json`
- [ ] DO NOT COMMIT if validator fails

### Before Azure Bootstrap
- [ ] `./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment dev` — dry run
- [ ] `az account show` — verify correct subscription
- [ ] Review workflow inputs carefully in GitHub UI

---

## 💰 Cost-Saving Rules

1. ✅ Always validate before committing workflow changes
2. ✅ Always dry-run before Azure deployments
3. ✅ Test locally before cloud deployment
4. ✅ Use dev environment for all experimentation
5. ✅ Prevention > Debugging — 2 seconds validation saves hours of debugging

---

## ⚠️ Red Flags to Watch For

When editing workflow files, these patterns indicate a misconfiguration:
- ❌ `prod` mentioned inside `bootstrap-dev` job
- ❌ `dev` mentioned inside `bootstrap-prod` job
- ❌ Logging messages don't match script parameters
- ❌ Parameter file (`dev.json`) doesn't match environment name
- ❌ Branch name (`main`) doesn't match job name `bootstrap-dev`

---

## 💡 Best Practices — Commit Messages

Use conventional commit format:
- `feat:` — New feature
- `fix:` — Bug fix
- `docs:` — Documentation only
- `refactor:` — Code refactoring
- `test:` — Adding tests
- `chore:` — Maintenance
- `perf:` — Performance improvement
- `Day N:` — Curriculum day completion

---

## 🆘 Emergency Commands

### **Workflow Failed — Rollback**
```powershell
git log --oneline -5
git reset --hard <commit-hash>
git push origin dev --force
./Resources/Azure-Deployment/validate-workflow-config.ps1
```

### **Wrong Resources Created in Azure**
```powershell
# Delete resource group (DANGEROUS — confirm environment first!)
az group delete --name rg-orderprocessing-dev --yes --no-wait
```

### **Build Completely Broken**
```powershell
git stash
git checkout <last-working-commit>
dotnet clean && dotnet build
# If works: git stash pop && git diff to investigate
```

---

## 🤖 Copilot Agent Prompts (VS Code Chat)

Reusable agent prompts in `.github/prompts/`. Run in VS Code Chat (`Ctrl+Shift+I` → Agent mode).

| Command | When to use | What it does |
|---------|-------------|--------------|
| `/XYDataLabs-day-complete` | End of every curriculum day | Routes updates to curriculum, commands files, ADRs, memory. Suggests commit. |
| `/XYDataLabs-sql-local-access` | After every fresh bootstrap/deploy | Opens/closes Azure SQL firewall for your local IP. Prints SSMS details. |

**How to run:** `Ctrl+Shift+I` → Agent mode → `/XYDataLabs-day-complete` → answer "What did you complete today?"

### **Routing Decision**
| What you did | Where it goes |
|--------------|---------------|
| Completed checklist item | `1_MASTER_CURRICULUM.md` |
| Ran a CLI command | `docs/reference/<topic>.md` |
| Chose technology X over Y | New `docs/architecture/decisions/ADR-NNN.md` |
| Learned reusable pattern | `/memories/architect-patterns.md` |
| New Azure resource/FQDN | `/memories/repo/azure-resources.md` |
| New .NET class/convention | `/memories/repo/dotnet-conventions.md` |
| Workflow/deployment gotcha | `/memories/repo/workflow-split.md` |

---

## 🔗 Important URLs

- **Repository:** https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem
- **Actions:** https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions
- **Azure Portal:** https://portal.azure.com
- **API (dev):** https://pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net/swagger
- **UI (dev):** https://pavanthakur-orderprocessing-ui-xyapp-dev.azurewebsites.net

---

## 🔄 Daily Workflow Summary

```powershell
# Morning: Start work
cd Q:\GIT\TestAppXY_OrderProcessingSystem
git checkout dev
git pull origin dev

# During: Make changes and validate frequently
dotnet build                    # After code changes
dotnet test                     # After code changes
./Resources/Azure-Deployment/validate-workflow-config.ps1  # After workflow changes

# Before commit: Final validation
git status
git diff
git add .
git commit -m "type: description"
git push origin dev
```

---

**Remember:** Prevention is cheaper than debugging!  
**Always validate before committing critical changes.**

---

## ✅ Pre-Commit Checklists (Quick Reference)

### Code Changes
- [ ] `git status` — review changed files
- [ ] `dotnet build` — build passes
- [ ] `dotnet test` — tests pass
- [ ] `git diff` — review changes

### Workflow Changes (MANDATORY)
- [ ] `./Resources/Azure-Deployment/validate-workflow-config.ps1` — exit code 0
- [ ] Verify `bootstrap-dev` uses `dev` environment / `dev.json`
- [ ] Verify `bootstrap-staging` uses `staging` environment / `staging.json`
- [ ] Verify `bootstrap-prod` uses `prod` environment / `prod.json`
- [ ] DO NOT COMMIT if validator fails

### Before Azure Bootstrap
- [ ] `./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment dev` — dry run
- [ ] `az account show` — verify correct subscription
- [ ] Review workflow inputs carefully in GitHub UI

### Before Deploying to Production
- [ ] All tests pass in dev + staging
- [ ] Code review completed
- [ ] Documentation updated
- [ ] Rollback procedure documented

---

## ⚠️ Red Flags (Workflow Misconfiguration)

- ❌ `prod` mentioned inside a `bootstrap-dev` job
- ❌ `dev` mentioned inside a `bootstrap-prod` job
- ❌ Logging messages don't match script parameters
- ❌ Parameter file (`dev.json`) doesn't match environment name
- ❌ Branch name (`main`) doesn't match job name `bootstrap-dev`

> See [git-workflow.md](git-workflow.md) for full troubleshooting steps.

---

## 🤖 Copilot Agent Prompts (VS Code Chat)

Reusable agent prompts stored in `.github/prompts/`. Type in VS Code Chat (`Ctrl+Shift+I` → Agent mode).

| Command | When to use | What it does |
|---------|-------------|--------------|
| `/XYDataLabs-day-complete` | End of every curriculum day | Routes updates to curriculum, commands files, ADRs, memory. Suggests commit. |
| `/XYDataLabs-sql-local-access` | After every fresh bootstrap/deploy | Opens/closes Azure SQL firewall for your local IP. Prints SSMS details. |

**How to run:** `Ctrl+Shift+I` → Agent mode → type `/XYDataLabs-day-complete` → answer "What did you complete today?"

### Routing Decision (quick ref)

| What you did | Where it goes |
|--------------|---------------|
| Completed checklist item | `1_MASTER_CURRICULUM.md` |
| Ran a CLI command | `docs/reference/<topic>.md` |
| Chose technology X over Y | New `docs/architecture/decisions/ADR-NNN.md` |
| Learned reusable pattern | `/memories/architect-patterns.md` |
| New Azure resource/FQDN | `/memories/repo/azure-resources.md` |
| New .NET class/convention | `/memories/repo/dotnet-conventions.md` |
| Workflow/deployment gotcha | `/memories/repo/workflow-split.md` |

---

## � GitHub App Commands

### Validate & Setup
```powershell
# Validate existing GitHub App configuration
.\scripts\validate-github-app-config.ps1 -Detailed

# Create new GitHub App from manifest
.\scripts\setup-github-app-from-manifest.ps1
```

### Workflows
- **Azure Initial Setup:** Environment = `all`, Setup OIDC = `true` (first time), Configure Secrets = `true`
- **Azure Bootstrap & Deploy:** Environment = `dev`/`staging`/`prod`, Bootstrap Infrastructure = `true`, Deploy API/UI = `true`

### Required Permissions

| Permission | Level | Notes |
|------------|-------|-------|
| Actions | Read and write | |
| **Secrets** | **Read and write** | **⚠️ CRITICAL** |
| Workflows | Read and write | |
| Pull requests | Read and write | |
| Administration | Read and write | |
| **Environments** | **Read and write** | **⚠️ CRITICAL** |
| Contents | Read | |
| Metadata | Read | Automatic |

### Required Secrets

**Repository level (once):** `APP_ID`, `APP_PRIVATE_KEY`, `AZUREAPPSERVICE_CLIENTID`, `AZUREAPPSERVICE_TENANTID`, `AZUREAPPSERVICE_SUBSCRIPTIONID`

**Per environment (dev, staging, prod):** `AZUREAPPSERVICE_CLIENTID`, `AZUREAPPSERVICE_TENANTID`, `AZUREAPPSERVICE_SUBSCRIPTIONID`

### Delete & Recreate Flow
1. **Backup:** `.\scripts\validate-github-app-config.ps1 -Detailed > backup.txt`
2. **Delete:** https://github.com/settings/apps → Advanced → Delete
3. **Recreate:** `.\scripts\setup-github-app-from-manifest.ps1`
4. **Update Secrets:** `APP_ID` and `APP_PRIVATE_KEY`
5. **Reinstall:** Install app on repository
6. **Configure:** Run Azure Initial Setup workflow
7. **Validate:** `.\scripts\validate-github-app-config.ps1 -Detailed`

### Troubleshooting
- **App token generation failed** → Check app is installed on repository, verify `APP_ID`/`APP_PRIVATE_KEY`, ensure "Secrets: Read and write" permission
- **Environment secrets failed** → Add "Environments: Read and write" permission, re-approve on installation page
- **Validation shows failures** → Run `gh auth login`, check https://github.com/settings/installations

### Important URLs

| Resource | URL |
|----------|-----|
| Create GitHub App | https://github.com/settings/apps/new |
| Manage Apps | https://github.com/settings/apps |
| App Installations | https://github.com/settings/installations |
| Repository Secrets | Repository → Settings → Secrets → Actions |
| Environments | Repository → Settings → Environments |

---

## �💰 Cost-Saving Rules

1. ✅ Always validate before committing workflow changes
2. ✅ Always dry-run before Azure deployments
3. ✅ Test locally before cloud deployment
4. ✅ Use dev environment for all experimentation
5. ✅ Prevention > Debugging — 2 seconds validation saves hours of debugging

---

## 🔗 Important URLs

- **Repository:** https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem
- **Actions:** https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions
- **Azure Portal:** https://portal.azure.com
- **API (dev):** https://pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net/swagger
- **UI (dev):** https://pavanthakur-orderprocessing-ui-xyapp-dev.azurewebsites.net

---

## 📚 Related Documentation

- `docs/reference/` — all detailed command reference files (this index points here)
- `Resources/Azure-Deployment/` — all Azure automation scripts
- `Resources/Configuration/` — sharedsettings per environment
- `.github/workflows/README.md` — workflow overview and secrets
- `TROUBLESHOOTING-INDEX.md` — quick links for common errors

---

**Remember:** Prevention is cheaper than debugging. Always validate before committing critical changes.
