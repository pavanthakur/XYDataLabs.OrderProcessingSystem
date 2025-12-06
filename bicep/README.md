# App Service with Key Vault Integration

This directory contains Bicep templates for deploying an Azure App Service with secure Key Vault integration using Managed Identity.

## Files

- **appservice-with-kv.bicep** - Main Bicep template for deploying/updating App Service with Key Vault integration
- **parameters/** - Environment-specific parameter files
  - **dev.parameters.json** - Development environment
  - **uat.parameters.json** - UAT/Staging environment
  - **prod.parameters.json** - Production environment

## Features

- **System-assigned Managed Identity**: Automatically creates and assigns a managed identity to the App Service
- **Key Vault Integration**: References secrets from Azure Key Vault using Key Vault references
- **RBAC-based Access**: Grants the App Service's managed identity the "Key Vault Secrets User" role
- **Environment-aware Configuration**: Separate parameter files for each environment (dev, uat, prod)
- **Idempotent Deployments**: Can be run multiple times safely without side effects

## Prerequisites

Before deploying, ensure:

1. Azure CLI is installed and you're logged in
2. The target Resource Group exists
3. An App Service Plan exists (referenced in parameter files)
4. An Azure Key Vault exists (referenced in parameter files)
5. The following secrets are created in the Key Vault:
   - `OpenPayAdapter--ApiKey` - API key for OpenPay adapter
   - `APPLICATIONINSIGHTS-CONNECTION-STRING` - Application Insights connection string

## Deployment

### Using Azure CLI

Deploy to a specific environment:

```bash
# Deploy to Development
az deployment group create \
  --resource-group rg-orderprocessing-dev \
  --template-file appservice-with-kv.bicep \
  --parameters parameters/dev.parameters.json

# Deploy to UAT
az deployment group create \
  --resource-group rg-orderprocessing-uat \
  --template-file appservice-with-kv.bicep \
  --parameters parameters/uat.parameters.json

# Deploy to Production
az deployment group create \
  --resource-group rg-orderprocessing-prod \
  --template-file appservice-with-kv.bicep \
  --parameters parameters/prod.parameters.json
```

### Using GitHub Actions with OIDC

For GitHub Actions workflows, use Azure login with OIDC:

```yaml
- name: Azure Login with OIDC
  uses: azure/login@v1
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

- name: Deploy Bicep Template
  uses: azure/arm-deploy@v1
  with:
    resourceGroupName: rg-orderprocessing-dev
    template: ./bicep/appservice-with-kv.bicep
    parameters: ./bicep/parameters/dev.parameters.json
```

## Configuration

### App Settings (Non-Secrets)

These are set directly as environment variables:

- `OpenPayAdapter__BaseUrl` - Base URL for the OpenPay API
- `ASPNETCORE_ENVIRONMENT` - ASP.NET Core environment (Development, Staging, Production)

### Secrets (Key Vault References)

These are referenced from Key Vault using special syntax:

- `OpenPayAdapter__ApiKey` - Retrieved from Key Vault secret `OpenPayAdapter--ApiKey`
- `APPLICATIONINSIGHTS_CONNECTION_STRING` - Retrieved from Key Vault secret `APPLICATIONINSIGHTS-CONNECTION-STRING`

**Note**: Key Vault references use the format: `@Microsoft.KeyVault(VaultName={vault-name};SecretName={secret-name})`

## Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `appName` | Name of the App Service | `pavanthakur-orderprocessing-api-xyapp-dev` |
| `location` | Azure region | `centralindia` |
| `appServicePlanName` | Name of existing App Service Plan | `asp-orderprocessing-dev` |
| `keyVaultName` | Name of existing Key Vault | `kv-orderprocessing-dev` |
| `openPayBaseUrl` | OpenPay API base URL | `https://sandbox-api.openpay.mx/v1` |
| `aspnetcoreEnvironment` | ASP.NET Core environment | `Development` |

## Outputs

The template provides the following outputs:

- `principalId` - The managed identity principal ID of the App Service
- `webAppName` - The name of the deployed App Service
- `webAppHostName` - The default hostname of the App Service

## Security Considerations

1. **Managed Identity**: Uses system-assigned managed identity to eliminate the need for storing credentials
2. **RBAC**: Uses role-based access control (Key Vault Secrets User) instead of access policies
3. **HTTPS Only**: Enforces HTTPS for all connections
4. **Secret Management**: All sensitive values are stored in Key Vault, not in app settings

## Troubleshooting

### Role Assignment Issues

If you see permission errors accessing Key Vault:
1. Verify the managed identity has been created
2. Check the role assignment exists: `az role assignment list --scope /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.KeyVault/vaults/{vault-name}`
3. Wait a few minutes for role assignments to propagate

### Key Vault Reference Issues

If secrets are not loading:
1. Verify the secret exists in Key Vault with the correct name
2. Check the Key Vault reference syntax is correct
3. Ensure the managed identity has the "Key Vault Secrets User" role
4. Restart the App Service after the role assignment

## Related Documentation

- [Azure Key Vault References](https://docs.microsoft.com/azure/app-service/app-service-key-vault-references)
- [Managed Identities](https://docs.microsoft.com/azure/active-directory/managed-identities-azure-resources/overview)
- [Bicep Documentation](https://docs.microsoft.com/azure/azure-resource-manager/bicep/)
