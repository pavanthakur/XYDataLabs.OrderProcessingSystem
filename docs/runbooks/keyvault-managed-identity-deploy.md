# Key Vault + Managed Identity Deployment Runbook

## Overview

This runbook provides step-by-step instructions for deploying the Order Processing System with Azure Key Vault integration and Managed Identity authentication. The deployment uses OpenID Connect (OIDC) for secure, passwordless authentication from GitHub Actions to Azure.

## Prerequisites

### Azure Requirements
- Azure subscription with appropriate permissions
- Azure CLI installed and authenticated
- Permissions to create:
  - Resource Groups
  - App Service Plans and App Services
  - Key Vaults
  - Role Assignments
  - Azure AD App Registrations (for OIDC)

### GitHub Requirements
- GitHub CLI (`gh`) installed and authenticated
- Repository admin access to configure secrets and environments
- Permissions to manage GitHub Actions workflows

### Local Tools
- PowerShell 7.0 or higher
- Azure CLI (`az`)
- GitHub CLI (`gh`)
- Bicep CLI (included with Azure CLI)

## Architecture

### Components
- **App Service**: Hosts the Order Processing API with System-Assigned Managed Identity
- **Key Vault**: Stores application secrets (API keys, connection strings)
- **Managed Identity**: Authenticates the App Service to Key Vault without credentials
- **GitHub OIDC**: Enables passwordless deployment from GitHub Actions to Azure

### Security Model
1. App Service has a System-Assigned Managed Identity
2. Managed Identity is granted "Key Vault Secrets User" role on the Key Vault
3. App Settings reference Key Vault secrets using `@Microsoft.KeyVault(...)` syntax
4. GitHub Actions authenticates to Azure using OIDC (no stored credentials)

## OIDC Setup

### Step 1: Create Azure AD App Registration for GitHub OIDC

```bash
# Set variables
GITHUB_ORG="pavanthakur"
GITHUB_REPO="XYDataLabs.OrderProcessingSystem"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

# Create App Registration
APP_NAME="github-oidc-orderprocessing"
az ad app create --display-name "$APP_NAME" \
  --query appId -o tsv > app_id.txt

APP_ID=$(cat app_id.txt)

# Create Service Principal
az ad sp create --id $APP_ID

# Get Service Principal Object ID
SP_OBJECT_ID=$(az ad sp show --id $APP_ID --query id -o tsv)

# Assign Contributor role at subscription level
az role assignment create \
  --role "Contributor" \
  --assignee $APP_ID \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

echo "App ID: $APP_ID"
echo "Tenant ID: $TENANT_ID"
echo "Subscription ID: $SUBSCRIPTION_ID"
```

### Step 2: Configure Federated Credentials for GitHub

Create federated credentials for each environment:

```bash
# For dev environment (dev branch)
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-federated-dev",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'$GITHUB_ORG'/'$GITHUB_REPO':environment:dev",
    "description": "GitHub Actions OIDC for dev environment",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# For uat environment (uat branch)
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-federated-uat",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'$GITHUB_ORG'/'$GITHUB_REPO':environment:uat",
    "description": "GitHub Actions OIDC for uat environment",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# For prod environment (main branch)
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-federated-prod",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'$GITHUB_ORG'/'$GITHUB_REPO':environment:prod",
    "description": "GitHub Actions OIDC for prod environment",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

### Step 3: Configure GitHub Secrets

Configure Azure credentials as GitHub secrets (repository-level or environment-level):

```bash
# Navigate to repository
cd /path/to/XYDataLabs.OrderProcessingSystem

# Set repository secrets
gh secret set AZURE_CLIENT_ID --body "$APP_ID"
gh secret set AZURE_TENANT_ID --body "$TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID"

# Or set environment secrets (recommended for isolation)
gh secret set AZURE_CLIENT_ID --env dev --body "$APP_ID"
gh secret set AZURE_TENANT_ID --env dev --body "$TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID --env dev --body "$SUBSCRIPTION_ID"

gh secret set AZURE_CLIENT_ID --env uat --body "$APP_ID"
gh secret set AZURE_TENANT_ID --env uat --body "$TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID --env uat --body "$SUBSCRIPTION_ID"

gh secret set AZURE_CLIENT_ID --env prod --body "$APP_ID"
gh secret set AZURE_TENANT_ID --env prod --body "$TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID --env prod --body "$SUBSCRIPTION_ID"
```

## Deployment Steps

### Step 1: Create Key Vault and Prerequisites

For each environment (dev, uat, prod), create the required Azure resources:

```bash
# Set environment variables
ENV="dev"  # Change to uat or prod as needed
LOCATION="eastus"
RG_NAME="rg-orderprocessing-${ENV}"
KV_NAME="kv-orderprocessing-${ENV}"
ASP_NAME="asp-orderprocessing-${ENV}"

# Create Resource Group
az group create --name $RG_NAME --location $LOCATION

# Create Key Vault
az keyvault create \
  --name $KV_NAME \
  --resource-group $RG_NAME \
  --location $LOCATION \
  --enable-rbac-authorization true \
  --sku standard

# Create App Service Plan (Free tier for dev, Standard for uat/prod)
SKU="F1"  # Use "B1" or "S1" for uat/prod
az appservice plan create \
  --name $ASP_NAME \
  --resource-group $RG_NAME \
  --location $LOCATION \
  --sku $SKU \
  --is-linux false
```

### Step 2: Add Secrets to Key Vault

**⚠️ IMPORTANT: Use placeholder values initially. Real secrets should be added securely after deployment.**

```bash
# Add OpenPay API Key (placeholder - replace with real value)
az keyvault secret set \
  --vault-name $KV_NAME \
  --name "OpenPayAdapter--ApiKey" \
  --value "placeholder-api-key-change-me"

# Add Application Insights Connection String (placeholder - replace with real value)
az keyvault secret set \
  --vault-name $KV_NAME \
  --name "ApplicationInsights--ConnectionString" \
  --value "InstrumentationKey=placeholder-change-me;IngestionEndpoint=https://placeholder.applicationinsights.azure.com/"

echo "✅ Secrets added to Key Vault (using placeholders)"
echo "⚠️  Remember to update secrets with real values after deployment"
```

### Step 3: Grant Current User Access to Key Vault (Optional)

If you need to manage secrets manually:

```bash
# Get current user object ID
USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)

# Assign Key Vault Secrets Officer role
az role assignment create \
  --role "Key Vault Secrets Officer" \
  --assignee $USER_OBJECT_ID \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG_NAME/providers/Microsoft.KeyVault/vaults/$KV_NAME"
```

### Step 4: Deploy via GitHub Actions

The deployment can be triggered automatically by pushing to the appropriate branch, or manually via workflow dispatch:

#### Option A: Automatic Deployment (Push to Branch)
```bash
# Merge your changes to the dev branch
git checkout dev
git merge feature/keyvault-managedidentity-dev
git push origin dev

# GitHub Actions will automatically deploy to dev environment
```

#### Option B: Manual Deployment (Workflow Dispatch)
```bash
# Trigger workflow manually via GitHub CLI
gh workflow run deploy-and-verify.yml \
  --ref dev \
  -f environment=dev

# Or use GitHub UI: Actions → Deploy and Verify → Run workflow
```

### Step 5: Verify Deployment

After deployment completes:

1. **Check GitHub Actions logs**: Verify the workflow completed successfully
2. **Verify Azure resources**:
   ```bash
   # Check App Service
   az webapp show --name "pavanthakur-orderprocessing-api-xyapp-${ENV}" --resource-group $RG_NAME
   
   # Check Managed Identity
   az webapp identity show --name "pavanthakur-orderprocessing-api-xyapp-${ENV}" --resource-group $RG_NAME
   
   # Check App Settings (Key Vault references)
   az webapp config appsettings list \
     --name "pavanthakur-orderprocessing-api-xyapp-${ENV}" \
     --resource-group $RG_NAME \
     --query "[?contains(value, '@Microsoft.KeyVault')]"
   ```

3. **Test health endpoint**:
   ```bash
   APP_URL="https://pavanthakur-orderprocessing-api-xyapp-${ENV}.azurewebsites.net"
   curl -i "${APP_URL}/health"
   ```

### Step 6: Update Real Secrets

After verifying the deployment, update Key Vault secrets with real values:

```bash
# Update OpenPay API Key
az keyvault secret set \
  --vault-name $KV_NAME \
  --name "OpenPayAdapter--ApiKey" \
  --value "ACTUAL_API_KEY_HERE"

# Update Application Insights Connection String
az keyvault secret set \
  --vault-name $KV_NAME \
  --name "ApplicationInsights--ConnectionString" \
  --value "ACTUAL_CONNECTION_STRING_HERE"

# Restart App Service to pick up new secret values
az webapp restart \
  --name "pavanthakur-orderprocessing-api-xyapp-${ENV}" \
  --resource-group $RG_NAME
```

## Rollout Plan: dev → uat → prod

### Phase 1: Development (dev)
1. ✅ Complete OIDC setup
2. ✅ Create dev Key Vault and prerequisites
3. ✅ Add placeholder secrets to dev Key Vault
4. ✅ Deploy to dev via GitHub Actions
5. ✅ Verify deployment and test functionality
6. ✅ Update with real secrets if needed
7. ✅ Perform end-to-end testing

### Phase 2: User Acceptance Testing (uat)
1. ⏳ Create uat Key Vault and prerequisites
2. ⏳ Add secrets to uat Key Vault
3. ⏳ Merge feature branch to uat branch
4. ⏳ Deploy to uat via GitHub Actions
5. ⏳ Verify deployment
6. ⏳ Perform UAT testing
7. ⏳ Get stakeholder approval

### Phase 3: Production (prod)
1. ⏳ Create prod Key Vault and prerequisites
2. ⏳ Add secrets to prod Key Vault
3. ⏳ Create release PR from uat to main
4. ⏳ Get approval from required reviewers
5. ⏳ Merge to main branch
6. ⏳ Deploy to prod via GitHub Actions
7. ⏳ Verify deployment
8. ⏳ Monitor production metrics
9. ⏳ Update runbook with any lessons learned

## Troubleshooting

### Issue: OIDC Authentication Fails
**Symptoms**: GitHub Actions fails with authentication errors

**Solution**:
1. Verify federated credentials are configured correctly
2. Check environment name matches exactly (case-sensitive)
3. Ensure App Registration has Contributor role on subscription
4. Verify GitHub secrets are set correctly

```bash
# List federated credentials
az ad app federated-credential list --id $APP_ID

# Verify role assignments
az role assignment list --assignee $APP_ID --scope "/subscriptions/$SUBSCRIPTION_ID"
```

### Issue: Key Vault Access Denied
**Symptoms**: App Service cannot read secrets from Key Vault

**Solution**:
1. Verify Managed Identity is enabled on App Service
2. Check role assignment on Key Vault

```bash
# Check Managed Identity
az webapp identity show --name $APP_NAME --resource-group $RG_NAME

# List role assignments on Key Vault
az role assignment list --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG_NAME/providers/Microsoft.KeyVault/vaults/$KV_NAME"
```

### Issue: App Settings Not Resolving Key Vault References
**Symptoms**: Application receives `@Microsoft.KeyVault(...)` string instead of secret value

**Solution**:
1. Verify Key Vault reference syntax is correct
2. Check that the secret exists in Key Vault
3. Ensure Managed Identity has access to the secret
4. Restart the App Service

```bash
# Verify secret exists
az keyvault secret show --vault-name $KV_NAME --name "OpenPayAdapter--ApiKey"

# Restart App Service
az webapp restart --name $APP_NAME --resource-group $RG_NAME
```

### Issue: Deployment Fails with "Resource Group Not Found"
**Symptoms**: Bicep deployment fails because resource group doesn't exist

**Solution**: The workflow now creates resource group automatically, but you can pre-create it:

```bash
az group create --name $RG_NAME --location $LOCATION
```

## Best Practices

1. **Secret Rotation**: 
   - Rotate secrets regularly (every 90 days recommended)
   - Use Key Vault versioning for seamless rotation
   - App Service automatically picks up new secret versions

2. **Environment Isolation**:
   - Use separate Key Vaults for dev/uat/prod
   - Never share secrets between environments
   - Use environment-specific GitHub secrets

3. **Monitoring**:
   - Enable Application Insights for all environments
   - Set up alerts for authentication failures
   - Monitor Key Vault access logs

4. **Access Control**:
   - Use RBAC (not access policies) for Key Vault
   - Grant least privilege access
   - Regularly audit role assignments

5. **Disaster Recovery**:
   - Enable soft-delete on Key Vault
   - Document secret values in secure location (password manager)
   - Test recovery procedures regularly

## References

- [Azure Key Vault Managed Identity Integration](https://learn.microsoft.com/en-us/azure/app-service/app-service-key-vault-references)
- [GitHub OIDC with Azure](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-azure)
- [Azure RBAC for Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide)
- [App Service Managed Identity](https://learn.microsoft.com/en-us/azure/app-service/overview-managed-identity)

## Support

For issues or questions:
1. Check this runbook and troubleshooting section
2. Review GitHub Actions logs
3. Check Azure Portal for resource status
4. Consult team documentation or contact DevOps team

---

**Last Updated**: 2025-12-06  
**Version**: 1.0  
**Maintained By**: DevOps Team
