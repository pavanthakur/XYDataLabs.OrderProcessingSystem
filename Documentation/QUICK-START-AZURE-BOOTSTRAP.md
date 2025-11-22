# 🚀 Azure Bootstrap - Quick Start Guide

## One-Click Azure Setup

This workflow automates everything from OIDC setup to infrastructure provisioning.

### 📍 Access the Workflow

**Direct Link**: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/workflows/azure-bootstrap.yml

Or navigate: **GitHub → Actions → Azure Bootstrap Setup**

---

## 🎯 First-Time Complete Setup

### Step 1: Run the Workflow

Click **"Run workflow"** button with these settings:

| Setting | Value | Description |
|---------|-------|-------------|
| **Use workflow from** | `dev` | Use dev branch |
| **Target environment** | `all` | Bootstrap all environments at once |
| **Setup OIDC** | ✅ `true` | Create Azure AD app (first-time only) |
| **Configure GitHub secrets** | ✅ `true` | Auto-configure repo secrets |
| **Bootstrap infrastructure** | ✅ `true` | Provision Azure resources |
| **Enable validation** | ✅ `true` | Enable pre-deployment checks |

### Step 2: Authenticate to Azure

1. Workflow will pause and display device code
2. Open https://microsoft.com/devicelogin
3. Enter the code shown in workflow logs
4. Sign in with your Azure account

### Step 3: Wait for Completion

- ⏱️ **Estimated time**: 10-15 minutes (for all environments)
- 📊 **Monitor**: Watch real-time logs in GitHub Actions
- 📦 **Artifacts**: Bootstrap logs auto-uploaded (30-day retention)

### Step 4: Verify Success

Check the workflow summary for:
- ✅ All jobs completed successfully
- ✅ GitHub secrets configured
- ✅ Azure resources created
- ✅ Validation enabled

---

## 🔄 Common Scenarios

### Scenario A: Dev Profile - All Options Enabled (Recommended)
```yaml
Environment: dev
Setup OIDC: ✅ true
Setup GitHub App: ✅ true
Configure secrets: ✅ true
Bootstrap infrastructure: ✅ true
Enable validation: ✅ true
```
**Time**: ~5-7 minutes  
**Use Case**: Complete first-time setup for dev environment with all features enabled

**What this does:**
- ✅ Creates Azure OIDC credentials for authentication
- ✅ Guides you through GitHub App setup (eliminates PAT expiration)
- ✅ Auto-configures all required GitHub secrets
- ✅ Provisions complete Azure infrastructure (App Services, App Insights)
- ✅ Enables pre-deployment validation checks

**Prerequisites:**
- Azure subscription with Contributor role
- GitHub repository admin access
- 5 minutes for GitHub App setup (one-time, optional but recommended)

### Scenario B: Dev Only (Quick Test - Skip GitHub App)
```yaml
Environment: dev
Setup OIDC: ✅ true
Setup GitHub App: ❌ false  # Skip for faster setup
Configure secrets: ✅ true
Bootstrap infrastructure: ✅ true
Enable validation: ❌ false  # Skip for manual testing
```
**Time**: ~5 minutes

---

### Scenario C: Add Staging Later
```yaml
Environment: staging
Setup OIDC: ❌ false  # Already done
Configure secrets: ❌ false  # Already done
Bootstrap infrastructure: ✅ true
Enable validation: ✅ true
```
**Time**: ~5 minutes

---

### Scenario D: Re-bootstrap Failed Environment
```yaml
Environment: dev
Setup OIDC: ❌ false
Configure secrets: ❌ false
Bootstrap infrastructure: ✅ true
Enable validation: ❌ false  # Keep validation setting unchanged
```
**Time**: ~5 minutes

---

## 📋 What Gets Created

### Azure AD (OIDC)
- **App Registration**: `GitHub-Actions-OIDC`
- **Federated Credentials**: 
  - Branch-based: dev, staging, main
  - Environment-based: dev, staging, prod
- **Service Principal**: Auto-created with RBAC

### GitHub Secrets
- `AZUREAPPSERVICE_CLIENTID`
- `AZUREAPPSERVICE_TENANTID`
- `AZUREAPPSERVICE_SUBSCRIPTIONID`

### Azure Resources (Per Environment)

**Dev Environment** (SKU: F1 Free):
- Resource Group: `rg-orderprocessing-dev`
- App Service Plan: `asp-orderprocessing-dev` (F1)
- API Web App: `pavanthakur-orderprocessing-api-xyapp-dev`
- UI Web App: `pavanthakur-orderprocessing-ui-xyapp-dev`
- App Insights: `ai-orderprocessing-dev`

**Staging Environment** (SKU: B1):
- Resource Group: `rg-orderprocessing-stg`
- App Service Plan: `asp-orderprocessing-stg` (B1)
- API Web App: `pavanthakur-orderprocessing-api-xyapp-stg`
- UI Web App: `pavanthakur-orderprocessing-ui-xyapp-stg`
- App Insights: `ai-orderprocessing-stg`

**Production Environment** (SKU: P1v3):
- Resource Group: `rg-orderprocessing-prod`
- App Service Plan: `asp-orderprocessing-prod` (P1v3)
- API Web App: `pavanthakur-orderprocessing-api-xyapp-prod`
- UI Web App: `pavanthakur-orderprocessing-ui-xyapp-prod`
- App Insights: `ai-orderprocessing-prod`

---

## ✅ Verification Checklist

After workflow completes, verify:

### 1. GitHub Secrets
Visit: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/settings/secrets/actions

Should see:
- ✅ AZUREAPPSERVICE_CLIENTID
- ✅ AZUREAPPSERVICE_TENANTID
- ✅ AZUREAPPSERVICE_SUBSCRIPTIONID

### 2. Azure AD App
```powershell
az ad app list --display-name "GitHub-Actions-OIDC"
```
Should return app with federated credentials.

### 3. Azure Resources
Visit: https://portal.azure.com

Navigate to resource groups:
- ✅ `rg-orderprocessing-dev` (if dev selected)
- ✅ `rg-orderprocessing-stg` (if staging selected)
- ✅ `rg-orderprocessing-prod` (if prod selected)

Each resource group should contain:
- App Service Plan
- 2 Web Apps (API + UI)
- Application Insights

### 4. Pre-Deployment Validation
Check: `.github/workflows/infra-deploy.yml`

Should see:
```yaml
pre-validate:
  if: (github.event_name == 'push') || ...  # Active condition
  
deploy:
  needs: pre-validate  # Uncommented dependency
```

---

## 🔧 Troubleshooting

### Issue: Device Code Timeout
**Solution**: Re-run workflow. You have 15 minutes to authenticate.

### Issue: "App already exists"
**Solution**: Normal! Workflow reuses existing app. Verify federated credentials are correct.

### Issue: GitHub Secrets Failed
**Solution**: Add manually:
1. Go to: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/settings/secrets/actions
2. Click "New repository secret"
3. Add values from workflow logs (OIDC setup job output)

### Issue: Resource Creation Timeout
**Solution**: 
- Check Azure subscription quotas
- Verify region `centralindia` availability
- Re-run bootstrap job only (disable OIDC/secrets)

### Issue: RBAC Assignment Failed
**Solution**: Wait 5 minutes for Azure AD propagation, then re-run.

---

## 🚀 Next Steps After Bootstrap

### 1. Test Infrastructure Deployment
```bash
# Make a change to trigger deployment
echo "test" >> infra/parameters/dev.json
git add infra/parameters/dev.json
git commit -m "test: trigger deployment workflow"
git push
```

### 2. Monitor Deployment
Visit: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions

Should see:
- ✅ Pre-deployment validation runs
- ✅ What-if analysis artifacts
- ✅ Infrastructure deployment

### 3. Deploy Application Code
Run application deployment workflows:
- API deployment workflow
- UI deployment workflow

### 4. Configure Telemetry
Follow: `Documentation/02-Azure-Learning-Guides/Telemetry-Quick-Start.md`

### 5. Verify Endpoints
- **Dev API**: https://pavanthakur-orderprocessing-api-xyapp-dev.azurewebsites.net
- **Dev UI**: https://pavanthakur-orderprocessing-ui-xyapp-dev.azurewebsites.net

---

## 📚 Documentation

- **Full Documentation**: `.github/workflows/README-AZURE-BOOTSTRAP.md`
- **Workflow File**: `.github/workflows/azure-bootstrap.yml`
- **Setup Script**: `Resources/Azure-Deployment/setup-github-oidc.ps1`
- **Bootstrap Script**: `Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1`

---

## 💡 Pro Tips

1. **Parallel Bootstrapping**: Select `environment: all` to provision dev/staging/prod simultaneously
2. **Cost Optimization**: Start with `dev` only (F1 Free tier) for testing
3. **Validation Toggle**: Disable validation during initial testing, enable once stable
4. **Log Artifacts**: Always download bootstrap logs for troubleshooting
5. **Idempotent**: Safe to re-run workflow - it skips existing resources

---

**Ready to start?** 

👉 **Click here**: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/workflows/azure-bootstrap.yml

Then click **"Run workflow"** button (top-right, green button)
