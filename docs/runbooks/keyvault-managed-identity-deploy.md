# Key Vault and Managed Identity Deployment Runbook

## Overview

This runbook provides step-by-step instructions for deploying the Order Processing System API with secure configuration management using Azure Key Vault and Managed Identity. This approach prevents missing runtime secrets and ensures consistent deployments across dev → uat → prod environments.

## Architecture

The deployment uses the following security model:

1. **System-Assigned Managed Identity**: Each App Service has its own managed identity that authenticates to Azure Key Vault
2. **Key Vault References**: Sensitive app settings reference Key Vault secrets using the `@Microsoft.KeyVault(...)` syntax
3. **Non-Secret Settings**: Non-sensitive configuration stored as regular app settings
4. **Environment-Specific Parameters**: Each environment (dev/uat/prod) has its own parameter file for infrastructure deployment

## Prerequisites

### Azure Resources Required

- Azure subscription with appropriate permissions
- Azure CLI installed and configured
- GitHub CLI (gh) installed (for script automation)
- PowerShell 7+ installed

### Required Permissions

1. **Azure Subscription**:
   - `Contributor` role on the subscription or resource group
   - `Key Vault Administrator` or `Key Vault Secrets Officer` role for Key Vault operations
   - `User Access Administrator` role (to grant Managed Identity access to Key Vault)

2. **GitHub Repository**:
   - Repository admin access (to configure secrets and environments)
   - Ability to push to dev, uat, and main branches

## Rollout Plan: Dev → UAT → Prod

### Phase 1: Development Environment

#### 1.1 Create Key Vault (One-Time Setup)

```bash
# Set variables
ENVIRONMENT="dev"
LOCATION="centralindia"
RG_NAME="rg-orderprocessing-$ENVIRONMENT"
KV_NAME="kv-orderproc-$ENVIRONMENT"

# Create resource group if it doesn't exist
az group create --name $RG_NAME --location $LOCATION

# Create Key Vault
az keyvault create \
  --name $KV_NAME \
  --resource-group $RG_NAME \
  --location $LOCATION \
  --enable-rbac-authorization false \
  --sku standard

# Get Key Vault ID for validation
az keyvault show --name $KV_NAME --resource-group $RG_NAME --query id -o tsv
```

#### 1.2 Populate Key Vault Secrets

```bash
# Set Key Vault name
KV_NAME="kv-orderproc-dev"

# Add OpenPay Adapter API Key (replace with actual value)
az keyvault secret set \
  --vault-name $KV_NAME \
  --name "OpenPayAdapter--ApiKey" \
  --value "your-openpay-api-key-here"

# Add Application Insights Connection String (replace with actual value)
# Get from your Application Insights resource
APP_INSIGHTS_CONN_STRING=$(az monitor app-insights component show \
  --app <your-app-insights-name> \
  --resource-group $RG_NAME \
  --query connectionString -o tsv)

az keyvault secret set \
  --vault-name $KV_NAME \
  --name "ApplicationInsights--ConnectionString" \
  --value "$APP_INSIGHTS_CONN_STRING"

# Verify secrets are created
az keyvault secret list --vault-name $KV_NAME --query "[].name" -o table
```

**Note**: The secret names use `--` (double hyphens) because Azure Key Vault doesn't support `:` in secret names, but the Bicep template maps them correctly to the app setting format (e.g., `OpenPayAdapter:ApiKey`).

#### 1.3 Configure GitHub Environment Secrets

Run the wrapper script to configure GitHub secrets and app environment:

```powershell
# Navigate to repository root
cd /path/to/XYDataLabs.OrderProcessingSystem

# Run the configuration script
./scripts/configure-secrets-and-run.ps1 `
  -Environment dev `
  -Repository pavanthakur/XYDataLabs.OrderProcessingSystem `
  -Force
```

Or manually configure using the Azure Deployment scripts:

```powershell
# Configure GitHub repository secrets
./Resources/Azure-Deployment/configure-github-secrets.ps1 `
  -Repository pavanthakur/XYDataLabs.OrderProcessingSystem `
  -Force

# Configure App Service environment settings
./Resources/Azure-Deployment/configure-app-environment.ps1 `
  -Environment dev `
  -BaseName orderprocessing `
  -GitHubOwner pavanthakur
```

#### 1.4 Deploy Infrastructure and Application

```bash
# Option A: Use GitHub Actions (recommended)
# Push changes to dev branch, workflow will trigger automatically
git checkout dev
git add .
git commit -m "Deploy secure configuration to dev"
git push origin dev

# Option B: Manual deployment using Azure CLI
az deployment group create \
  --name deploy-kv-dev-$(date +%s) \
  --resource-group rg-orderprocessing-dev \
  --template-file bicep/appservice-with-kv.bicep \
  --parameters @bicep/parameters/dev.parameters.json
```

#### 1.5 Grant Managed Identity Access to Key Vault

This is handled automatically by the Bicep template, but you can verify:

```bash
# Get App Service principal ID
APP_NAME="pavanthakur-orderprocessing-api-xyapp-dev"
RG_NAME="rg-orderprocessing-dev"

PRINCIPAL_ID=$(az webapp identity show \
  --name $APP_NAME \
  --resource-group $RG_NAME \
  --query principalId -o tsv)

echo "App Service Principal ID: $PRINCIPAL_ID"

# Verify Key Vault access policies
az keyvault show \
  --name kv-orderproc-dev \
  --resource-group $RG_NAME \
  --query properties.accessPolicies
```

### Phase 2: UAT Environment

Once dev is validated, repeat the process for UAT:

#### 2.1 Create UAT Key Vault

```bash
ENVIRONMENT="uat"
KV_NAME="kv-orderproc-uat"
RG_NAME="rg-orderprocessing-uat"

az group create --name $RG_NAME --location centralindia

az keyvault create \
  --name $KV_NAME \
  --resource-group $RG_NAME \
  --location centralindia \
  --enable-rbac-authorization false
```

#### 2.2 Create UAT Parameter File

Create `bicep/parameters/uat.parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "appName": {
      "value": "pavanthakur-orderprocessing-api-xyapp-uat"
    },
    "keyVaultName": {
      "value": "kv-orderproc-uat"
    },
    "appServicePlanName": {
      "value": "asp-orderprocessing-uat"
    },
    "location": {
      "value": "centralindia"
    },
    "appServiceSku": {
      "value": "B1"
    },
    "environment": {
      "value": "uat"
    },
    "openPayAdapterBaseUrl": {
      "value": "https://api.openpay.uat.example.com"
    }
  }
}
```

#### 2.3 Populate UAT Secrets and Deploy

```bash
# Add secrets to UAT Key Vault
az keyvault secret set --vault-name kv-orderproc-uat \
  --name "OpenPayAdapter--ApiKey" --value "uat-api-key"

az keyvault secret set --vault-name kv-orderproc-uat \
  --name "ApplicationInsights--ConnectionString" --value "uat-app-insights-connection-string"

# Run configuration script
./scripts/configure-secrets-and-run.ps1 -Environment uat

# Merge dev to uat branch to trigger deployment
git checkout uat
git merge dev
git push origin uat
```

### Phase 3: Production Environment

After UAT validation, deploy to production:

#### 3.1 Create Production Key Vault

```bash
ENVIRONMENT="prod"
KV_NAME="kv-orderproc-prod"
RG_NAME="rg-orderprocessing-prod"

az group create --name $RG_NAME --location centralindia

az keyvault create \
  --name $KV_NAME \
  --resource-group $RG_NAME \
  --location centralindia \
  --enable-rbac-authorization false
```

#### 3.2 Create Production Parameter File

Create `bicep/parameters/prod.parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "appName": {
      "value": "pavanthakur-orderprocessing-api-xyapp-prod"
    },
    "keyVaultName": {
      "value": "kv-orderproc-prod"
    },
    "appServicePlanName": {
      "value": "asp-orderprocessing-prod"
    },
    "location": {
      "value": "centralindia"
    },
    "appServiceSku": {
      "value": "P1v3"
    },
    "environment": {
      "value": "prod"
    },
    "openPayAdapterBaseUrl": {
      "value": "https://api.openpay.com"
    }
  }
}
```

#### 3.3 Populate Production Secrets and Deploy

```bash
# Add secrets to Production Key Vault
az keyvault secret set --vault-name kv-orderproc-prod \
  --name "OpenPayAdapter--ApiKey" --value "production-api-key"

az keyvault secret set --vault-name kv-orderproc-prod \
  --name "ApplicationInsights--ConnectionString" --value "production-app-insights-connection-string"

# Run configuration script
./scripts/configure-secrets-and-run.ps1 -Environment prod

# Merge uat to main branch to trigger production deployment
git checkout main
git merge uat
git push origin main
```

## Validation

### Validate App Settings

```bash
# Set environment variables
ENV="dev"  # or uat, prod
APP_NAME="pavanthakur-orderprocessing-api-xyapp-$ENV"
RG_NAME="rg-orderprocessing-$ENV"

# List all app settings
az webapp config appsettings list \
  --name $APP_NAME \
  --resource-group $RG_NAME \
  --query "[].{Name:name, Value:value}" \
  --output table

# Check specific settings
az webapp config appsettings list \
  --name $APP_NAME \
  --resource-group $RG_NAME \
  --query "[?name=='ASPNETCORE_ENVIRONMENT' || name=='OpenPayAdapter__ApiKey']" \
  --output table
```

### Validate Key Vault References

Key Vault references should appear as `@Microsoft.KeyVault(SecretUri=...)` in the app settings output.

### Validate Health Endpoint

```bash
# Test health endpoint
ENV="dev"
APP_NAME="pavanthakur-orderprocessing-api-xyapp-$ENV"

curl -s "https://$APP_NAME.azurewebsites.net/api/info/environment" | jq

# Expected output:
# {
#   "Environment": "DEV",
#   "OriginalEnvironment": "Development",
#   "IsDocker": false,
#   "DeploymentType": "Local Process",
#   ...
# }
```

### Validate Managed Identity Access

```bash
# Check App Service can resolve Key Vault secrets
az webapp log tail \
  --name $APP_NAME \
  --resource-group $RG_NAME

# Look for errors related to Key Vault access
# Expected: No errors about missing secrets or authentication failures
```

## Troubleshooting

### Issue: App Settings Not Resolving Key Vault References

**Symptoms**: App settings show `@Microsoft.KeyVault(...)` but secrets aren't resolved

**Resolution**:
1. Verify Managed Identity is enabled:
   ```bash
   az webapp identity show --name $APP_NAME --resource-group $RG_NAME
   ```

2. Verify Key Vault access policy:
   ```bash
   az keyvault show --name $KV_NAME --query properties.accessPolicies
   ```

3. Grant access if missing:
   ```bash
   PRINCIPAL_ID=$(az webapp identity show --name $APP_NAME --resource-group $RG_NAME --query principalId -o tsv)
   
   az keyvault set-policy \
     --name $KV_NAME \
     --object-id $PRINCIPAL_ID \
     --secret-permissions get list
   ```

4. Restart the App Service:
   ```bash
   az webapp restart --name $APP_NAME --resource-group $RG_NAME
   ```

### Issue: Health Check Failing

**Symptoms**: `/api/info/environment` returns 500 or times out

**Resolution**:
1. Check application logs:
   ```bash
   az webapp log tail --name $APP_NAME --resource-group $RG_NAME
   ```

2. Verify database connection (if applicable)
3. Check Application Insights for errors
4. Verify all required app settings are present

### Issue: Key Vault Secrets Not Found

**Symptoms**: Error messages about missing secrets in Key Vault

**Resolution**:
1. List secrets in Key Vault:
   ```bash
   az keyvault secret list --vault-name $KV_NAME --query "[].name" -o table
   ```

2. Verify secret names match exactly (use `--` instead of `:`)
3. Create missing secrets:
   ```bash
   az keyvault secret set --vault-name $KV_NAME --name "SecretName" --value "SecretValue"
   ```

## Rollback Procedures

### Rollback Deployment

If a deployment fails or introduces issues:

1. **Identify last known good deployment**:
   ```bash
   az deployment group list \
     --resource-group $RG_NAME \
     --query "[?properties.provisioningState=='Succeeded'].{Name:name, Timestamp:properties.timestamp}" \
     --output table
   ```

2. **Redeploy previous version**:
   ```bash
   # Revert to previous commit
   git checkout dev
   git reset --hard <previous-commit-hash>
   git push --force origin dev
   
   # Or manually redeploy previous Bicep template
   az deployment group create \
     --name rollback-$(date +%s) \
     --resource-group $RG_NAME \
     --template-file bicep/appservice-with-kv.bicep \
     --parameters @bicep/parameters/dev.parameters.json
   ```

3. **Rollback application code**:
   ```bash
   # Use Azure App Service deployment slots (if configured)
   az webapp deployment slot swap \
     --name $APP_NAME \
     --resource-group $RG_NAME \
     --slot staging \
     --target-slot production
   
   # Or redeploy previous application version via GitHub Actions
   ```

### Emergency: Disable Key Vault References

If Key Vault is unavailable, temporarily use direct values:

```bash
# Replace Key Vault reference with direct value
az webapp config appsettings set \
  --name $APP_NAME \
  --resource-group $RG_NAME \
  --settings OpenPayAdapter__ApiKey="temporary-direct-value"

# Warning: This should only be temporary - rotate secrets after
```

## Maintenance

### Rotating Secrets

To rotate a secret:

1. Create new secret version in Key Vault:
   ```bash
   az keyvault secret set \
     --vault-name $KV_NAME \
     --name "OpenPayAdapter--ApiKey" \
     --value "new-secret-value"
   ```

2. Restart App Service to pick up new version:
   ```bash
   az webapp restart --name $APP_NAME --resource-group $RG_NAME
   ```

3. Verify the new secret is working
4. Delete old secret versions if needed

### Monitoring

1. **Application Insights**: Monitor telemetry and errors
2. **Key Vault Diagnostics**: Enable diagnostic logs to track secret access
3. **App Service Logs**: Review application logs for configuration issues

## Best Practices

1. **Never commit secrets**: Use Key Vault for all sensitive values
2. **Use separate Key Vaults**: One per environment for isolation
3. **Enable soft delete**: Protect against accidental secret deletion
4. **Audit access**: Enable Key Vault audit logging
5. **Least privilege**: Grant only required permissions to Managed Identity
6. **Test in dev first**: Always validate changes in dev before promoting
7. **Document secrets**: Maintain an inventory of which secrets exist in each environment
8. **Automate**: Use scripts and workflows for consistency
9. **Idempotency**: Ensure scripts can be run multiple times safely
10. **Monitor**: Set up alerts for Key Vault access failures

## References

- [Azure Key Vault Documentation](https://docs.microsoft.com/azure/key-vault/)
- [Managed Identities Documentation](https://docs.microsoft.com/azure/active-directory/managed-identities-azure-resources/)
- [Key Vault References in App Service](https://docs.microsoft.com/azure/app-service/app-service-key-vault-references)
- [Bicep Documentation](https://docs.microsoft.com/azure/azure-resource-manager/bicep/)

## Support

For issues or questions:
1. Check application logs in Azure Portal
2. Review GitHub Actions workflow logs
3. Consult this runbook's troubleshooting section
4. Contact the DevOps team
