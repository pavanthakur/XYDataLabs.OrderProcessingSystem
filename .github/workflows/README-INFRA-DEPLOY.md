# Infrastructure Deployment Workflow Guide

## 🎯 Overview

The `infra-deploy.yml` workflow deploys the active Azure infrastructure surface using Bicep templates.

> **Phase 10 note:** This guide describes the active Azure Container Apps deployment path for Phase 10. Legacy App Service references remain only for historical compatibility and should not be treated as the current target runtime model.

It supports three execution modes:

1. **Manual deployment** (workflow_dispatch) - Full control via GitHub UI
2. **Automatic deployment** (push to branches) - Branch-based deployment
3. **Validation** (pull requests) - What-if analysis only

---

## 🚀 Manual Deployment (Recommended for Testing)

### How to Run from GitHub UI

1. **Navigate to Actions Tab:**
   - Go to: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions
   - Find: "Deploy Azure Infrastructure" workflow

2. **Click "Run workflow" button** (top right)

3. **Configure Parameters:**

   | Parameter | Description | Options | Default |
   |-----------|-------------|---------|---------|
   | **Environment** | Target environment | dev, staging, prod | dev |
   | **Location** | Azure region | Any region string | centralindia |
   | **Dry Run** | What-if only (no deploy) | true/false | true |
   | **Public Domain** | Optional DNS suffix for friendly aliases | Any real domain suffix | empty |
   | **Bind Aliases** | Enable alias planning / binding checks | true/false | false |
   | **Alias Mode** | Choose direct ACA binding or front-door planning | direct / frontdoor | direct |

4. **Run Types:**

   **🧪 Dry Run (What-If Analysis):**
   - Set `Dry Run` = `true`
   - Reviews changes without deploying
   - Safe to run anytime
   - No Azure resources created/modified

   **🚀 Real Deployment:**
   - Set `Dry Run` = `false`
   - Deploys actual infrastructure
   - Creates/updates Azure resources
   - **Use carefully!**

   **Current Azure Deployment:**
   - Uses `infra/main.phase10.bicep` and `infra/parameters/phase10-<env>.json`
   - Resources follow the environment-suffixed naming pattern so Phase X cleanup can remove the matching stack
   - Gateway, Orders, Inventory, Notifications, and UI are deployed as separate Container Apps with separate images, matching the split-service Docker validation lane
   - The workflow summary shows transport-stack outputs
   - If `Bind Aliases` is enabled, provide a real `Public Domain` so the workflow can derive env-aware public names like `api-dev.contoso.com`

**Shared contract with local Docker validation:**
- same environment suffix pattern (`dev`, `staging`, `prod`)
- same split-service shape (gateway/orders/inventory/notifications/UI)
- same cleanup symmetry (`appname-env` resources can be torn down safely)
- different public URL style only at the hosting layer: local Docker uses fixed localhost ports, Azure Container Apps uses generated ingress plus optional aliases

**Related validation gate:**
- `phase10-docker-dev-http-e2e.yml` runs the same hook-based Docker Dev HTTP sequence in CI and uploads the matching `TestResults/Playwright/phase10-docker-http` artifacts.
- Use the hook as the merge gate for the local Docker validation chain, and use `infra-deploy.yml` for Azure Container Apps deployment and alias planning.

---

## 📋 Example Scenarios

### Scenario 1: Test Infrastructure Changes (Safe)
```
Environment: dev
Location: centralindia
Dry Run: TRUE ✅
```
**Result:** Shows what would be deployed, no actual changes

### Scenario 2: Deploy Dev Environment
```
Environment: dev
Location: centralindia
Dry Run: FALSE ⚠️
```
**Result:** Creates dev environment in Azure

### Scenario 3: Deploy Staging
```
Environment: staging
Location: centralindia
Dry Run: FALSE ⚠️
```
**Result:** Creates separate staging environment

---

## 🔄 Automatic Deployment (Push-Based)

When you push to specific branches:

| Branch | Environment | Parameter File | Trigger |
|--------|-------------|----------------|---------|
| `dev` | dev | `infra/parameters/phase10-dev.json` | Any push to `infra/**` |
| `staging` | staging | `infra/parameters/phase10-staging.json` | Any push to `infra/**` |
| `main` | prod | `infra/parameters/phase10-prod.json` | Any push to `infra/**` |

**Example:**
```bash
# Make changes to Bicep files
git add infra/main.phase10.bicep
git commit -m "Update infrastructure"
git push origin dev  # Triggers automatic deployment
```

---

## 🔍 Validation (Pull Requests)

When you create a PR with infra changes:

1. Workflow runs automatically
2. Detects the active infrastructure files and runs the matching `what-if`
3. Shows predicted changes in PR comments
4. **No actual deployment** occurs

**Example:**
```bash
git checkout -b feature/add-storage
# Make changes to infra
git push origin feature/add-storage
# Open PR to dev → Validation runs
```

---

## 📊 Deployment Outputs

After successful deployment, the workflow provides:

### GitHub Actions Summary
- Environment details
- Deployment name
- Resource links
- Next steps

### Available Outputs
- **Resource Group Name:** `rg-orderprocessing-{env}`
- **Service Bus Namespace:** `sb-orderprocessing-{env}`
- **Log Analytics Workspace:** workspace name
- **Managed Environment:** container apps environment
- **Gateway / Orders / Inventory / Notifications / UI:** container app names
- **Function App:** function host name
- **Key Vault:** vault name
- **App Insights Name:** `ai-orderprocessing-{env}`

- Resource Group
- Service Bus Namespace
- Log Analytics Workspace
- Managed Environment
- Gateway / Orders / Inventory / Notifications / UI container app names
- Function App
- Key Vault
- App Insights

---

## 🛠️ Prerequisites

### Required GitHub Secrets
These must be configured in repository settings:

| Secret Name | Description | How to Get |
|-------------|-------------|------------|
| `AZUREAPPSERVICE_CLIENTID` | App Registration Client ID | Run `setup-github-oidc.ps1` |
| `AZUREAPPSERVICE_TENANTID` | Azure AD Tenant ID | `az account show --query tenantId -o tsv` |
| `AZUREAPPSERVICE_SUBSCRIPTIONID` | Azure Subscription ID | `az account show --query id -o tsv` |

**Setup Command:**
```powershell
# From project root
.\Resources\Azure-Deployment\setup-github-oidc.ps1 -Environment dev
```

### Azure Permissions
The service principal needs:
- **Contributor** role on subscription (for resource creation)
- **(Optional)** Directory permissions for identity module

---

## 🧪 Testing Strategy

### Step 1: Dry Run Everything First
```
Always start with Dry Run = TRUE
Review what-if output carefully
Check for unexpected changes
```

### Step 2: Deploy to Dev
```
Environment: dev
Dry Run: FALSE
Verify in Azure Portal
Test endpoints
```

### Step 3: Promote to Higher Environments
```
If dev works → deploy staging
If staging works → deploy prod
```

---

## ⚠️ Important Notes

### Identity Module Limitation
The `identity.bicep` module requires a **User-Assigned Managed Identity** with Microsoft Graph permissions. 

**Current Workaround:**
1. Set `Enable Identity = false` in manual runs
2. Run `setup-github-oidc.ps1` script manually instead
3. Or create the UAMI with proper permissions before deploying

**Why:** Bicep deployment scripts need elevated permissions to create App Registrations and federated credentials.

### Cost Considerations

| SKU | Cost | Best For |
|-----|------|----------|
| F1 | Free | Dev/testing (limited) |
| B1 | ~$13/month | Dev/small apps |
| B2 | ~$26/month | Staging |
| S1 | ~$69/month | Production |
| P1v3 | ~$146/month | High-performance prod |

**Tip:** Always use F1 or B1 for learning/dev!

### Resource Naming
Phase 10 resources are named with the environment-suffixed pattern:
```
{component}-{environment}
```

Examples:
```
orderprocessing-gate-dev
orderprocessing-ui-dev
sb-orderprocessing-dev
kv-orderprocessing-dev
```

This keeps deployment and cleanup aligned with the exact environment that was deployed.

---

## 🐛 Troubleshooting

### Issue: "Deployment script failed"
**Cause:** Identity module needs managed identity  
**Solution:** Set `Enable Identity = false` or use `setup-github-oidc.ps1`

### Issue: "What-if shows unexpected deletions"
**Cause:** Parameter mismatch  
**Solution:** Review parameter values, ensure they match existing resources

### Issue: "Unauthorized to perform action"
**Cause:** Missing RBAC permissions  
**Solution:** Verify service principal has Contributor role

### Issue: "Name already taken"
**Cause:** Resource name collision  
**Solution:** Check the environment suffix and ensure the target stack was cleaned up before redeploying

---

## 📚 Related Documentation

- **Migration Plan:** `docs/guides/deployment/aca-migration-plan.md`
- **Bicep README:** `infra/README.md`
- **OIDC Setup:** `Resources/Azure-Deployment/README.md`
- **Master Curriculum:** `docs/learning/curriculum/1_MASTER_CURRICULUM.md`

---

## 🎓 Learning Path

This workflow corresponds to:
- **Day 29-31:** Bicep modules and infrastructure deployment
- **Week 5-8:** Infrastructure as Code & CI/CD hardening
- **Phase 2:** Enterprise App Service Deployment

**Next Steps:**
1. Run dry run to understand what-if output
2. Deploy dev environment
3. Verify resources in Azure Portal
4. Move to containerization (Week 9)

---

## 📞 Quick Commands

### Check Workflow Status
```bash
gh workflow list
gh workflow view "Deploy Azure Infrastructure"
gh run list --workflow=infra-deploy.yml
```

### Trigger Manual Run (via CLI)
```bash
gh workflow run infra-deploy.yml \
  -f environment=dev \
  -f location=centralindia \
  -f appServiceSku=F1 \
  -f enableIdentity=false \
  -f dryRun=true
```

### View Latest Run
```bash
gh run view
```

---

**Last Updated:** November 21, 2025  
**Status:** ✅ Ready for manual testing
