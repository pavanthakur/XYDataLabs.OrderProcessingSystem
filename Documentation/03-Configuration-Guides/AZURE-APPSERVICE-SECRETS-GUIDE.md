# Azure App Service Deployment - Required Secrets Guide

## Overview

This guide explains the secrets required for deploying to Azure App Service across different environments (dev, staging, prod). These secrets enable OIDC (OpenID Connect) authentication, which is the recommended and most secure way to authenticate GitHub Actions with Azure.

## Table of Contents

- [Quick Reference](#quick-reference)
- [Repository-Level Secrets (Required)](#repository-level-secrets-required)
- [Environment-Specific Secrets (Optional)](#environment-specific-secrets-optional)
- [How to Set Up Secrets](#how-to-set-up-secrets)
- [Automated Setup via Bootstrap Workflow](#automated-setup-via-bootstrap-workflow)
- [Manual Setup](#manual-setup)
- [Troubleshooting](#troubleshooting)

## Quick Reference

### Minimum Required Secrets (Repository Level)

These three secrets are **required** for Azure App Service deployment:

| Secret Name | Description | Example/Format |
|-------------|-------------|----------------|
| `AZUREAPPSERVICE_CLIENTID` | Azure AD App Registration Client ID | `12345678-1234-1234-1234-123456789abc` |
| `AZUREAPPSERVICE_TENANTID` | Azure Tenant ID | `87654321-4321-4321-4321-cba987654321` |
| `AZUREAPPSERVICE_SUBSCRIPTIONID` | Azure Subscription ID | `abcdef12-3456-7890-abcd-ef1234567890` |

### Where These Secrets Come From

These credentials are created during the Azure OIDC setup process:

1. **Azure AD App Registration**: Creates the Client ID
2. **Azure Tenant**: Provides the Tenant ID
3. **Azure Subscription**: Provides the Subscription ID

## Repository-Level Secrets (Required)

Repository-level secrets are **shared across all environments** (dev, staging, prod). They are the minimum requirement for deployment.

### Setting Repository Secrets

1. Go to your repository on GitHub
2. Navigate to: **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add each of the three required secrets

### AZUREAPPSERVICE_CLIENTID

- **Purpose**: Identifies the Azure AD application used for authentication
- **Created by**: Azure OIDC setup (App Registration)
- **Format**: GUID (UUID)
- **Example**: `12345678-1234-1234-1234-123456789abc`

### AZUREAPPSERVICE_TENANTID

- **Purpose**: Identifies your Azure AD tenant
- **Created by**: Azure OIDC setup (from your Azure subscription)
- **Format**: GUID (UUID)
- **Example**: `87654321-4321-4321-4321-cba987654321`

### AZUREAPPSERVICE_SUBSCRIPTIONID

- **Purpose**: Identifies your Azure subscription
- **Created by**: Azure OIDC setup (from your Azure subscription)
- **Format**: GUID (UUID)
- **Example**: `abcdef12-3456-7890-abcd-ef1234567890`

## Environment-Specific Secrets (Optional)

Environment-specific secrets allow you to use **different Azure credentials** for dev, staging, and prod environments. This is useful when:

- You want to isolate environments into separate Azure subscriptions
- You need different Azure AD applications per environment
- You have different security requirements per environment

### When to Use Environment Secrets

✅ **Use environment-specific secrets if:**
- You have separate Azure subscriptions for dev, staging, and prod
- You need stronger isolation between environments
- You have compliance requirements for credential separation

❌ **Skip environment secrets if:**
- You use the same Azure subscription for all environments
- You want simpler management (one set of credentials)
- Your resource isolation is achieved through resource groups

### Setting Environment Secrets

1. Go to your repository on GitHub
2. Navigate to: **Settings** → **Environments**
3. Select the environment (dev, staging, or prod)
4. Add environment secrets with the same names:
   - `AZUREAPPSERVICE_CLIENTID`
   - `AZUREAPPSERVICE_TENANTID`
   - `AZUREAPPSERVICE_SUBSCRIPTIONID`

**Note**: Environment secrets override repository secrets when present.

## How to Set Up Secrets

You have two options for setting up these secrets:

### Option 1: Automated Setup (Recommended)

Use the Azure Bootstrap workflow to automatically create and configure all secrets:

1. Go to **Actions** → **Azure Bootstrap Setup** → **Run workflow**
2. Configure the workflow:
   - **Target environment**: Select `dev`, `staging`, `prod`, or `all`
   - **Setup Azure OIDC**: ✅ `true` (first-time setup)
   - **Setup GitHub App**: ✅ `true` (for automated secret management)
   - **Configure GitHub secrets**: ✅ `true` (to set the secrets)
   - **Bootstrap infrastructure**: Choose based on your needs
3. Follow the prompts for:
   - Azure device code authentication
   - GitHub App creation (one-time, 4 minutes)
4. The workflow will automatically:
   - Create Azure OIDC credentials
   - Set up GitHub secrets
   - Verify the configuration

### Option 2: Manual Setup

If you prefer manual setup or need to update secrets:

#### Step 1: Set Up Azure OIDC

Run the OIDC setup script:

```powershell
./Resources/Azure-Deployment/setup-github-oidc.ps1 `
  -Branches "dev,staging,main" `
  -Environments "dev,staging,prod" `
  -GitHubOwner "YOUR_GITHUB_USERNAME" `
  -Repository "YOUR_REPO_NAME" `
  -AppDisplayName "GitHub-Actions-OIDC"
```

This creates the Azure AD application and federated credentials.

#### Step 2: Get Your Azure Credentials

```powershell
# Get subscription details
az account show

# Get app details
az ad app list --display-name "GitHub-Actions-OIDC"
```

Extract:
- **Client ID**: `appId` from the app list output
- **Tenant ID**: `tenantId` from account show output
- **Subscription ID**: `id` from account show output

#### Step 3: Add Secrets to GitHub

1. Go to: `https://github.com/YOUR_USERNAME/YOUR_REPO/settings/secrets/actions`
2. Click **New repository secret**
3. Add each secret:
   - Name: `AZUREAPPSERVICE_CLIENTID`
   - Value: Your Client ID
   - (Repeat for TENANTID and SUBSCRIPTIONID)

## Automated Setup via Bootstrap Workflow

The Azure Bootstrap workflow (`azure-bootstrap.yml`) provides a fully automated way to set up all required secrets.

### Prerequisites

Before running the bootstrap workflow, you need:

1. **GitHub App** (for automated secret management):
   - `APP_ID` secret
   - `APP_PRIVATE_KEY` secret
   - See: [QUICK-SETUP-GITHUB-APP.md](./QUICK-SETUP-GITHUB-APP.md)

2. **Azure Subscription** with permissions to:
   - Create App Registrations
   - Manage federated credentials
   - Create resource groups

### Workflow Steps

The bootstrap workflow performs these steps:

1. **Setup Azure OIDC**:
   - Creates Azure AD App Registration
   - Configures federated credentials for GitHub
   - Outputs Client ID, Tenant ID, and Subscription ID

2. **Configure GitHub Secrets**:
   - Uses GitHub App authentication
   - Sets repository secrets automatically
   - Sets environment secrets (if environments exist)
   - Verifies all secrets are configured correctly

3. **Bootstrap Infrastructure**:
   - Creates Azure resource groups
   - Deploys App Service plans and resources
   - Configures RBAC permissions

### Running the Bootstrap Workflow

```yaml
# In GitHub Actions UI
Target environment: dev
Setup Azure OIDC: true
Setup GitHub App: false (if already configured)
Configure GitHub secrets: true
Bootstrap infrastructure: true
Enable validation: true
```

### What Gets Created

After running the bootstrap workflow:

✅ **Azure Resources**:
- App Registration: `GitHub-Actions-OIDC`
- Federated Credentials: 6 (3 branches + 3 environments)
- Service Principal with Contributor role

✅ **GitHub Secrets** (Repository):
- `AZUREAPPSERVICE_CLIENTID`
- `AZUREAPPSERVICE_TENANTID`
- `AZUREAPPSERVICE_SUBSCRIPTIONID`

✅ **GitHub Secrets** (Environment - Optional):
- Same three secrets in dev, staging, prod environments

## Troubleshooting

### Secret Not Found Error

**Error**: `AZUREAPPSERVICE_CLIENTID not found`

**Solution**:
1. Verify the secret exists: Go to Settings → Secrets and variables → Actions
2. Check the secret name matches exactly (case-sensitive)
3. Re-add the secret if missing

### Authentication Failed

**Error**: `Failed to login to Azure`

**Solution**:
1. Verify all three secrets are present and correct
2. Check that the Azure AD app still exists
3. Verify federated credentials are configured for your repository
4. Ensure the app has Contributor role on the subscription

### Environment Secret Not Working

**Error**: `Could not fetch secrets (environment may not exist)`

**Solution**:
1. This is a warning, not an error - environments are optional
2. Create the environment: Settings → Environments → New environment
3. Add environment secrets if needed
4. Or use repository secrets (which work for all environments)

### Wrong Credentials

**Error**: `Subscription not found` or `Tenant mismatch`

**Solution**:
1. Run `az account show` to get correct IDs
2. Run `az ad app list --display-name "GitHub-Actions-OIDC"` to get Client ID
3. Update all three secrets with correct values
4. Ensure you're using the same Azure account that created the OIDC setup

### Secret Verification Failed

**Error**: `One or more required repository secrets are missing`

**Solution**:
1. The verification step checks that secrets exist in GitHub
2. Add missing secrets via Settings → Secrets and variables → Actions
3. Re-run the workflow after adding secrets
4. If using environment-specific secrets, ensure environment exists first

## Best Practices

### Security

✅ **DO**:
- Use OIDC (these secrets) instead of service principal credentials
- Rotate secrets if you suspect they're compromised
- Use environment secrets for production with stricter controls
- Limit Azure AD app permissions to minimum required
- Review federated credentials periodically

❌ **DON'T**:
- Share secrets in code, logs, or documentation
- Use the same secrets for multiple repositories
- Grant unnecessary Azure permissions
- Store secrets in plain text files

### Management

✅ **DO**:
- Document when secrets were created/updated
- Use descriptive Azure AD app names
- Keep secrets in sync across environments if using shared credentials
- Test secret rotation in dev before prod

❌ **DON'T**:
- Mix OIDC and service principal authentication
- Delete Azure AD apps that are in use
- Forget to update secrets after Azure changes

## Additional Resources

- [Azure OIDC Setup Guide](../../Resources/Azure-Deployment/setup-github-oidc.ps1)
- [GitHub App Setup](./QUICK-SETUP-GITHUB-APP.md)
- [Azure Bootstrap Workflow](../../.github/workflows/azure-bootstrap.yml)
- [GitHub OIDC Documentation](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-azure)
- [Azure App Service Deployment](https://learn.microsoft.com/en-us/azure/app-service/deploy-github-actions)

## Support

If you encounter issues not covered in this guide:

1. Check workflow logs in GitHub Actions
2. Review Azure portal for App Registration status
3. Verify federated credentials in Azure AD
4. Consult the troubleshooting guides:
   - [TROUBLESHOOTING-INDEX.md](../../TROUBLESHOOTING-INDEX.md)
   - [WORKFLOW-FAILURE-RESOLUTION.md](../../WORKFLOW-FAILURE-RESOLUTION.md)
