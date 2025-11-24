# Azure Bootstrap Workflow

Automated one-click setup for Azure infrastructure and GitHub Actions OIDC integration.

## 🎯 Purpose

This workflow automates the complete Azure setup process, from OIDC configuration to infrastructure provisioning, eliminating manual setup steps.

## 🚀 Quick Start

### Prerequisites

**No manual prerequisites required!** 🎉

The workflow uses the automatically available `GITHUB_TOKEN` with appropriate permissions to configure repository secrets. You can run the workflow immediately without any manual token setup.

**Optional**: For environment-level secret configuration, you can add a `GH_PAT` (Personal Access Token) repository secret:
- **Why**: Provides additional isolation by configuring secrets at the environment level
- **How**: Create a PAT with `repo` scope and add it as `GH_PAT` in repository secrets
- **Impact if skipped**: Environment secrets won't be configured, but repository secrets will work fine

### First-Time Setup (Complete)

1. **Navigate to Actions**: https://github.com/pavanthakur/TestAppXY_OrderProcessingSystem/actions
2. **Select Workflow**: Click "Azure Bootstrap Setup"
3. **Run Workflow** with these settings:
   - Environment: `all` (or specific environment)
   - ✅ Setup Azure OIDC: `true`
   - ✅ Setup GitHub App: `true` (follow manual setup instructions)
   - OIDC App Name: `GitHub-Actions-OIDC` (default)
   - ✅ Configure GitHub secrets: `true`
   - ✅ Enable pre-deployment validation: `true` (default, recommended)
   - ✅ Bootstrap infrastructure: `true` (default)
4. **Authenticate** when prompted for Azure login (device code flow)
5. **Wait** for completion (~10-15 minutes for all environments)
6. **Note**: Pre-deployment validation will be automatically enabled (may require manual step due to permissions)

### Add New Environment

To bootstrap a new environment after initial setup:

1. Run workflow with:
   - Environment: `dev` (or `staging`/`prod`)
   - ❌ Setup Azure OIDC: `false` (already done)
   - ❌ Setup GitHub App: `false` (already done)
   - ❌ Configure GitHub secrets: `false` (already done)
   - ✅ Enable pre-deployment validation: `true` (recommended)
   - ✅ Bootstrap infrastructure: `true`

## 📋 Workflow Inputs

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `environment` | choice | - | Target environment (`dev`, `staging`, `prod`, `all`) |
| `setupOidc` | boolean | `false` | Create Azure AD app registration with federated credentials (first-time only) |
| `setupGitHubApp` | boolean | `false` | Setup GitHub App (required for automated secret management - first-time only) |
| `oidcAppName` | string | `GitHub-Actions-OIDC` | OIDC App Name (requires GitHub App setup) |
| `configureSecrets` | boolean | `false` | Automatically configure GitHub repository secrets |
| `enableValidation` | boolean | `true` | Enable pre-deployment validation for future infrastructure deployments |
| `bootstrapInfra` | boolean | `true` | Provision Azure resources (Resource Groups, App Services, App Insights) |

## 🔄 Workflow Jobs

### 1. Setup OIDC (`setup-oidc`)
**Runs when**: `setupOidc` input is `true`

**Actions**:
- Authenticates to Azure (device code flow)
- Creates `GitHub-Actions-OIDC` Azure AD app registration
- Configures federated credentials for:
  - **Branches**: dev, staging, main
  - **Environments**: dev, staging, prod
- Outputs Azure credentials for subsequent jobs

**Outputs**:
- `client-id`: Azure AD application (client) ID
- `tenant-id`: Azure tenant ID
- `subscription-id`: Azure subscription ID
- `app-object-id`: Azure AD app object ID

### 2. Configure Secrets (`configure-secrets`)
**Runs when**: `configureSecrets` input is `true`

**Actions**:
- Checks if secrets already exist
- Installs GitHub CLI if needed
- Sets GitHub repository secrets:
  - `AZUREAPPSERVICE_CLIENTID`
  - `AZUREAPPSERVICE_TENANTID`
  - `AZUREAPPSERVICE_SUBSCRIPTIONID`
- Sets GitHub environment secrets (if `GH_PAT` is configured):
  - For each selected environment (dev, staging, prod)
  - Same three secrets scoped to environment level
  - Provides better isolation between environments

**Requirements**:
- **Repository Secrets**: Automatically uses `GITHUB_TOKEN` with `secrets: write` permission (configured in workflow)
- **Environment Secrets**: Requires `GH_PAT` secret (Personal Access Token with `repo` scope)
  - If `GH_PAT` is not configured, environment secrets are skipped with a warning
  - Repository secrets will still be configured successfully
- GitHub CLI (pre-installed on GitHub-hosted runners)

**Setting up GH_PAT** (Optional, for environment-level secrets):
1. Create a Personal Access Token:
   - Go to: https://github.com/settings/tokens
   - Click "Generate new token (classic)"
   - Select scope: `repo` (Full control of private repositories)
   - Generate and copy the token
2. Add as repository secret:
   - Go to: Settings > Secrets and variables > Actions in your repository
   - Or navigate to: `https://github.com/<owner>/<repo>/settings/secrets/actions`
   - Click "New repository secret"
   - Name: `GH_PAT`
   - Value: Paste your token
   - Click "Add secret"

### 3. Bootstrap Environments (`bootstrap-dev`, `bootstrap-staging`, `bootstrap-prod`)
**Runs when**: `bootstrapInfra` input is `true` AND environment matches

**Actions** (per environment):
- Authenticates using OIDC
- Runs `bootstrap-enterprise-infra.ps1`
- Creates:
  - Resource Group: `rg-orderprocessing-{env}`
  - App Service Plan: `asp-orderprocessing-{env}` (SKU: F1/B1/P1v3)
  - API Web App: `pavanthakur-orderprocessing-api-xyapp-{env}`
  - UI Web App: `pavanthakur-orderprocessing-ui-xyapp-{env}`
  - Application Insights: `ai-orderprocessing-{env}`
- Assigns RBAC (Contributor) to OIDC service principal
- Uploads bootstrap logs as artifacts

**Parallelization**:
- Dev, Staging, and Prod jobs run in parallel when `environment=all`

### 4. Pre-Validate Prerequisites (`pre-validate-prerequisites`)
**Runs when**: Bootstrap or validation is enabled

**Actions**:
- Validates OIDC credentials (AZUREAPPSERVICE_CLIENTID, TENANTID, SUBSCRIPTIONID)
- Validates GitHub App credentials (APP_ID, APP_PRIVATE_KEY)
- Provides clear error messages if prerequisites are missing
- **Fails with error if prerequisites are not configured** (blocks bootstrap execution)
- Creates validation summary

**Purpose**: Ensures prerequisites are configured before bootstrap runs - **Required for bootstrap to proceed**

### 5. Enable Validation (`enable-validation`)
**Runs when**: `enableValidation` input is `true` AND bootstrap completed

**Actions**:
- Modifies `.github/workflows/infra-deploy.yml`
- Re-enables `pre-validate` job condition
- Restores `needs: pre-validate` dependency
- Attempts to commit changes to repository
- May require manual intervention due to GitHub token permissions

**Purpose**: Enables pre-deployment validation for future infrastructure deployments

### 6. Summary (`summary`)
**Runs**: Always (after all jobs)

**Actions**:
- Aggregates results from all jobs
- Displays status table in workflow summary
- Shows success/failure for each step including pre-validation and enable-validation

## 🎬 Usage Scenarios

### Scenario 1: Complete First-Time Setup
**Goal**: Set up everything from scratch

**Steps**:
1. Run workflow with all options enabled:
   ```yaml
   environment: all
   setupOidc: true
   setupGitHubApp: true
   configureSecrets: true
   enableValidation: true
   bootstrapInfra: true
   ```
2. Authenticate to Azure when prompted
3. Follow GitHub App setup instructions if needed
4. Wait for completion (~15 minutes)
5. Verify in Azure Portal
6. Check if pre-deployment validation was enabled (may require manual step)

**Result**: OIDC configured, secrets set, all environments provisioned, validation enabled

---

### Scenario 2: Bootstrap Only Dev Environment
**Goal**: Quick dev setup for testing

**Steps**:
1. Run workflow:
   ```yaml
   environment: dev
   setupOidc: true
   setupGitHubApp: true
   configureSecrets: true
   enableValidation: true
   bootstrapInfra: true
   ```
2. Authenticate when prompted
3. Wait for completion (~5 minutes)

**Result**: Dev environment ready, validation enabled

---

### Scenario 3: Add Staging Environment Later
**Goal**: Expand to staging after dev is working

**Steps**:
1. Run workflow:
   ```yaml
   environment: staging
   setupOidc: false  # Already done
   setupGitHubApp: false  # Already done
   configureSecrets: false  # Already done
   enableValidation: true
   bootstrapInfra: true
   ```
2. Wait for completion (~5 minutes)

**Result**: Staging environment added, validation enabled

---

### Scenario 4: Re-run Bootstrap (Fix Issues)
**Goal**: Recreate resources if bootstrap failed

**Steps**:
1. Delete failed resources in Azure Portal (optional)
2. Run workflow:
   ```yaml
   environment: dev
   setupOidc: false
   setupGitHubApp: false
   configureSecrets: false
   enableValidation: false  # Skip if only re-bootstrapping
   bootstrapInfra: true
   ```
3. Wait for completion

**Result**: Resources recreated

## 🔍 Monitoring & Troubleshooting

### View Workflow Progress
1. Go to: https://github.com/pavanthakur/TestAppXY_OrderProcessingSystem/actions
2. Click on "Azure Bootstrap Setup" workflow run
3. Monitor real-time logs for each job

### Check Bootstrap Logs
- Logs are uploaded as artifacts (30-day retention)
- Download from workflow run page: "Artifacts" section
- Files: `bootstrap-log-dev.log`, `bootstrap-log-staging.log`, `bootstrap-log-prod.log`

### Common Issues

#### Issue: "OIDC app already exists"
**Solution**: This is normal. Workflow will reuse existing app. Ensure federated credentials match expected branches/environments.

#### Issue: "GitHub secrets configuration failed"
**Solution**: 
- Workflow automatically uses `GITHUB_TOKEN` - no manual token setup required
- Ensure the workflow has `secrets: write` permission (already configured)
- If still failing, check workflow logs for specific error messages
- Alternatively, manually add secrets: https://github.com/pavanthakur/TestAppXY_OrderProcessingSystem/settings/secrets/actions

#### Issue: "failed to fetch public key: HTTP 403: Resource not accessible by integration"
**Symptom**: Error when trying to configure environment secrets
**Cause**: `GITHUB_TOKEN` doesn't have permission to access environment secrets API
**Solution**:
1. This is expected if `GH_PAT` is not configured
2. Environment secrets will be skipped with a warning message
3. Repository secrets will still be configured successfully
4. To enable environment secrets:
   - Create a Personal Access Token with `repo` scope
   - Add it as `GH_PAT` repository secret
   - Re-run the workflow
5. Environment secrets are optional - repository secrets are sufficient for most use cases

#### Issue: "Resource Group creation timeout"
**Solution**: 
- Check Azure subscription quotas
- Verify region availability (`centralindia`)
- Re-run workflow after verifying Azure status

#### Issue: "RBAC assignment failed"
**Solution**:
- Ensure you have Owner/User Access Administrator role on subscription
- Wait 5 minutes for service principal propagation, then re-run

#### Issue: "Enable validation job failed"
**Solution**:
- Check if `infra-deploy.yml` has expected TODO comments
- Manually edit workflow if structure changed
- Commit changes manually

### Verify Setup Completion

After successful run, verify:

✅ **GitHub Secrets**:
```bash
gh secret list --repo pavanthakur/TestAppXY_OrderProcessingSystem
```

✅ **Azure AD App**:
```bash
az ad app list --display-name "GitHub-Actions-OIDC"
```

✅ **Federated Credentials**:
```bash
az ad app federated-credential list --id <app-object-id>
```

✅ **Azure Resources**:
```bash
az group list --query "[?starts_with(name, 'rg-orderprocessing')].name"
```

✅ **Validation Enabled**:
Check `.github/workflows/infra-deploy.yml` for active `pre-validate` job

## 🔐 Security Considerations

### Authentication Methods

**Initial OIDC Setup** (setup-oidc job):
- Uses **device code flow** (interactive)
- Requires user with Azure AD app creation permissions
- One-time authentication per workflow run

**Infrastructure Bootstrap** (bootstrap jobs):
- Uses **OIDC federated credentials** (passwordless)
- No secrets stored beyond GitHub repository secrets
- Automatic token exchange via GitHub Actions

### Required Permissions

**Azure AD** (for OIDC setup):
- Application Administrator or Global Administrator
- Permission to create app registrations

**Azure Subscription** (for bootstrap):
- Owner or Contributor + User Access Administrator
- Permission to create resource groups and assign RBAC

**GitHub** (for secret configuration):
- **Repository Secrets**: Workflow automatically uses `GITHUB_TOKEN` with `secrets: write` permission
  - No manual token creation or management required
  - The workflow is configured with the necessary permissions
- **Environment Secrets** (optional): Requires `GH_PAT` (Personal Access Token)
  - PAT must have `repo` scope
  - Used to configure environment-level secrets for better isolation
  - If not provided, only repository secrets are configured

### Secret Scope

Secrets can be configured at two levels:

**Repository-Scoped Secrets** (always configured):
- `AZUREAPPSERVICE_CLIENTID`
- `AZUREAPPSERVICE_TENANTID`
- `AZUREAPPSERVICE_SUBSCRIPTIONID`

These secrets are shared across all environments (dev/staging/prod). The workflow uses OIDC federated credentials with environment-specific subjects to ensure each environment accesses only its own Azure resources.

**Environment-Scoped Secrets** (optional, requires GH_PAT):
- Same three secrets, but scoped to specific environments
- Provides additional isolation: `dev`, `staging`, `prod`
- Environment protection rules can be applied
- Recommended for production environments
- If `GH_PAT` is not configured, environment secrets are skipped gracefully

**Why Environment Secrets?**
- Better isolation between environments
- Can apply environment-specific protection rules
- Allows different credentials per environment if needed in the future
- Follows GitHub security best practices

No passwords or certificates stored. OIDC uses token exchange.

## 🎯 Next Steps After Bootstrap

1. **Verify Resources**:
   - Azure Portal: https://portal.azure.com
   - Resource Groups: `rg-orderprocessing-{env}`
   - Web Apps: Check health status

2. **Test Deployment**:
   ```bash
   # Make infrastructure change
   git add infra/parameters/dev.json
   git commit -m "test: trigger deployment"
   git push
   ```

3. **Monitor Workflow**:
   - Pre-validation should run automatically
   - Check validation artifacts
   - Review what-if analysis

4. **Deploy Application**:
   - Run API deployment workflow
   - Run UI deployment workflow
   - Verify endpoints

5. **Configure App Insights**:
   - Follow `Documentation/02-Azure-Learning-Guides/Telemetry-Quick-Start.md`
   - Configure connection strings
   - Verify telemetry flow

## 📚 Related Documentation

- **Setup Scripts**: `Resources/Azure-Deployment/setup-github-oidc.ps1`
- **Bootstrap Script**: `Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1`
- **Validation Workflow**: `.github/workflows/validate-deployment.yml`
- **Infrastructure Deployment**: `.github/workflows/infra-deploy.yml`
- **Azure Deployment Guide**: `Documentation/02-Azure-Learning-Guides/AZURE_DEPLOYMENT_GUIDE.md`

## 🔄 Maintenance

### Update OIDC for New Branches
Re-run workflow with:
```yaml
environment: dev
setupOidc: true
configureSecrets: false
bootstrapInfra: false
```

Or manually run:
```powershell
./Resources/Azure-Deployment/setup-github-oidc.ps1 `
  -Branches "dev,staging,main,feature-xyz" `
  -Environments "dev,staging,prod"
```

### Delete Environment
```bash
# Delete resource group
az group delete --name rg-orderprocessing-dev --yes --no-wait

# Remove RBAC (if needed)
az role assignment delete --assignee <sp-object-id> --scope /subscriptions/<sub-id>/resourceGroups/rg-orderprocessing-dev
```

Then re-run bootstrap workflow to recreate.

## 📊 Workflow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│  User triggers workflow via GitHub UI                       │
│  Selects: environment, OIDC setup, secrets, bootstrap, etc. │
└────────────────────┬────────────────────────────────────────┘
                     │
         ┌───────────┴───────────┐
         │                       │
         ▼                       ▼
┌──────────────────┐    ┌─────────────────────┐
│  Setup OIDC      │───▶│  Configure Secrets  │
│  (if enabled)    │    │  (if enabled)       │
│  - Azure login   │    │  - GitHub CLI       │
│  - Create app    │    │  - Set repo secrets │
│  - Fed creds     │    └──────────┬──────────┘
└──────────────────┘               │
                                   │
         ┌─────────────────────────┼─────────────────────────┐
         │                         │                         │
         ▼                         ▼                         ▼
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│  Bootstrap Dev   │    │  Bootstrap Stg   │    │  Bootstrap Prod  │
│  (if selected)   │    │  (if selected)   │    │  (if selected)   │
│  - OIDC login    │    │  - OIDC login    │    │  - OIDC login    │
│  - Run script    │    │  - Run script    │    │  - Run script    │
│  - Create infra  │    │  - Create infra  │    │  - Create infra  │
└────────┬─────────┘    └────────┬─────────┘    └────────┬─────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                                 ▼
                    ┌─────────────────────────┐
                    │  Enable Validation      │
                    │  (if enabled)           │
                    │  - Modify workflow      │
                    │  - Commit changes       │
                    └─────────────────────────┘
                                 │
                                 ▼
                    ┌─────────────────────────┐
                    │  Summary                │
                    │  - Aggregate results    │
                    │  - Display status       │
                    └─────────────────────────┘
```

## ✅ Success Criteria

After successful workflow completion:

- [ ] GitHub secrets configured (3 secrets visible in settings)
- [ ] Azure AD app "GitHub-Actions-OIDC" exists with federated credentials
- [ ] Resource groups created in Azure (per selected environments)
- [ ] App Service Plans and Web Apps provisioned
- [ ] Application Insights created
- [ ] RBAC assigned (OIDC service principal has Contributor role)
- [ ] Pre-deployment validation enabled in `infra-deploy.yml`
- [ ] Bootstrap logs available as workflow artifacts

---

**Last Updated**: 2025-11-21  
**Workflow Version**: 1.0  
**Maintainer**: DevOps Team
