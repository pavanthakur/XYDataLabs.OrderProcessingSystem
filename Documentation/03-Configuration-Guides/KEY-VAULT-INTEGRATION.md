# Azure Key Vault Integration Guide

## Overview

This guide explains how OpenPay secrets are securely stored and accessed using Azure Key Vault across different environments (dev, uat, prod).

> **Note**: Key Vault secrets are **automatically populated** during CI/CD deployment. See [KEYVAULT-SECRET-AUTOMATION.md](../../KEYVAULT-SECRET-AUTOMATION.md) for automation details.

## Architecture

### Key Vault Structure

Each environment has its own dedicated Key Vault:
- **Dev**: `kv-orderprocessing-dev`
- **Staging**: `kv-orderprocessing-staging`
- **Prod**: `kv-orderprocessing-prod`

### Secret Naming Convention

Secrets use hierarchical naming with double-dash (`--`) separator for ASP.NET Core configuration compatibility:

```
OpenPay--MerchantId
OpenPay--PrivateKey
OpenPay--DeviceSessionId
OpenPay--IsProduction
OpenPay--RedirectUrl
OpenPayAdapter--ApiKey
ApplicationInsights--ConnectionString
```

This naming convention allows ASP.NET Core to automatically bind these secrets to their respective configuration sections.

## Deployment

### Infrastructure Setup (Automated)

The Key Vault infrastructure is automatically created during bootstrap deployment:

```powershell
./Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1 -Environment dev
```

The bootstrap script performs:
1. Creates the Key Vault for the specified environment
2. Enables system-assigned managed identity for API and UI web apps
3. Grants Key Vault access policies to the web app managed identities
4. Sets the `KEY_VAULT_NAME` environment variable for web apps

### Secrets Population (Automated)

Secrets are automatically populated by the CI/CD workflow using a dedicated script:

```powershell
./Resources/Azure-Deployment/populate-keyvault-secrets.ps1 -Environment dev
```

This script:
1. Adds `OpenPayAdapter--ApiKey` (placeholder for dev/staging, actual key for prod)
2. Auto-retrieves and adds `ApplicationInsights--ConnectionString`
3. Validates Key Vault exists before adding secrets
4. Provides comprehensive logging and error handling

See [KEYVAULT-SECRET-AUTOMATION.md](../../KEYVAULT-SECRET-AUTOMATION.md) for complete automation details.

### Manual Key Vault Operations

#### View Secrets
```bash
az keyvault secret list --vault-name kv-orderprocessing-dev
```

#### Get Secret Value
```bash
az keyvault secret show --vault-name kv-orderprocessing-dev --name OpenPay--MerchantId
```

#### Update Secret
```bash
echo "new-secret-value" | az keyvault secret set --vault-name kv-orderprocessing-dev --name OpenPay--MerchantId --file -
```

## Application Configuration

### Azure Environment

When running in Azure App Service:
1. The application detects Azure environment via `WEBSITE_SITE_NAME` environment variable
2. `SharedSettingsLoader` automatically adds Azure Key Vault as a configuration source
3. Uses `DefaultAzureCredential` which leverages the web app's managed identity
4. Key Vault secrets override values from `sharedsettings.{env}.json`

### Local/Docker Environment

When running locally or in Docker:
1. Application uses file-based configuration from `sharedsettings.local.json` or `sharedsettings.dev.json`
2. Key Vault is **not** accessed (maintains existing behavior)
3. No Azure credentials required for local development

## Security Features

### Managed Identity
- Uses **system-assigned managed identity** for authentication
- No connection strings or passwords required
- Automatic credential rotation

### Access Control
- Access policies grant only `get` and `list` permissions for secrets
- Separate managed identity per web app (API and UI)
- Principle of least privilege

### Secure Secret Handling
- Secrets passed via stdin during deployment (not command line)
- Key Vault name validation to prevent injection attacks
- Graceful fallback to file-based configuration on errors

## Configuration Code

### SharedSettingsLoader Enhancement

```csharp
// Automatically loads Key Vault when running in Azure
if (isAzure)
{
    var keyVaultName = Environment.GetEnvironmentVariable("KEY_VAULT_NAME") 
        ?? $"kv-orderprocessing-{effectiveEnvironment}";
    
    var keyVaultUri = $"https://{keyVaultName}.vault.azure.net/";
    
    builder.AddAzureKeyVault(
        new Uri(keyVaultUri),
        new DefaultAzureCredential());
}
```

## Troubleshooting

### Key Vault Access Denied

**Problem**: Web app cannot access Key Vault secrets
**Solution**: 
1. Verify managed identity is enabled: `az webapp identity show -g <rg> -n <app-name>`
2. Check access policies: `az keyvault show -n <kv-name> --query properties.accessPolicies`
3. Re-run bootstrap script to fix access policies

### Secrets Not Loading

**Problem**: Application not reading secrets from Key Vault
**Solution**:
1. Check `KEY_VAULT_NAME` environment variable in App Service settings
2. Verify Key Vault name matches the expected pattern: `kv-orderprocessing-{env}`
3. Review application logs for Key Vault connection errors

### Local Development

**Problem**: Want to test with Key Vault locally
**Solution**:
1. Install Azure CLI and login: `az login`
2. Set environment variable: `$env:WEBSITE_SITE_NAME="local-test"`
3. Set Key Vault name: `$env:KEY_VAULT_NAME="kv-orderprocessing-dev"`
4. Your Azure CLI credentials will be used via `DefaultAzureCredential`

## Migration Notes

### Updating Secrets

To update Key Vault secrets:

**Option 1: Run the populate script**
```powershell
./Resources/Azure-Deployment/populate-keyvault-secrets.ps1 -Environment {env} -OpenPayApiKey "new-key"
```

**Option 2: Use Azure CLI directly**
```bash
az keyvault secret set --vault-name kv-orderprocessing-{env} --name OpenPayAdapter--ApiKey --value "new-key"
```

Web apps will automatically pick up new values (no restart required).

### Adding New Secrets

To add new secrets to Key Vault:

1. Update the `$secrets` hashtable in bootstrap script:
   ```powershell
   $secrets = @{
       "OpenPay--MerchantId" = $openPayConfig.MerchantId
       "OpenPay--NewSecret" = $openPayConfig.NewSecret  # Add new secret
   }
   ```
2. Re-run bootstrap script
3. Access in code via `IConfiguration`: `configuration["OpenPay:NewSecret"]`

## References

- [Azure Key Vault Documentation](https://docs.microsoft.com/azure/key-vault/)
- [Managed Identity Documentation](https://docs.microsoft.com/azure/active-directory/managed-identities-azure-resources/)
- [ASP.NET Core Configuration](https://docs.microsoft.com/aspnet/core/fundamentals/configuration/)
