# Key Vault Configuration Guide

## Overview

This guide addresses common Key Vault configuration issues and provides step-by-step instructions to ensure your Azure Key Vault is properly configured and accessible by your App Services using Managed Identity.

## Common Issues

### Issue 1: Key Vault is Empty (No Secrets)

**Symptoms:**
- Key Vault exists but contains no secrets
- Applications work but may be using fallback configurations

**Solution:**
Run the secret population script:

```powershell
.\Resources\Azure-Deployment\populate-keyvault-secrets.ps1 -Environment dev
```

This script will:
- ✅ Add `OpenPayAdapter--ApiKey` secret (with placeholder for dev/staging)
- ✅ Add `ApplicationInsights--ConnectionString` secret (auto-retrieved)
- ✅ Set `KEY_VAULT_NAME` environment variable on App Services
- ✅ Verify all secrets were added successfully

### Issue 2: Managed Identity Not Assigned

**Symptoms:**
- `verify-azure-setup.ps1` reports "Managed Identity not assigned"
- App Services cannot access Key Vault
- Error: "⚠️ Managed Identity not assigned - Will enable"

**Solution:**
Run the managed identity enablement script:

```powershell
.\Resources\Azure-Deployment\enable-managed-identity.ps1 -Environment dev
```

This script will:
- ✅ Enable System-Assigned Managed Identity on API App
- ✅ Enable System-Assigned Managed Identity on UI App
- ✅ Grant both identities `get` and `list` permissions on Key Vault secrets
- ✅ Set `KEY_VAULT_NAME` environment variable on App Services
- ✅ Verify configuration is correct

**Manual Alternative:**

```bash
# 1. Enable Managed Identity on API App
az webapp identity assign \
  -g rg-orderprocessing-dev \
  -n pavanthakur-orderprocessing-api-xyapp-dev

# Get the principalId from the output
PRINCIPAL_ID="<principalId from output>"

# 2. Grant Key Vault access
az keyvault set-policy \
  -n kv-orderproc-dev \
  --object-id $PRINCIPAL_ID \
  --secret-permissions get list

# 3. Set environment variable
az webapp config appsettings set \
  -g rg-orderprocessing-dev \
  -n pavanthakur-orderprocessing-api-xyapp-dev \
  --settings KEY_VAULT_NAME=kv-orderproc-dev

# 4. Restart the app
az webapp restart \
  -g rg-orderprocessing-dev \
  -n pavanthakur-orderprocessing-api-xyapp-dev
```

## Complete Setup Workflow

Follow this sequence to ensure everything is properly configured:

### Step 1: Verify Current Setup

```powershell
.\Resources\Azure-Deployment\verify-azure-setup.ps1
```

This will check:
- App Services status
- Application Insights
- SQL Database
- Key Vault existence and secrets
- Managed Identity status
- Key Vault access policies

### Step 2: Enable Managed Identity (if needed)

If verification shows "⚠️ Managed Identity not assigned":

```powershell
.\Resources\Azure-Deployment\enable-managed-identity.ps1 -Environment dev
```

### Step 3: Populate Key Vault Secrets (if needed)

If verification shows "⚠️ Secrets: None found":

```powershell
.\Resources\Azure-Deployment\populate-keyvault-secrets.ps1 -Environment dev
```

### Step 4: Restart App Services

After configuration changes, restart the apps:

```powershell
az webapp restart -g rg-orderprocessing-dev -n pavanthakur-orderprocessing-api-xyapp-dev
az webapp restart -g rg-orderprocessing-dev -n pavanthakur-orderprocessing-ui-xyapp-dev
```

### Step 5: Verify Again

Run the verification script again to confirm everything is working:

```powershell
.\Resources\Azure-Deployment\verify-azure-setup.ps1
```

You should see:
- ✅ Key Vault with secrets listed
- ✅ API App Managed Identity with principal ID
- ✅ Managed Identity has Key Vault access

## How It Works

### Infrastructure Setup

The Bicep templates create:

1. **App Services with Managed Identity** (`infra/modules/hosting.bicep`)
   ```bicep
   identity: {
     type: 'SystemAssigned'
   }
   ```

2. **Key Vault with Access Policies** (`infra/modules/keyvault.bicep`)
   ```bicep
   accessPolicies: [
     {
       objectId: apiAppPrincipalId
       permissions: {
         secrets: ['get', 'list']
       }
     }
   ]
   ```

### Application Configuration

The application uses `SharedSettingsLoader.cs` which:

1. Detects Azure environment via `WEBSITE_SITE_NAME` variable
2. Reads `KEY_VAULT_NAME` environment variable
3. Constructs Key Vault URI: `https://{keyVaultName}.vault.azure.net/`
4. Uses `DefaultAzureCredential` to authenticate (supports Managed Identity)
5. Loads all secrets from Key Vault into configuration

**Code snippet:**
```csharp
var keyVaultName = Environment.GetEnvironmentVariable("KEY_VAULT_NAME");
var keyVaultUri = $"https://{keyVaultName}.vault.azure.net/";

builder.AddAzureKeyVault(
    new Uri(keyVaultUri),
    new DefaultAzureCredential());
```

### Secret Naming Convention

Secrets use `--` (double dash) as separator (converted to `:` in configuration):

- `OpenPayAdapter--ApiKey` → `OpenPayAdapter:ApiKey`
- `ApplicationInsights--ConnectionString` → `ApplicationInsights:ConnectionString`

This matches the configuration section structure in `appsettings.json`.

## Troubleshooting

### "Key Vault not found"

**Cause:** Key Vault name mismatch or infrastructure not deployed

**Solution:**
1. Check Key Vault exists:
   ```bash
   az keyvault list -g rg-orderprocessing-dev --query "[].name" -o tsv
   ```
2. Verify the name matches the pattern: `kv-orderproc-dev` (shortened base name)
3. If it doesn't exist, deploy infrastructure:
   ```bash
   az deployment sub create \
     --location centralindia \
     --template-file infra/main.bicep \
     --parameters @infra/parameters/dev.json
   ```

### "Access Denied" or "Forbidden"

**Cause:** Managed Identity doesn't have Key Vault permissions

**Solution:**
Run the enable-managed-identity script:
```powershell
.\Resources\Azure-Deployment\enable-managed-identity.ps1 -Environment dev
```

### "Cannot connect to Key Vault"

**Cause:** Network restrictions or firewall rules

**Solution:**
1. Check Key Vault network settings:
   ```bash
   az keyvault show -n kv-orderproc-dev -g rg-orderprocessing-dev \
     --query properties.networkAcls
   ```
2. If firewall is enabled, add your IP or allow Azure services:
   ```bash
   az keyvault network-rule add -n kv-orderproc-dev \
     --ip-address <your-ip>
   ```

### "Invalid Key Vault name format"

**Cause:** Key Vault name doesn't meet Azure requirements (3-24 chars, alphanumeric and hyphens)

**Solution:**
The scripts automatically shorten the base name to fit. If you see this error, check:
1. Base name length
2. Environment name length
3. Combined length: `kv-{baseName}-{env}` must be ≤ 24 characters

### App Still Not Reading from Key Vault

**Checklist:**
1. ✅ Managed Identity is enabled and has correct principal ID
2. ✅ Key Vault access policy includes the principal ID
3. ✅ Secrets exist in Key Vault with correct names
4. ✅ `KEY_VAULT_NAME` environment variable is set on App Service
5. ✅ App Service has been restarted after configuration changes

**Diagnostic Steps:**
```bash
# Check environment variable
az webapp config appsettings list \
  -g rg-orderprocessing-dev \
  -n pavanthakur-orderprocessing-api-xyapp-dev \
  --query "[?name=='KEY_VAULT_NAME']"

# Check application logs
az webapp log tail \
  -g rg-orderprocessing-dev \
  -n pavanthakur-orderprocessing-api-xyapp-dev

# Look for Key Vault debug messages in logs
```

## Production Considerations

### Before Production Deployment

1. **Update OpenPayAdapter API Key:**
   ```powershell
   az keyvault secret set \
     --vault-name kv-orderproc-prod \
     --name "OpenPayAdapter--ApiKey" \
     --value "your-production-api-key"
   ```

2. **Review Access Policies:**
   - Ensure only necessary identities have access
   - Use least privilege principle (get/list only)
   - Consider using Azure RBAC instead of access policies

3. **Enable Monitoring:**
   - Set up Key Vault diagnostic logs
   - Monitor access patterns
   - Set up alerts for unauthorized access attempts

4. **Backup and Disaster Recovery:**
   - Soft delete is already enabled (90 days retention)
   - Document secret rotation procedures
   - Test recovery procedures

### Secret Rotation

To rotate a secret:
```bash
# Add new version
az keyvault secret set \
  --vault-name kv-orderproc-prod \
  --name "OpenPayAdapter--ApiKey" \
  --value "new-api-key"

# No app restart needed - apps will pick up new version automatically
```

## Related Files

- **Scripts:**
  - `enable-managed-identity.ps1` - Enable MI and grant access
  - `populate-keyvault-secrets.ps1` - Add secrets to Key Vault
  - `verify-azure-setup.ps1` - Verify configuration

- **Infrastructure:**
  - `infra/modules/keyvault.bicep` - Key Vault definition
  - `infra/modules/hosting.bicep` - App Services with Managed Identity
  - `infra/main.bicep` - Main infrastructure template

- **Application Code:**
  - `XYDataLabs.OrderProcessingSystem.Utilities/SharedSettingsLoader.cs` - Configuration loader

## Quick Reference

| Task | Command |
|------|---------|
| Enable Managed Identity | `.\Resources\Azure-Deployment\enable-managed-identity.ps1 -Environment dev` |
| Populate Secrets | `.\Resources\Azure-Deployment\populate-keyvault-secrets.ps1 -Environment dev` |
| Verify Setup | `.\Resources\Azure-Deployment\verify-azure-setup.ps1` |
| List Secrets | `az keyvault secret list --vault-name kv-orderproc-dev --query "[].name"` |
| Update Secret | `az keyvault secret set --vault-name kv-orderproc-dev --name "SecretName" --value "value"` |
| Check MI Principal ID | `az webapp identity show -g rg-orderprocessing-dev -n pavanthakur-orderprocessing-api-xyapp-dev` |
| Check Access Policies | `az keyvault show -n kv-orderproc-dev --query properties.accessPolicies` |
| Restart App | `az webapp restart -g rg-orderprocessing-dev -n pavanthakur-orderprocessing-api-xyapp-dev` |

## Support

If you encounter issues not covered in this guide:

1. Run the verification script and check output
2. Review application logs for Key Vault connection errors
3. Verify Azure CLI is authenticated: `az account show`
4. Check you have necessary permissions on Azure subscription

---

**Last Updated:** 2025-12-08  
**Version:** 1.0
