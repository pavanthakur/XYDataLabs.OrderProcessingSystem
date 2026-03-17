# Quick Command Reference Guide
**Last Updated:** November 21, 2025

This guide provides essential commands for daily development, validation, and documentation tasks to ensure smooth workflow and prevent costly errors.

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

## ✅ Validation Commands (CRITICAL - Use Before Every Commit)

### **Pre-Commit Validation Checklist**

```powershell
# 1. Validate workflow configurations (MANDATORY for workflow changes)
./Resources/Azure-Deployment/validate-workflow-config.ps1

# 2. Test branch-to-environment mapping (for infrastructure changes)
./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment dev

# 3. Validate shared settings consistency (before config changes)
./Resources/Azure-Deployment/validate-sharedsettings-diff.ps1

# 4. Check for errors in solution (before committing code)
dotnet build XYDataLabs.OrderProcessingSystem.sln

# 5. Run unit tests (before committing code)
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
git diff generate-github-app-token.yml      # Specific file

# 3. Stage changes
git add .                                   # All files
git add .github/workflows/generate-github-app-token.yml  # Specific file

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
```

### **GitHub Secrets Management**
```powershell
# Set environment variable for GH CLI
$env:GH_TOKEN = "<your-personal-access-token>"

# List repository secrets (requires GH_PAT)
gh secret list

# List environment secrets
gh secret list --env dev
gh secret list --env staging
gh secret list --env prod

# Set a secret
gh secret set SECRET_NAME --body "secret-value"
gh secret set SECRET_NAME --env dev --body "secret-value"
```

### **Run Azure Bootstrap (GitHub CLI)**
```powershell
# Prerequisites:
# - GitHub CLI installed: https://cli.github.com/
# - Authenticated: this uses GH_PAT or your gh auth session

# (Optional) Authenticate gh if not already
gh auth login

# Verify workflow name exists
gh workflow list | Select-String "Azure Bootstrap Setup"

# Run on dev with full setup (recommended first-time):
gh workflow run "Azure Bootstrap Setup" `
	--ref dev `
	-f environment=dev `
	-f setupOidc=true `
	-f setupGitHubApp=true `
	-f configureSecrets=true `
	-f bootstrapInfra=true `
	-f cleanupInfra=false

# Run secrets configuration only (use when OIDC is already set):
gh workflow run "Azure Bootstrap Setup" `
	--ref dev `
	-f environment=dev `
	-f setupOidc=false `
	-f setupGitHubApp=false `
	-f configureSecrets=true `
	-f bootstrapInfra=false `
	-f cleanupInfra=false

# Run for all environments (advanced; ensure OIDC + secrets ready):
gh workflow run "Azure Bootstrap Setup" `
	--ref main `
	-f environment=all `
	-f setupOidc=false `
	-f setupGitHubApp=false `
	-f configureSecrets=true `
	-f bootstrapInfra=true `
	-f cleanupInfra=false

# Cleanup dev environment (⚠️ DESTRUCTIVE — deletes all resources):
gh workflow run "Azure Bootstrap Setup" `
	--ref dev `
	-f environment=dev `
	-f cleanupInfra=true

# Check latest runs
gh run list -L 5

# Watch the most recent run interactively
gh run watch --exit-status

# View logs for a specific run
gh run view <run-id> --log
```

### **GH_PAT Repository Secret (if needed)**
```powershell
# Option 1 (UI):
#   Settings → Secrets and variables → Actions → New repository secret → Name: GH_PAT

# Option 2 (CLI): set GH_PAT at repository scope (value will not echo)
$owner = "pavanthakur"; $repo = "XYDataLabs.OrderProcessingSystem"
# Paste the PAT value when prompted (or use --body "<token>" cautiously)
cmd /c "set /p X=Enter GH_PAT value: & gh secret set GH_PAT --repo %owner%/%repo% --body %X%"

# Verify secret exists
gh secret list --repo $owner/$repo | Select-String GH_PAT
```

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
# Run API (default: https://localhost:5001)
cd XYDataLabs.OrderProcessingSystem.API
dotnet run

# Run UI (default: https://localhost:5002)
cd XYDataLabs.OrderProcessingSystem.UI
dotnet run

# Run with specific environment
dotnet run --environment Development
dotnet run --environment Staging
dotnet run --environment Production
```

---

## 🐳 Docker Commands

### **Docker Container Management**
```powershell
# List running containers
docker ps

# List all containers (including stopped)
docker ps -a

# Start/Stop containers
docker start container-name
docker stop container-name

# View logs
docker logs container-name
docker logs container-name --follow       # Follow logs in real-time

# Remove container
docker rm container-name
docker rm -f container-name               # Force remove running container
```

### **Docker Image Management**
```powershell
# List images
docker images

# Build image
docker build -t app-name:tag .

# Remove image
docker rmi image-name:tag

# Clean up unused images
docker image prune -a
```

### **Docker Compose**
```powershell
# Start all services
docker-compose up -d

# Stop all services
docker-compose down

# View logs
docker-compose logs
docker-compose logs -f service-name

# Rebuild and start
docker-compose up -d --build
```

---

## 📊 Validation Script Details

### **validate-workflow-config.ps1**
**Purpose:** Validates GitHub Actions workflow configurations  
**When to use:** EVERY TIME before committing workflow changes  
**What it checks:**
- ✅ Bootstrap-dev calls `-Environment dev`
- ✅ Bootstrap-staging calls `-Environment staging`
- ✅ Bootstrap-prod calls `-Environment prod`
- ✅ Logging messages match configurations
- ✅ OIDC setup uses dynamic inputs
- ✅ Configure-secrets respects environment selection

```powershell
# Basic usage
./Resources/Azure-Deployment/validate-workflow-config.ps1

# Custom workflow file
./Resources/Azure-Deployment/validate-workflow-config.ps1 -WorkflowFile ".github/workflows/custom.yml"
```

### **test-branch-env-mapping.ps1**
**Purpose:** Dry-run test of branch-to-environment mapping  
**When to use:** Before running Azure bootstrap workflow  
**What it validates:**
- ✅ Parameter files exist and are valid JSON
- ✅ Environment values match expected configuration
- ✅ OIDC subject patterns are correct
- ✅ Resource group naming is consistent

```powershell
# Test single environment
./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment dev

# Test all environments
./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment all
```

### **validate-sharedsettings-diff.ps1**
**Purpose:** Validates configuration consistency across environments  
**When to use:** Before committing configuration file changes  
**What it checks:**
- ✅ Detects missing configuration keys
- ✅ Identifies value discrepancies between environments
- ✅ Reports nested object differences

```powershell
# Basic usage
./Resources/Azure-Deployment/validate-sharedsettings-diff.ps1

# Exit codes:
# 0 = All aligned
# 2 = Discrepancies found (review output)
```

---

## 🔍 Troubleshooting Commands

### **Git Issues**
```powershell
# Check remote URL
git remote -v

# Fix remote URL
git remote set-url origin https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem.git

# Resolve merge conflicts
git status                           # See conflicted files
# Edit files to resolve conflicts
git add .
git commit -m "Resolve merge conflicts"

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
# Clear Azure CLI cache
az cache purge

# Re-login
az logout
az login

# Check Azure CLI version
az --version
az upgrade
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
- [ ] `git diff .github/workflows/` - Review workflow changes
- [ ] Manually verify environment mappings
- [ ] Commit only if validator exits with code 0

### **Before Running Azure Bootstrap**
- [ ] `./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment dev` - Dry run
- [ ] Verify parameter files exist and are correct
- [ ] Check Azure subscription is correct (`az account show`)
- [ ] Ensure GH_PAT token is configured (for secrets)
- [ ] Review GitHub Actions workflow inputs before clicking "Run workflow"

### **Before Deploying to Production**
- [ ] All tests pass in dev environment
- [ ] All tests pass in staging environment
- [ ] Code review completed
- [ ] Documentation updated
- [ ] Backup plan ready
- [ ] Rollback procedure documented

---

## 🎯 Common Development Scenarios

### **Scenario 1: Updating Application Code**
```powershell
# 1. Make code changes in Visual Studio/VS Code
# 2. Build and test locally
dotnet build
dotnet test

# 3. Run locally to verify
cd XYDataLabs.OrderProcessingSystem.API
dotnet run

# 4. Commit changes
git add .
git commit -m "feat: Add new order validation logic"
git push origin dev
```

### **Scenario 2: Updating Workflow Configuration**
```powershell
# 1. Make workflow changes in .github/workflows/
# 2. MANDATORY validation
./Resources/Azure-Deployment/validate-workflow-config.ps1

# 3. If validator passes (exit code 0)
git add .github/workflows/
git commit -m "fix: Update bootstrap-dev configuration"
git push origin dev

# 4. If validator fails (exit code 1) - DO NOT COMMIT
# Fix issues and re-run validator
```

### **Scenario 3: Updating Configuration Files**
```powershell
# 1. Edit configuration in Resources/Configuration/
# 2. Validate consistency
./Resources/Azure-Deployment/validate-sharedsettings-diff.ps1

# 3. Review discrepancies (if any)
# 4. Commit changes
git add Resources/Configuration/
git commit -m "config: Update database connection strings"
git push origin dev
```

### **Scenario 4: First-Time Azure Bootstrap**
```powershell
# 1. Dry-run validation
./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment dev

# 2. Login to Azure
az login

# 3. Verify subscription
az account show

# 4. Go to GitHub Actions UI
# https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions

# 5. Run "Azure Bootstrap Setup" workflow
# - Select branch: dev
# - Select environment: dev

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
# - Check: Setup OIDC ✅
# - Check: Configure Secrets ✅
# - Check: Bootstrap Infrastructure ✅
# - Check: Enable Validation ✅

# 6. Monitor workflow execution
# 7. Verify resources created in Azure Portal
```

### **Scenario 5: Syncing Branches**
```powershell
# From dev to main (after testing)
git checkout dev
git pull origin dev
./Resources/Azure-Deployment/validate-workflow-config.ps1  # If workflow changed
git checkout main
git pull origin main
git merge dev --no-ff -m "Merge: Release v1.2.3"
git push origin main
git checkout dev

# From main to dev (get hotfixes)
git checkout dev
git pull origin dev
git merge main --no-ff -m "Merge: Hotfix from main"
git push origin dev
```

---

## 💡 Best Practices Reminders

### **Git Commit Messages**
Use conventional commit format:
- `feat: Add new feature` - New feature
- `fix: Correct bug in order processing` - Bug fix
- `docs: Update API documentation` - Documentation only
- `refactor: Restructure payment module` - Code refactoring
- `test: Add unit tests for validation` - Tests
- `chore: Update dependencies` - Maintenance
- `perf: Improve database query performance` - Performance

### **Validation Frequency**
| Action | Validation Required | Command |
|--------|-------------------|---------|
| Code changes | Build + Test | `dotnet build && dotnet test` |
| Workflow changes | **MANDATORY** | `./Resources/Azure-Deployment/validate-workflow-config.ps1` |
| Config changes | Recommended | `./Resources/Azure-Deployment/validate-sharedsettings-diff.ps1` |
| Before Azure deploy | **MANDATORY** | `./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment dev` |

### **Cost-Saving Tips**
- ✅ Always run dry-run tests before Azure deployments
- ✅ Always validate workflows before committing
- ✅ Test locally before deploying to cloud
- ✅ Use dev environment for testing, not prod
- ✅ Monitor Azure costs regularly: `az consumption usage list`

---

## 🆘 Emergency Commands

### **Workflow Failed - Rollback**
```powershell
# 1. Check commit history
git log --oneline -5

# 2. Revert to last working commit
git reset --hard <commit-hash>
git push origin dev --force

# 3. Verify with validator
./Resources/Azure-Deployment/validate-workflow-config.ps1
```

### **Wrong Resources Created in Azure**
```powershell
# 1. Delete resource group (DANGEROUS - confirm environment first!)
az group delete --name rg-orderprocessing-dev --yes --no-wait

# 2. Verify OIDC credentials
az ad app federated-credential list --id <app-object-id>

# 3. Delete specific credential
az ad app federated-credential delete --id <app-object-id> --federated-credential-id <credential-id>

# 4. Re-run bootstrap with correct configuration
```

### **Build Completely Broken**
```powershell
# 1. Stash current changes
git stash

# 2. Get last working version
git checkout <last-working-commit>

# 3. Test build
dotnet clean
dotnet build

# 4. If works, investigate changes
git stash pop
git diff
```

---

## 📚 Additional Resources

### **Documentation Files**
- `Documentation/HOW-TO-AVOID-CONFIG-ERRORS.md` - Error prevention guide
- `Documentation/README.md` - Project overview
- `.github/workflows/generate-github-app-token.yml` - GitHub App token + OIDC workflow
- `.github/workflows/infra-deploy.yml` - Infrastructure deployment

### **Scripts Location**
- `Resources/Azure-Deployment/` - All Azure automation scripts
- `Resources/Configuration/` - Application configuration files
- `Resources/Database/` - Database scripts and migrations

### **Important URLs**
- Repository: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem
- Actions: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions
- Azure Portal: https://portal.azure.com

---

## 🔄 Daily Workflow Summary

```powershell
# Morning: Start work
cd Q:\GIT\TestAppXY_OrderProcessingSystem
git checkout dev
git pull origin dev

# During: Make changes and validate frequently
# ... make changes ...
dotnet build                    # After code changes
dotnet test                     # After code changes
./Resources/Azure-Deployment/validate-workflow-config.ps1  # After workflow changes

# Before commit: Final validation
git status
git diff
# Run appropriate validators
git add .
git commit -m "type: description"
git push origin dev

# End of day: Sync if needed
git checkout main
git merge dev --no-ff
git push origin main
git checkout dev
```

---

**Remember:** Prevention is cheaper than debugging!  
**Always validate before committing critical changes.**  
**When in doubt, run the validator.**

---

*Save this file for quick reference. Update it as you discover new useful commands.*
