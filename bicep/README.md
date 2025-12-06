# Bicep Infrastructure Templates

## Overview

This directory contains Azure Bicep templates for deploying the Order Processing System API with secure configuration management using Azure Key Vault and Managed Identity.

## Files

### Templates

- **appservice-with-kv.bicep**: Main Bicep template that deploys:
  - Azure Key Vault with soft delete enabled
  - App Service Plan
  - App Service with System-Assigned Managed Identity
  - Key Vault access policy for the Managed Identity
  - App settings with Key Vault references for secrets

### Parameters

- **parameters/dev.parameters.json**: Development environment parameters
- **parameters/uat.parameters.json**: UAT environment parameters (to be created)
- **parameters/prod.parameters.json**: Production environment parameters (to be created)

## Usage

### Prerequisites

1. Azure subscription with the following permissions:
   - **Contributor** role on the resource group (to create resources)
   - **User Access Administrator** role (to assign access policies) or sufficient permissions to manage Key Vault access
2. After deployment, populate the Key Vault with these secrets:
   - `OpenPayAdapter--ApiKey`
   - `ApplicationInsights--ConnectionString`

### Deployment

#### Using Azure CLI

```bash
# Set environment
ENVIRONMENT="dev"
RG_NAME="rg-orderprocessing-$ENVIRONMENT"

# Create resource group if needed
az group create --name $RG_NAME --location centralindia

# Deploy template
az deployment group create \
  --name deploy-kv-$(date +%s) \
  --resource-group $RG_NAME \
  --template-file bicep/appservice-with-kv.bicep \
  --parameters @bicep/parameters/$ENVIRONMENT.parameters.json
```

#### Using GitHub Actions

The deployment is automated via the `.github/workflows/deploy-and-verify.yml` workflow:
- Pushes to `dev` branch → deploys to dev environment
- Pushes to `uat` branch → deploys to uat environment
- Pushes to `main` branch → deploys to prod environment

### Validation

After deployment, validate the setup:

```bash
# Check app settings
az webapp config appsettings list \
  --name <app-name> \
  --resource-group <resource-group> \
  --output table

# Test health endpoint
curl https://<app-name>.azurewebsites.net/api/info/environment
```

## Template Parameters

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `appName` | Name of the App Service | Yes | - |
| `keyVaultName` | Name of the Key Vault to create | Yes | - |
| `appServicePlanName` | Name of the App Service Plan | Yes | - |
| `location` | Azure region | No | Resource Group location |
| `appServiceSku` | App Service Plan SKU (F1, B1, P1v3) | No | F1 |
| `environment` | Environment name (dev, uat, prod) | No | dev |
| `openPayAdapterBaseUrl` | OpenPay Adapter base URL (non-secret) | No | https://api.openpay.example.com |

## App Settings

The template configures the following app settings:

### Non-Secret Settings
- `ASPNETCORE_ENVIRONMENT`: Mapped from environment parameter (Development/Staging/Production)
- `OpenPayAdapter__BaseUrl`: OpenPay Adapter base URL

### Secret Settings (Key Vault References)
- `OpenPayAdapter__ApiKey`: References Key Vault secret `OpenPayAdapter--ApiKey`
- `APPLICATIONINSIGHTS_CONNECTION_STRING`: References Key Vault secret `ApplicationInsights--ConnectionString`

## Managed Identity

The template enables System-Assigned Managed Identity on the App Service and grants it the following permissions on Key Vault:
- `get` - Read secret values
- `list` - List secrets

## Security Considerations

1. **Key Vault Soft Delete**: Soft delete is enabled with 90-day retention to protect against accidental deletion
2. **Network Restrictions**: For production, consider restricting Key Vault access to specific virtual networks
3. **Audit Logging**: Enable diagnostic logs on Key Vault to track secret access
4. **Secret Rotation**: Implement a secret rotation strategy for production secrets
5. **Least Privilege**: The Managed Identity has minimal required permissions (get, list)

## Troubleshooting

### Key Vault References Not Resolving

If app settings show `@Microsoft.KeyVault(...)` but secrets aren't resolved:

1. Verify the Key Vault exists and contains the required secrets
2. Check the Managed Identity has access to Key Vault
3. Verify the secret URI format is correct
4. Restart the App Service after granting permissions

### Deployment Errors

Common issues:
- **Key Vault name conflict**: If deployment fails because Key Vault name is taken, choose a different name or wait for soft delete retention period
- **Insufficient permissions**: Ensure you have Contributor access to the resource group
- **Invalid SKU**: Verify the App Service Plan SKU is valid for your subscription

## References

- [Azure Bicep Documentation](https://docs.microsoft.com/azure/azure-resource-manager/bicep/)
- [Key Vault References](https://docs.microsoft.com/azure/app-service/app-service-key-vault-references)
- [Managed Identities](https://docs.microsoft.com/azure/active-directory/managed-identities-azure-resources/)
- [Runbook: Key Vault and Managed Identity Deployment](../docs/runbooks/keyvault-managed-identity-deploy.md)
