# Key Vault Access Investigation Guide

## Overview

This document provides a comprehensive guide to investigating and resolving Key Vault access issues that prevent the UI and API applications from starting in Azure App Service.

## Problem Statement

The UI and API applications fail to start with a Key Vault configuration error. The `SharedSettingsLoader.cs` enforces a strict Key Vault requirement for Azure deployments, and the application throws an exception if Key Vault cannot be accessed.

## Common Root Causes

Based on the documentation and code analysis, Key Vault access failures typically occur due to one or more of the following:

### 1. Missing or Incorrect KEY_VAULT_NAME Environment Variable
**Symptom:** Application logs show "KEY_VAULT_NAME environment variable not set" warning  
**Impact:** Application constructs Key Vault name incorrectly or uses wrong Key Vault  

**Check:**
```powershell
az webapp config appsettings list -g rg-orderprocessing-dev -n pavanthakur-orderprocessing-api-xyapp-dev --query "[?name=='KEY_VAULT_NAME']"
```

**Fix:**
```powershell
$kvName = "kv-orderproc-dev"  # Replace with actual Key Vault name
az webapp config appsettings set -g rg-orderprocessing-dev -n pavanthakur-orderprocessing-api-xyapp-dev --settings KEY_VAULT_NAME=$kvName
az webapp config appsettings set -g rg-orderprocessing-dev -n pavanthakur-orderprocessing-ui-xyapp-dev --settings KEY_VAULT_NAME=$kvName
```

### 2. Managed Identity Not Enabled
**Symptom:** Error message mentions "DefaultAzureCredential" or authentication failures  
**Impact:** Application cannot authenticate to Key Vault  

**Check:**
```powershell
az webapp identity show -g rg-orderprocessing-dev -n pavanthakur-orderprocessing-api-xyapp-dev
```

**Fix:**
```powershell
az webapp identity assign -g rg-orderprocessing-dev -n pavanthakur-orderprocessing-api-xyapp-dev
az webapp identity assign -g rg-orderprocessing-dev -n pavanthakur-orderprocessing-ui-xyapp-dev
```

### 3. Missing Key Vault Access Policies
**Symptom:** Authentication succeeds but authorization fails (403 Forbidden)  
**Impact:** Managed Identity cannot access Key Vault secrets  

**Check:**
```powershell
$identity = az webapp identity show -g rg-orderprocessing-dev -n pavanthakur-orderprocessing-api-xyapp-dev --query principalId -o tsv
az keyvault show -n kv-orderproc-dev --query "properties.accessPolicies[?objectId=='$identity']"
```

**Fix:**
```powershell
$apiIdentity = az webapp identity show -g rg-orderprocessing-dev -n pavanthakur-orderprocessing-api-xyapp-dev --query principalId -o tsv
$uiIdentity = az webapp identity show -g rg-orderprocessing-dev -n pavanthakur-orderprocessing-ui-xyapp-dev --query principalId -o tsv

az keyvault set-policy -n kv-orderproc-dev --object-id $apiIdentity --secret-permissions get list
az keyvault set-policy -n kv-orderproc-dev --object-id $uiIdentity --secret-permissions get list
```

### 4. Invalid Key Vault Name Format
**Symptom:** Error message shows "Invalid Key Vault name format"  
**Impact:** Key Vault URI is malformed  

**Requirements:**
- 3-24 characters
- Alphanumeric and hyphens only
- Must be globally unique
- No underscores or other special characters

**Check:**
```powershell
# Key Vault name should match pattern: ^[a-zA-Z0-9\-]{3,24}$
$kvName = "kv-orderproc-dev"  # Valid
# "kv_orderproc_dev" would be INVALID (underscores not allowed)
```

### 5. Empty Key Vault (No Secrets)
**Symptom:** Application starts but fails to find required configuration  
**Impact:** Application cannot load secrets from Key Vault  

**Check:**
```powershell
az keyvault secret list --vault-name kv-orderproc-dev --query "[].name"
```

**Fix:**
```powershell
./Resources/Azure-Deployment/populate-keyvault-secrets.ps1 -Environment dev
```

### 6. Key Vault Doesn't Exist
**Symptom:** DNS or connection errors  
**Impact:** Key Vault endpoint cannot be reached  

**Check:**
```powershell
az keyvault list -g rg-orderprocessing-dev
```

**Fix:**
Run Azure Bootstrap workflow to create infrastructure

## Diagnostic Tool

A comprehensive diagnostic script has been created to automatically check all common issues:

### Usage
```powershell
# Run diagnostic for dev environment
./Resources/Azure-Deployment/diagnose-keyvault-access.ps1 -Environment dev

# For other environments
./Resources/Azure-Deployment/diagnose-keyvault-access.ps1 -Environment staging
./Resources/Azure-Deployment/diagnose-keyvault-access.ps1 -Environment prod
```

### What It Checks
1. ✅ Resource Group existence
2. ✅ Key Vault existence and name
3. ✅ Key Vault name format validation
4. ✅ KEY_VAULT_NAME environment variable on App Services
5. ✅ Managed Identity on API and UI App Services
6. ✅ Key Vault access policies for Managed Identities
7. ✅ Key Vault secrets (empty or populated)
8. ✅ ASPNETCORE_ENVIRONMENT configuration
9. ✅ Key Vault endpoint connectivity

### Sample Output
```
╔════════════════════════════════════════════════════════════════╗
║     KEY VAULT ACCESS DIAGNOSTIC - DEV                          ║
╚════════════════════════════════════════════════════════════════╝

[Step 1] Verifying Resource Group...
  ✅ Resource Group exists: rg-orderprocessing-dev

[Step 2] Locating Key Vault...
  ✅ Key Vault found: kv-orderproc-dev

[Step 3] Validating Key Vault name format...
  ✅ Key Vault name format is valid

[Step 4] Checking KEY_VAULT_NAME environment variable...
  ❌ API App missing KEY_VAULT_NAME environment variable
  💡 Run: az webapp config appsettings set -g rg-orderprocessing-dev -n pavanthakur-orderprocessing-api-xyapp-dev --settings KEY_VAULT_NAME=kv-orderproc-dev

...
```

## Quick Fix - All-in-One Solution

If you want to fix all common Managed Identity and Key Vault access issues at once:

```powershell
# Step 1: Enable Managed Identity and configure Key Vault access
./Resources/Azure-Deployment/enable-managed-identity.ps1 -Environment dev

# Step 2: Populate Key Vault with required secrets
./Resources/Azure-Deployment/populate-keyvault-secrets.ps1 -Environment dev

# Step 3: Restart applications to apply changes
az webapp restart -g rg-orderprocessing-dev -n pavanthakur-orderprocessing-api-xyapp-dev
az webapp restart -g rg-orderprocessing-dev -n pavanthakur-orderprocessing-ui-xyapp-dev

# Step 4: Verify setup
./Resources/Azure-Deployment/verify-azure-setup.ps1 -Environment dev
```

## Viewing Application Logs

After attempting fixes, check application logs to see if the issue is resolved:

### Azure Portal
1. Navigate to App Service → Monitoring → Log stream
2. Look for Key Vault related messages:
   - `[INFO] Attempting to load secrets from Key Vault:`
   - `[SUCCESS] Azure Key Vault configuration added successfully`
   - Or error messages with `[CRITICAL ERROR]`

### Azure CLI
```powershell
# View recent logs
az webapp log tail -g rg-orderprocessing-dev -n pavanthakur-orderprocessing-api-xyapp-dev

# Download log file
az webapp log download -g rg-orderprocessing-dev -n pavanthakur-orderprocessing-api-xyapp-dev
```

### Application Insights
```powershell
# Query for Key Vault related errors
./Resources/Azure-Deployment/query-app-insights-errors.ps1 -Environment dev
```

## Understanding the Error Messages

### From SharedSettingsLoader.cs

#### Success Messages
```
[INFO] Attempting to load secrets from Key Vault: https://kv-orderproc-dev.vault.azure.net/
[SUCCESS] Azure Key Vault configuration added successfully: https://kv-orderproc-dev.vault.azure.net/
[INFO] Application will use Key Vault for secure secret management
```

#### Error Messages
```
[CRITICAL ERROR] Failed to configure Azure Key Vault in Azure environment. 
This is a mandatory requirement for production deployments. 
Error: <specific error details>
```

#### Possible Specific Errors
1. **"No connection could be made"** → Key Vault doesn't exist or networking issue
2. **"Authentication failed"** → Managed Identity not enabled or not working
3. **"Forbidden"** → Managed Identity lacks Key Vault access policies
4. **"Invalid Key Vault name"** → Name format validation failed

## Code Reference

The Key Vault check is implemented in `SharedSettingsLoader.cs` (lines 60-116):

```csharp
if (isAzure)
{
    try
    {
        var keyVaultName = Environment.GetEnvironmentVariable("KEY_VAULT_NAME");
        if (string.IsNullOrWhiteSpace(keyVaultName))
        {
            keyVaultName = $"kv-orderprocessing-{effectiveEnvironment}";
            Console.WriteLine($"[WARN] KEY_VAULT_NAME environment variable not set...");
        }
        
        // Validate format
        if (!IsValidKeyVaultName(keyVaultName))
        {
            throw new InvalidOperationException("Invalid Key Vault name format");
        }
        
        var keyVaultUri = $"https://{keyVaultName}.vault.azure.net/";
        builder.AddAzureKeyVault(new Uri(keyVaultUri), new DefaultAzureCredential());
    }
    catch (Exception ex)
    {
        // Throws exception - application fails to start
        throw new InvalidOperationException(
            "Azure Key Vault configuration is mandatory for Azure deployments...", ex);
    }
}
```

## Why Key Vault Is Mandatory

The strict Key Vault requirement is intentional and enforces enterprise security practices:

1. **Security**: Secrets should never be stored in configuration files in production
2. **Compliance**: Enterprise policies require centralized secret management
3. **Auditability**: Key Vault logs all secret access attempts
4. **Rotation**: Secrets can be rotated without redeploying applications
5. **Separation of Concerns**: Infrastructure team manages secrets, not developers

## Best Practices

1. **Always use Managed Identity** - Never use connection strings or keys for Key Vault access
2. **Set KEY_VAULT_NAME explicitly** - Don't rely on name construction logic
3. **Use least privilege** - Only grant 'get' and 'list' permissions on secrets
4. **Monitor access** - Enable Key Vault diagnostic logs
5. **Populate secrets early** - Run populate-keyvault-secrets.ps1 immediately after infrastructure deployment

## Related Documentation

- `KEYVAULT-CONFIGURATION-FIX-SUMMARY.md` - Previous Key Vault configuration work
- `KEYVAULT-SECRET-AUTOMATION.md` - Secret automation overview
- `Resources/Azure-Deployment/README-KEYVAULT-SETUP.md` - Key Vault setup guide
- `Resources/Azure-Deployment/enable-managed-identity.ps1` - Managed Identity setup script
- `Resources/Azure-Deployment/populate-keyvault-secrets.ps1` - Secret population script
- `Resources/Azure-Deployment/verify-azure-setup.ps1` - Verification script

## Troubleshooting Workflow

```
1. Run diagnostic script
   └─→ Issues found?
       ├─→ YES: Follow remediation steps from diagnostic output
       │   └─→ Run enable-managed-identity.ps1
       │   └─→ Run populate-keyvault-secrets.ps1
       │   └─→ Restart applications
       │   └─→ Return to step 1
       └─→ NO: Check application logs for specific error
           └─→ Review error message details
           └─→ Check Application Insights
           └─→ Verify application logs in Azure Portal
```

---

**Created:** 2025-12-08  
**Purpose:** Investigation and resolution guide for Key Vault access issues  
**Maintains:** Strict Key Vault requirement for enterprise security compliance
