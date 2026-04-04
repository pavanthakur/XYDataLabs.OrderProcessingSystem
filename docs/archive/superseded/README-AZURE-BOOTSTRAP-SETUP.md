# Azure Bootstrap Setup Workflow

> **⚠️ This document is superseded.** The workflow has been split into two focused workflows:
>
> - **[Azure Initial Setup](README-AZURE-INITIAL-SETUP.md)** (`azure-initial-setup.yml`) — Phase 0 (GitHub App), Phase 1a (OIDC), Phase 1b (secrets)
> - **[Azure Bootstrap & Deploy](README-AZURE-BOOTSTRAP.md)** (`azure-bootstrap.yml`) — Phase 2 (infrastructure), API/UI deploy, Phase X (cleanup)
>
> See those READMEs for current documentation.

---

*The content below is preserved for historical reference but may be outdated.*

## Overview (Historical)

The **Azure Bootstrap Setup** workflow (`azure-bootstrap.yml`) was the single entry point for all first-time Azure setup. It sequenced Phase 0 prerequisites, Phase 1 OIDC and secrets setup, and Phase 2 infrastructure provisioning in the correct dependency order. **This has been split into two workflows — see above.**

## Workflow Name

**Name:** `Azure Bootstrap Setup` (now split into `Azure Initial Setup` + `Azure Bootstrap & Deploy`)

This workflow is designed for manual execution via GitHub Actions UI.

## Quick Access

**Direct Link:** https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/actions/workflows/azure-bootstrap.yml

## Running for Dev Profile with All Options Enabled

### Recommended Configuration

For a complete first-time setup of the dev environment with all features enabled:

> ⚠️ **Phase 1a and 1b always run in `dev` environment context** (hardcoded) because all environments share the same Azure AD App Registration. The `validate-inputs` job uses a `$isSetupOnly` variable to detect Phase 0/1a/1b-only runs and relaxes the branch-environment check accordingly.

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
- **Description:** Setup GitHub App (required for automated secret management - first-time only)
- **When to use:** First run for zero-maintenance token management

#### oidcAppName
- **Type:** String
- **Default:** `GitHub-Actions-OIDC`
- **Description:** OIDC App Name (requires GitHub App setup)
- **When to use:** Customize OIDC app name if needed; appears after GitHub App setup

#### enableValidation

> **Removed** — The `enableValidation` input has been removed from the workflow. Validation logic is now integrated into the `validate-inputs` job and runs automatically on every workflow execution.

#### bootstrapInfra
- **Type:** Boolean
- **Default:** `true`
- **Description:** Bootstrap infrastructure (App Services, etc.)
- **When to use:** Always enabled unless only updating credentials

#### configureSecrets
- **Type:** Boolean
- **Default:** `false`
- **Description:** Configure GitHub secrets (auto if GitHub App configured)
- **When to use:** After OIDC setup or when secrets are missing

## Workflow Jobs

1. **validate-inputs** - Validates all parameters and displays summary
2. **setup-oidc** - Creates Azure AD app and federated credentials
3. **configure-secrets** - Sets repository and environment secrets
4. **bootstrap-dev** - Provisions dev environment infrastructure
5. **bootstrap-staging** - Provisions staging environment infrastructure
6. **bootstrap-prod** - Provisions production environment infrastructure
7. **cleanup-dev/staging/prod** - ⚠️ Destructive: deletes App Services and Resource Group
8. **summary** - Generates final workflow summary
9. **trigger-deployments** - Optionally triggers API/UI deploy workflows

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
yamllint -d relaxed .github/workflows/azure-bootstrap.yml
```

### Issue: Device Code Timeout
**Solution:** 
- You have 3 minutes to authenticate
- Re-run the workflow if timeout occurs
- Use incognito mode if browser caches interfere

### Issue: GitHub App Setup Unclear
**Solution:** Follow detailed guide:
- Documentation: `docs/guides/configuration/github-app-authentication.md`
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

- **Quick Start Guide:** `docs/guides/deployment/quick-start-azure-bootstrap.md`
- **GitHub App Setup:** `docs/guides/configuration/github-app-authentication.md`
- **Workflow Summary:** `.github/workflows/README.md`
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

**Last Updated:** 2026-03-18  
**Workflow Version:** 1.0  
**Maintainer:** Platform Team
