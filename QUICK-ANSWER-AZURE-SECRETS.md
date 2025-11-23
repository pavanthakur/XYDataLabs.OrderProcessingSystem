# Quick Answer: Required Secrets for Azure App Service Hosting

## The Issue You Reported

The workflow step "Configure GitHub Secrets" was failing with this error:
```
Environment: dev
  ⚠️  Could not fetch secrets (environment may not exist)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ All environment secrets verified successfully
End Time (UTC): 2025-11-23 15:06:07

Error: Process completed with exit code 1.
```

## What Was Fixed

**Root Cause**: The PowerShell script was inheriting a non-zero exit code from the `gh api` command when checking for environment secrets in non-existent environments.

**Solution**: Added explicit `exit 0` to the "Verify Environment Secrets" step to ensure success even when environments don't exist yet (which is expected during initial bootstrap).

## Required Secrets for Azure App Service

To bootstrap and deploy to Azure App Service in dev, staging, or prod environments, you need these **3 repository secrets**:

### 1. AZUREAPPSERVICE_CLIENTID
- **What**: Azure AD App Registration Client ID
- **Format**: GUID (e.g., `12345678-1234-1234-1234-123456789abc`)
- **Purpose**: Identifies your Azure AD application for OIDC authentication

### 2. AZUREAPPSERVICE_TENANTID
- **What**: Azure Tenant ID
- **Format**: GUID (e.g., `87654321-4321-4321-4321-cba987654321`)
- **Purpose**: Identifies your Azure AD tenant

### 3. AZUREAPPSERVICE_SUBSCRIPTIONID
- **What**: Azure Subscription ID
- **Format**: GUID (e.g., `abcdef12-3456-7890-abcd-ef1234567890`)
- **Purpose**: Identifies your Azure subscription where resources will be created

## How to Set These Secrets

### Option 1: Automated (Recommended)

Run the Azure Bootstrap workflow:

1. Go to **Actions** → **Azure Bootstrap Setup** → **Run workflow**
2. Configure:
   - Target environment: `dev` (or `staging`, `prod`, `all`)
   - Setup Azure OIDC: `true`
   - Setup GitHub App: `true` (first time)
   - Configure GitHub secrets: `true`
   - Bootstrap infrastructure: `true`
3. The workflow will:
   - Prompt for Azure device code authentication
   - Create Azure OIDC credentials
   - Automatically set all 3 secrets in GitHub
   - Bootstrap your infrastructure

**Prerequisites**: 
- GitHub App configured (see `Documentation/03-Configuration-Guides/QUICK-SETUP-GITHUB-APP.md`)
- Azure subscription with appropriate permissions

### Option 2: Manual

1. Run the OIDC setup script:
   ```powershell
   ./Resources/Azure-Deployment/setup-github-oidc.ps1 `
     -Branches "dev" `
     -Environments "dev" `
     -GitHubOwner "pavanthakur" `
     -Repository "XYDataLabs.OrderProcessingSystem"
   ```

2. Get the credentials:
   ```powershell
   # Get subscription info
   az account show
   
   # Get app info
   az ad app list --display-name "GitHub-Actions-OIDC"
   ```

3. Add secrets to GitHub:
   - Go to: https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem/settings/secrets/actions
   - Click "New repository secret"
   - Add each of the 3 secrets with values from step 2

## Environment-Specific Secrets (Optional)

You can **optionally** create environment-specific versions of these secrets for dev, staging, and prod environments. This is only needed if you want:
- Separate Azure subscriptions per environment
- Different security boundaries
- Compliance isolation

If you don't set environment secrets, the repository secrets will be used for all environments (which is perfectly fine for most cases).

## What Happens Now

With the fix applied:
1. ✅ The workflow will no longer fail when environments don't exist
2. ✅ Environment secret verification is informational only
3. ✅ Repository secrets are still verified and required
4. ✅ You can proceed with bootstrap for dev, staging, or prod

## Next Steps

1. **If you haven't run Azure Bootstrap yet**:
   - Run the workflow with "Setup Azure OIDC" = true
   - It will create and configure all secrets automatically

2. **If you already have Azure OIDC set up**:
   - The repository secrets should already exist
   - The workflow will now succeed
   - You can proceed with infrastructure bootstrap

3. **To bootstrap a specific environment**:
   - Run Azure Bootstrap workflow
   - Set target environment to `dev`, `staging`, or `prod`
   - Enable "Bootstrap infrastructure"
   - The workflow will create Azure resources for that environment

## For More Details

See the comprehensive guide at:
`Documentation/03-Configuration-Guides/AZURE-APPSERVICE-SECRETS-GUIDE.md`

This includes:
- Detailed explanations of each secret
- Troubleshooting common issues
- Best practices
- Security considerations
