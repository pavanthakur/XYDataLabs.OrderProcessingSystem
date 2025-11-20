# Infrastructure Deployment Workflow Guide

## 🎯 Overview

The `infra-deploy.yml` workflow deploys Azure infrastructure using Bicep templates. It supports three deployment modes:

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
   | **App Service SKU** | App Service tier | F1, B1, B2, S1, P1v3 | F1 |
   | **Enable Identity** | OIDC identity setup | true/false | true |
   | **Dry Run** | What-if only (no deploy) | true/false | true |

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

---

## 📋 Example Scenarios

### Scenario 1: Test Infrastructure Changes (Safe)
```
Environment: dev
Location: centralindia
App Service SKU: F1
Enable Identity: true
Dry Run: TRUE ✅
```
**Result:** Shows what would be deployed, no actual changes

### Scenario 2: Deploy Dev Environment
```
Environment: dev
Location: centralindia
App Service SKU: F1
Enable Identity: true
Dry Run: FALSE ⚠️
```
**Result:** Creates dev environment in Azure

### Scenario 3: Upgrade to Paid Tier
```
Environment: dev
Location: centralindia
App Service SKU: B1 (instead of F1)
Enable Identity: true
Dry Run: FALSE ⚠️
```
**Result:** Upgrades App Service Plan (incurs cost!)

### Scenario 4: Deploy Staging
```
Environment: staging
Location: centralindia
App Service SKU: B2
Enable Identity: true
Dry Run: FALSE ⚠️
```
**Result:** Creates separate staging environment

---

## 🔄 Automatic Deployment (Push-Based)

When you push to specific branches:

| Branch | Environment | Parameter File | Trigger |
|--------|-------------|----------------|---------|
| `dev` | dev | `infra/parameters/dev.json` | Any push to `infra/**` |
| `staging` | staging | `infra/parameters/staging.json` | Any push to `infra/**` |
| `main` | prod | `infra/parameters/prod.json` | Any push to `infra/**` |

**Example:**
```bash
# Make changes to Bicep files
git add infra/main.bicep
git commit -m "Update infrastructure"
git push origin dev  # Triggers automatic deployment
```

---

## 🔍 Validation (Pull Requests)

When you create a PR with infra changes:

1. Workflow runs automatically
2. Executes `az deployment sub what-if`
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
- **API Hostname:** `{owner}-orderprocessing-api-xyapp-{env}.azurewebsites.net`
- **UI Hostname:** `{owner}-orderprocessing-ui-xyapp-{env}.azurewebsites.net`
- **App Insights Name:** `ai-orderprocessing-{env}`

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
Resources are named with pattern:
```
{githubOwner}-{baseName}-{component}-{environment}
```

Example:
```
pavanthakur-orderprocessing-api-xyapp-dev
```

This ensures global uniqueness for App Service names.

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
**Cause:** App Service name collision  
**Solution:** Change `githubOwner` parameter or `baseName`

---

## 📚 Related Documentation

- **Migration Plan:** `Documentation/04-Enterprise-Architecture/ACA-Migration-Plan.md`
- **Bicep README:** `infra/README.md`
- **OIDC Setup:** `Resources/Azure-Deployment/README.md`
- **Master Curriculum:** `Documentation/05-Self-Learning/Azure-Curriculum/1_MASTER_CURRICULUM.md`

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
