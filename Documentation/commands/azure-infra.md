# Azure Infrastructure & Workflow Commands

**Part of:** [QUICK-COMMAND-REFERENCE.md](../QUICK-COMMAND-REFERENCE.md)  
**Last Updated:** March 20, 2026

---

## 🔧 Azure CLI Commands

```powershell
# Login to Azure
az login

# Check current subscription
az account show

# List all subscriptions
az account list --output table

# Switch subscription
az account set --subscription "subscription-id-or-name"

# List resource groups
az group list --output table

# List resources in a resource group
az resource list --resource-group rg-orderprocessing-dev --output table

# Check OIDC app and credentials
az ad app list --display-name "GitHub-Actions-OIDC" --output table
az ad app federated-credential list --id <app-object-id>
```

---

## 🧪 Dry-Run Testing (No Azure Changes)

```powershell
# Test environment mapping
./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment dev
./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment staging
./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment prod
./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment all

# Validate workflow before running in GitHub
./Resources/Azure-Deployment/validate-workflow-config.ps1
```

---

## 🔑 GitHub Secrets Management

```powershell
# Set environment variable for GH CLI
$env:GH_TOKEN = "<your-personal-access-token>"

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

### **GH_PAT Repository Secret (if needed)**
```powershell
$owner = "pavanthakur"; $repo = "XYDataLabs.OrderProcessingSystem"
gh secret set GH_PAT --repo $owner/$repo
# Verify
gh secret list --repo $owner/$repo | Select-String GH_PAT
```

---

## ⚙️ Run Azure Workflows (GitHub CLI)

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

# Configure secrets for all environments:
gh workflow run "Azure Initial Setup" `
    --ref dev `
    -f environment=all `
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

# API-only deploy (most common — infra already exists):
gh workflow run "Azure Bootstrap & Deploy" `
    --ref dev `
    -f environment=dev `
    -f bootstrapInfra=false `
    -f deployApi=true `
    -f deployUi=false `
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

---

## 📋 Validation Script Details

### **validate-workflow-config.ps1**
Validates GitHub Actions workflow configurations  
**Use:** EVERY TIME before committing workflow changes
```powershell
./Resources/Azure-Deployment/validate-workflow-config.ps1
./Resources/Azure-Deployment/validate-workflow-config.ps1 -WorkflowFile ".github/workflows/custom.yml"
```
Checks: bootstrap env mappings, logging matches config, OIDC inputs, secrets environment selection

### **test-branch-env-mapping.ps1**
Dry-run test of branch-to-environment mapping  
**Use:** Before running Azure bootstrap workflow
```powershell
./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment dev
./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment all
```
Checks: parameter files exist + valid JSON, env values match expected config, resource group naming

### **validate-sharedsettings-diff.ps1**
Validates configuration consistency across environments  
**Use:** Before committing configuration file changes
```powershell
./Resources/Azure-Deployment/validate-sharedsettings-diff.ps1
# Exit 0 = All aligned | Exit 2 = Discrepancies found (review output)
```

---

## 🚀 Scenario: First-Time Azure Bootstrap
```powershell
# 1. Dry-run validation
./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment dev

# 2. Login to Azure
az login

# 3. Verify subscription
az account show

# 4. Go to GitHub Actions UI
# https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions

# 5. Run "Azure Initial Setup" workflow first (one-time OIDC + secrets)
# 6. Then run "Azure Bootstrap & Deploy" workflow
#    - Branch: dev | Environment: dev | Deploy API + UI
```

---

## 🆘 Emergency: Wrong Resources Created in Azure
```powershell
# 1. Delete resource group (DANGEROUS — confirm environment first!)
az group delete --name rg-orderprocessing-dev --yes --no-wait

# 2. Verify OIDC credentials
az ad app federated-credential list --id <app-object-id>

# 3. Delete specific credential
az ad app federated-credential delete --id <app-object-id> --federated-credential-id <credential-id>

# 4. Re-run bootstrap with correct configuration
```

---

## 🔍 Troubleshooting — Azure CLI Issues
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

## 📋 Pre-Flight Checklist — Before Azure Bootstrap
- [ ] `./Resources/Azure-Deployment/test-branch-env-mapping.ps1 -Environment dev` — Dry run
- [ ] Verify parameter files exist and are correct
- [ ] Check Azure subscription is correct (`az account show`)
- [ ] Ensure GH_PAT token is configured (for secrets)
- [ ] Review GitHub Actions workflow inputs before clicking "Run workflow"

## 📋 Pre-Flight Checklist — Before Deploying to Production
- [ ] All tests pass in dev environment
- [ ] All tests pass in staging environment
- [ ] Code review completed
- [ ] Documentation updated
- [ ] Backup plan ready
- [ ] Rollback procedure documented
