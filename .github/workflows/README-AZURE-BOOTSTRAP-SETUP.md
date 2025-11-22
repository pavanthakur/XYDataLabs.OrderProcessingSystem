# Azure Bootstrap Setup Workflow

## Overview

The **Generate GitHub App Token** workflow (`generate-github-app-token.yml`) replaces the previous `azure-bootstrap.yml` file for focused GitHub App token generation after Azure OIDC is confirmed.

## Workflow Name

**Name:** `Azure Bootstrap Setup`

This workflow is designed for manual execution via GitHub Actions UI.

## Quick Access

**Direct Link:** https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/workflows/generate-github-app-token.yml

## Running for Dev Profile with All Options Enabled

### Recommended Configuration

For a complete first-time setup of the dev environment with all features enabled:

1. Navigate to: **Actions → Azure Bootstrap Setup → Run workflow**

2. Configure the following settings:

| Parameter | Value | Description |
|-----------|-------|-------------|
| **Use workflow from** | `dev` | Branch to run from |
| **Target environment to bootstrap** | `dev` | Environment to set up |
| **Setup Azure OIDC** | ✅ `true` | Create Azure AD app and federated credentials |
| **Setup GitHub App** | ✅ `true` | Configure GitHub App (eliminates PAT expiration) |
| **Configure GitHub secrets** | ✅ `true` | Auto-configure repository secrets |
| **Bootstrap infrastructure** | ✅ `true` | Provision Azure resources |
| **Enable pre-deployment validation** | ✅ `true` | Enable validation checks |

3. Click **"Run workflow"** button

### What Happens

#### Phase 1: Validation (1 min)
- Validates all input parameters
- Displays configuration summary
- Checks environment selection

#### Phase 2: Azure OIDC Setup (2-3 min)
- Creates Azure AD app registration: `GitHub-Actions-OIDC`
- Sets up federated credentials for branch and environment
- Configures service principal with RBAC
- **Action Required:** Authenticate via device code

#### Phase 3: GitHub App Setup (5 min, manual)
- Guides you through GitHub App creation
- Provides step-by-step instructions
- Configures auto-expiring tokens
- **Action Required:** Follow on-screen instructions

#### Phase 4: Configure Secrets (1 min)
- Sets repository secrets automatically
- Configures environment secrets
- Verifies all credentials

#### Phase 5: Bootstrap Infrastructure (3-5 min)
- Creates resource group: `rg-orderprocessing-dev`
- Provisions App Service Plan (F1 Free tier)
- Deploys API Web App
- Deploys UI Web App
- Sets up Application Insights

#### Phase 6: Enable Validation (1 min)
- Updates infra-deploy.yml workflow
- Enables pre-deployment validation
- Commits changes to repository

### Expected Output

After successful completion, you will have:

#### Azure Resources
- ✅ Resource Group: `rg-orderprocessing-dev`
- ✅ App Service Plan: `asp-orderprocessing-dev` (F1 Free)
- ✅ API Web App: `pavanthakur-orderprocessing-api-xyapp-dev`
- ✅ UI Web App: `pavanthakur-orderprocessing-ui-xyapp-dev`
- ✅ Application Insights: `ai-orderprocessing-dev`

#### GitHub Configuration
- ✅ Repository secrets configured
- ✅ Environment secrets configured
- ✅ GitHub App installed (if enabled)
- ✅ Federated credentials created

#### Validation
- ✅ Pre-deployment validation enabled
- ✅ What-if analysis configured
- ✅ Parameter validation active

## Workflow Inputs

### Required Inputs

#### environment
- **Type:** Choice
- **Options:** `dev`, `staging`, `prod`, `all`
- **Description:** Target environment to bootstrap

### Optional Boolean Flags

#### setupOidc
- **Type:** Boolean
- **Default:** `false`
- **Description:** Setup Azure OIDC (first-time only)
- **When to use:** First run or when adding new environments

#### setupGitHubApp
- **Type:** Boolean
- **Default:** `false`
- **Description:** Setup GitHub App (one-time, eliminates PAT expiration)
- **When to use:** First run for zero-maintenance token management

#### configureSecrets
- **Type:** Boolean
- **Default:** `false`
- **Description:** Configure GitHub secrets (auto if GitHub App configured)
- **When to use:** After OIDC setup or when secrets are missing

#### bootstrapInfra
- **Type:** Boolean
- **Default:** `true`
- **Description:** Bootstrap infrastructure (App Services, etc.)
- **When to use:** Always enabled unless only updating credentials

#### enableValidation
- **Type:** Boolean
- **Default:** `true`
- **Description:** Enable pre-deployment validation after bootstrap
- **When to use:** After infrastructure is ready for deployments

## Workflow Jobs

1. **validate-inputs** - Validates all parameters and displays summary
2. **setup-oidc** - Creates Azure AD app and federated credentials
3. **setup-github-app** - Guides GitHub App setup (manual steps)
4. **configure-secrets** - Sets repository and environment secrets
5. **bootstrap-dev** - Provisions dev environment infrastructure
6. **bootstrap-staging** - Provisions staging environment infrastructure
7. **bootstrap-prod** - Provisions production environment infrastructure
8. **enable-validation** - Enables pre-deployment validation
9. **summary** - Generates final workflow summary

## Verification

### Check GitHub Secrets
Visit: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/settings/secrets/actions

Verify:
- ✅ `AZUREAPPSERVICE_CLIENTID`
- ✅ `AZUREAPPSERVICE_TENANTID`
- ✅ `AZUREAPPSERVICE_SUBSCRIPTIONID`

### Check Azure Resources
```powershell
# Login to Azure
az login

# List resource groups
az group list --query "[?starts_with(name, 'rg-orderprocessing')].name" -o table

# Check dev resources
az resource list --resource-group rg-orderprocessing-dev --query "[].{Name:name, Type:type}" -o table
```

### Check Federated Credentials
```powershell
# Get app details
az ad app list --display-name "GitHub-Actions-OIDC" --query "[0].{AppId:appId, ObjectId:id}" -o json

# List federated credentials
az ad app federated-credential list --id <app-object-id> --query "[].{Name:name, Subject:subject}" -o table
```

## Troubleshooting

### Issue: YAML Syntax Errors
**Solution:** The workflow has been validated and trailing spaces removed. If you encounter issues, run:
```bash
yamllint -d relaxed .github/workflows/generate-github-app-token.yml
```

### Issue: Device Code Timeout
**Solution:** 
- You have 3 minutes to authenticate
- Re-run the workflow if timeout occurs
- Use incognito mode if browser caches interfere

### Issue: GitHub App Setup Unclear
**Solution:** Follow detailed guide:
- Documentation: `Documentation/03-Configuration-Guides/GITHUB-APP-AUTHENTICATION.md`
- Takes 5 minutes one-time setup
- Skip if you prefer using PAT (requires renewal)

### Issue: Bootstrap Fails
**Solution:**
1. Check Azure subscription quotas
2. Verify you have Contributor role
3. Check region `centralindia` availability
4. Review bootstrap logs (auto-uploaded as artifacts)

### Issue: Secrets Not Configured
**Solution:**
- Verify GitHub App or PAT is configured
- Run with `configureSecrets: true`
- Or add secrets manually via GitHub settings

## Cost Considerations

### Dev Environment (F1 Free Tier)
- App Service Plan: **FREE**
- 2 Web Apps: **FREE** (shared hosting)
- Application Insights: **FREE** (up to 5GB/month)
- **Total Monthly Cost: $0** (within free limits)

### Staging Environment (B1 Tier)
- App Service Plan: ~$13/month
- Application Insights: ~$2/month (basic telemetry)
- **Total Monthly Cost: ~$15**

### Production Environment (P1v3 Tier)
- App Service Plan: ~$100/month
- Application Insights: ~$5/month (production telemetry)
- **Total Monthly Cost: ~$105**

## Related Documentation

- **Quick Start Guide:** `Documentation/QUICK-START-AZURE-BOOTSTRAP.md`
- **GitHub App Setup:** `Documentation/03-Configuration-Guides/GITHUB-APP-AUTHENTICATION.md`
- **Workflow Summary:** `Documentation/Bootstrap-Workflow-Summary.md`
- **Bootstrap Script:** `Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1`
- **OIDC Setup Script:** `Resources/Azure-Deployment/setup-github-oidc.ps1`

## Support

For issues or questions:
1. Check workflow run logs
2. Review downloaded bootstrap artifacts
3. Consult troubleshooting section above
4. Review Azure Portal for resource status
5. Check GitHub Actions logs for detailed error messages

---

**Last Updated:** 2025-11-22  
**Workflow Version:** 1.0  
**Maintainer:** Platform Team
