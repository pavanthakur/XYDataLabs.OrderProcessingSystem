# Key Vault Verification Guide

This guide provides comprehensive instructions for verifying the Azure Key Vault setup created by PR#54 and the GitHub workflow automation from PR#5.

## Table of Contents
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Azure Portal Verification](#azure-portal-verification)
- [Application Integration Verification](#application-integration-verification)
- [PR#5 and PR#54 Changes Verification](#pr5-and-pr54-changes-verification)
- [Troubleshooting](#troubleshooting)
- [Automated Verification Scripts](#automated-verification-scripts)

## Overview

### What Was Implemented

**PR#54 - Key Vault Creation**
- Created Azure Key Vault automatically during deployment (no manual pre-creation needed)
- Configured Key Vault with:
  - Standard SKU
  - Soft delete enabled (90-day retention)
  - System-Assigned Managed Identity access
  - Access policies for App Service

**PR#5 - GitHub Workflow Automation**
- Removed manual `GH_PAT` token requirement
- Automated GitHub token authentication using `GITHUB_TOKEN`
- Enabled `secrets: write` permission for environment secret configuration
- Streamlined Azure Bootstrap workflow

### Key Vault Purpose
The Key Vault stores sensitive configuration values:
- `OpenPayAdapter--ApiKey`: API key for OpenPay payment adapter
- `ApplicationInsights--ConnectionString`: Connection string for Application Insights telemetry

## Prerequisites

Before verifying, ensure you have:
- Azure Portal access with at least **Reader** role on the resource group
- Azure CLI installed (for command-line verification)
- Access to the deployed App Service
- (Optional) PowerShell 7+ for running verification scripts

## Azure Portal Verification

### Step 1: Verify Key Vault Exists

1. **Navigate to Azure Portal**: https://portal.azure.com
2. **Search for Key Vaults**: Use the search bar at the top
3. **Locate Your Key Vault**: Should be named `kv-orderproc-dev` (for dev environment)
   - Expected naming pattern: `kv-orderproc-{environment}`

**What to Check:**
- ✅ Key Vault exists in the correct resource group (`rg-orderprocessing-dev`)
- ✅ Location matches your deployment region (e.g., `Central India`)
- ✅ Status is "Available"

### Step 2: Verify Key Vault Configuration

Navigate to your Key Vault and check the following:

#### A. Properties Tab
**Path:** Key Vault → Overview → Properties

Check:
- ✅ **Vault URI**: Should be `https://kv-orderproc-dev.vault.azure.net/`
- ✅ **Pricing Tier**: Standard
- ✅ **Soft Delete**: Enabled
- ✅ **Soft Delete Retention**: 90 days
- ✅ **Purge Protection**: (Optional, but recommended for production)

#### B. Access Policies
**Path:** Key Vault → Access policies

Verify:
- ✅ **App Service Managed Identity** has access with permissions:
  - **Secret permissions**: Get, List
  - Look for an access policy with the App Service's managed identity name
  - Identity name format: `{githubOwner}-orderprocessing-api-xyapp-{environment}`

**How to verify the Managed Identity:**
```
1. In the Key Vault, click "Access policies"
2. Look for an entry with your App Service name
3. Click on it to see the permissions
4. Verify "Get" and "List" are checked under "Secret permissions"
```

#### C. Secrets
**Path:** Key Vault → Secrets

Verify that these secrets exist (you may need "List" permission):
- ✅ `OpenPayAdapter--ApiKey`
- ✅ `ApplicationInsights--ConnectionString`

**Note:** You may not be able to view the secret values unless you have "Get" permission. That's okay - just verify the secrets exist.

### Step 3: Verify Network Access (Optional)

**Path:** Key Vault → Networking

For development:
- ✅ Public network access: **All networks** (or selected networks including your IP)

For production:
- Consider restricting to **Selected networks** or **Private endpoint**

### Step 4: Verify Tags

**Path:** Key Vault → Tags

Expected tags:
- `environment`: dev (or staging/prod)
- `app`: orderprocessing

## Application Integration Verification

### Step 5: Verify App Service Configuration

1. **Navigate to App Service**
   - Search for your App Service: `{githubOwner}-orderprocessing-api-xyapp-{environment}`
   - Example: `pavanthakur-orderprocessing-api-xyapp-dev`

2. **Check Managed Identity**
   - **Path:** App Service → Identity → System assigned
   - ✅ Status: **On**
   - ✅ Object (principal) ID is displayed
   - This identity is what Key Vault uses to grant access

3. **Check Application Settings**
   - **Path:** App Service → Configuration → Application settings
   
   Look for Key Vault references (they start with `@Microsoft.KeyVault`):
   ```
   OpenPayAdapter__ApiKey = @Microsoft.KeyVault(SecretUri=https://kv-orderproc-dev.vault.azure.net/secrets/OpenPayAdapter--ApiKey/)
   APPLICATIONINSIGHTS_CONNECTION_STRING = @Microsoft.KeyVault(SecretUri=https://kv-orderproc-dev.vault.azure.net/secrets/ApplicationInsights--ConnectionString/)
   ```

   **Note:** The `--` in Key Vault secret names becomes `__` (double underscore) in application settings.

4. **Verify Key Vault Reference Status**
   - Next to each Key Vault reference, there should be a green checkmark or status
   - Green = Resolved successfully
   - Red = Error accessing Key Vault (see troubleshooting)

### Step 6: Test Application Endpoints

1. **Get App Service URL**
   - **Path:** App Service → Overview
   - Copy the URL: `https://{app-name}.azurewebsites.net`

2. **Test Configuration Endpoint** (if available)
   ```bash
   curl https://{app-name}.azurewebsites.net/api/health
   # or
   curl https://{app-name}.azurewebsites.net/api/info/environment
   ```

3. **Check Application Insights**
   - **Path:** Application Insights → Live Metrics
   - Verify telemetry is being received
   - Check for any configuration errors in the logs

### Step 7: Verify Logs

**Path:** App Service → Log stream (or Monitoring → Logs)

Look for log entries confirming:
- ✅ Application Insights configuration loaded
- ✅ No Key Vault access errors
- ✅ Configuration sections loaded successfully

Example log entries to look for:
```
[CONFIG] Application Insights enabled for dev environment
[CONFIG] Resolved DB connection: Server=...
```

## PR#5 and PR#54 Changes Verification

### Verify PR#5 Changes (GitHub Workflow Automation)

1. **Check Workflow File**
   - **Path:** `.github/workflows/azure-bootstrap.yml`
   - Verify:
     - ✅ No references to `secrets.GH_PAT`
     - ✅ Uses `secrets.GITHUB_TOKEN` instead
     - ✅ Has `permissions: secrets: write`

2. **Check GitHub Environment Secrets**
   - Navigate to: GitHub Repository → Settings → Environments → {environment-name}
   - Verify auto-generated secrets exist:
     - `AZURE_CLIENT_ID`
     - `AZURE_SUBSCRIPTION_ID`
     - `AZURE_TENANT_ID`

3. **Test Workflow Execution**
   - Check recent workflow runs: https://github.com/{owner}/{repo}/actions
   - Verify Azure Bootstrap workflow completes without manual token errors

### Verify PR#54 Changes (Key Vault Creation)

1. **Check Bicep Template** (if exists in your repository)
   - **Path:** `bicep/appservice-with-kv.bicep` or similar
   - Verify Key Vault is created (not referenced as `existing`)
   - Configuration includes:
     ```bicep
     enableSoftDelete: true
     softDeleteRetentionInDays: 90
     ```

2. **Check Deployment Logs**
   - **Path:** Resource Group → Deployments
   - Find the deployment named `deploy-kv-{timestamp}`
   - ✅ Status: Succeeded
   - Review deployment details:
     - Key Vault created
     - Access policies assigned
     - App Service configured

3. **Verify Deployment Outputs**
   - Check deployment outputs for:
     - Key Vault name
     - Key Vault URI
     - App Service URLs

## Troubleshooting

### Issue: Key Vault References Show Red/Error Status

**Symptoms:**
- App Service configuration shows red icon next to Key Vault reference
- Application logs show "Key Vault secret not found" errors

**Solutions:**

1. **Verify Managed Identity Access**
   ```bash
   # Check if the App Service has a system-assigned managed identity
   az webapp identity show --name {app-name} --resource-group {rg-name}
   
   # Check Key Vault access policies
   az keyvault show --name {kv-name} --query properties.accessPolicies
   ```

2. **Grant Missing Permissions**
   ```bash
   # Get the App Service's managed identity principal ID
   PRINCIPAL_ID=$(az webapp identity show --name {app-name} --resource-group {rg-name} --query principalId -o tsv)
   
   # Grant Get and List permissions for secrets
   az keyvault set-policy --name {kv-name} \
     --object-id $PRINCIPAL_ID \
     --secret-permissions get list
   ```

3. **Restart App Service**
   ```bash
   az webapp restart --name {app-name} --resource-group {rg-name}
   ```

### Issue: Secrets Don't Exist in Key Vault

**Solution:**
Add the secrets manually:

```bash
# Add OpenPayAdapter ApiKey
az keyvault secret set --vault-name {kv-name} \
  --name "OpenPayAdapter--ApiKey" \
  --value "your-api-key-here"

# Add Application Insights Connection String
az keyvault secret set --vault-name {kv-name} \
  --name "ApplicationInsights--ConnectionString" \
  --value "InstrumentationKey=...;IngestionEndpoint=..."
```

### Issue: Application Not Reading Key Vault Values

**Symptoms:**
- Application uses default/empty values
- No Key Vault access errors in logs

**Solutions:**

1. Verify App Settings format:
   - Must use `@Microsoft.KeyVault(SecretUri=...)`
   - URI must be complete: `https://{vault}.vault.azure.net/secrets/{secret-name}/`

2. Check configuration key naming:
   - Key Vault: `OpenPayAdapter--ApiKey` (double dash)
   - App Settings: `OpenPayAdapter__ApiKey` (double underscore)
   - .NET reads it as: `OpenPayAdapter:ApiKey` (colon)

3. Verify application is restarted after configuration changes

## Automated Verification Scripts

### PowerShell Verification Script

Save this as `Verify-KeyVaultSetup.ps1`:

```powershell
<#
.SYNOPSIS
    Verifies Key Vault setup for Order Processing System
.DESCRIPTION
    Checks Key Vault configuration, access policies, secrets, and App Service integration
.PARAMETER ResourceGroupName
    Name of the Azure resource group
.PARAMETER Environment
    Environment name (dev, staging, prod)
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('dev','staging','prod')]
    [string]$Environment = 'dev'
)

Write-Host "🔍 Starting Key Vault Verification for Environment: $Environment" -ForegroundColor Cyan

# Variables
$keyVaultName = "kv-orderproc-$Environment"
$appServiceName = "*-orderprocessing-api-xyapp-$Environment"

# 1. Check if Key Vault exists
Write-Host "`n📦 Checking Key Vault existence..." -ForegroundColor Yellow
$keyVault = Get-AzKeyVault -ResourceGroupName $ResourceGroupName -VaultName $keyVaultName -ErrorAction SilentlyContinue

if ($keyVault) {
    Write-Host "✅ Key Vault '$keyVaultName' found" -ForegroundColor Green
    Write-Host "   Location: $($keyVault.Location)"
    Write-Host "   Vault URI: $($keyVault.VaultUri)"
} else {
    Write-Host "❌ Key Vault '$keyVaultName' not found" -ForegroundColor Red
    exit 1
}

# 2. Check Key Vault properties
Write-Host "`n🔧 Checking Key Vault configuration..." -ForegroundColor Yellow
$kvDetails = Get-AzKeyVault -ResourceGroupName $ResourceGroupName -VaultName $keyVaultName

Write-Host "   Soft Delete Enabled: $($kvDetails.EnableSoftDelete)" -ForegroundColor $(if($kvDetails.EnableSoftDelete) {"Green"} else {"Red"})
Write-Host "   Soft Delete Retention: $($kvDetails.SoftDeleteRetentionInDays) days"

# 3. Check secrets
Write-Host "`n🔑 Checking required secrets..." -ForegroundColor Yellow
$requiredSecrets = @(
    "OpenPayAdapter--ApiKey",
    "ApplicationInsights--ConnectionString"
)

foreach ($secretName in $requiredSecrets) {
    $secret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $secretName -ErrorAction SilentlyContinue
    if ($secret) {
        Write-Host "✅ Secret '$secretName' exists" -ForegroundColor Green
        Write-Host "   Created: $($secret.Created)"
        Write-Host "   Updated: $($secret.Updated)"
    } else {
        Write-Host "❌ Secret '$secretName' NOT FOUND" -ForegroundColor Red
    }
}

# 4. Check App Service
Write-Host "`n🌐 Checking App Service..." -ForegroundColor Yellow
$webApps = Get-AzWebApp -ResourceGroupName $ResourceGroupName | Where-Object { $_.Name -like $appServiceName }

if ($webApps.Count -eq 0) {
    Write-Host "⚠️  No App Service matching pattern '$appServiceName' found" -ForegroundColor Yellow
} else {
    foreach ($webapp in $webApps) {
        Write-Host "✅ Found App Service: $($webapp.Name)" -ForegroundColor Green
        
        # Check Managed Identity
        if ($webapp.Identity.Type -eq "SystemAssigned") {
            Write-Host "   ✅ System-Assigned Managed Identity enabled" -ForegroundColor Green
            Write-Host "   Principal ID: $($webapp.Identity.PrincipalId)"
            
            # Check Key Vault access policy
            $policies = (Get-AzKeyVault -ResourceGroupName $ResourceGroupName -VaultName $keyVaultName).AccessPolicies
            $hasAccess = $policies | Where-Object { $_.ObjectId -eq $webapp.Identity.PrincipalId }
            
            if ($hasAccess) {
                Write-Host "   ✅ Managed Identity has Key Vault access" -ForegroundColor Green
                Write-Host "   Secret Permissions: $($hasAccess.PermissionsToSecrets -join ', ')"
            } else {
                Write-Host "   ❌ Managed Identity does NOT have Key Vault access" -ForegroundColor Red
            }
        } else {
            Write-Host "   ❌ System-Assigned Managed Identity NOT enabled" -ForegroundColor Red
        }
        
        # Check App Settings for Key Vault references
        Write-Host "   Checking App Settings for Key Vault references..."
        $settings = $webapp.SiteConfig.AppSettings
        $kvRefs = $settings | Where-Object { $_.Value -like "*@Microsoft.KeyVault*" }
        
        if ($kvRefs.Count -gt 0) {
            Write-Host "   ✅ Found $($kvRefs.Count) Key Vault reference(s):" -ForegroundColor Green
            foreach ($ref in $kvRefs) {
                Write-Host "      - $($ref.Name)" -ForegroundColor Gray
            }
        } else {
            Write-Host "   ⚠️  No Key Vault references found in App Settings" -ForegroundColor Yellow
        }
    }
}

# 5. Summary
Write-Host "`n📊 Verification Summary" -ForegroundColor Cyan
Write-Host "================================"
Write-Host "Key Vault: $($keyVault ? '✅ Configured' : '❌ Missing')"
Write-Host "Secrets: Check output above for details"
Write-Host "App Service: Check output above for details"
Write-Host "================================"

Write-Host "`n✅ Verification complete!" -ForegroundColor Green
```

### Azure CLI Verification Script

Save this as `verify-keyvault-setup.sh`:

```bash
#!/bin/bash

# Verify Key Vault Setup Script
# Usage: ./verify-keyvault-setup.sh <resource-group> <environment>

set -e

RESOURCE_GROUP=$1
ENVIRONMENT=${2:-dev}
KV_NAME="kv-orderproc-$ENVIRONMENT"
APP_SERVICE_PATTERN="*-orderprocessing-api-xyapp-$ENVIRONMENT"

echo "🔍 Starting Key Vault Verification for Environment: $ENVIRONMENT"

# 1. Check Key Vault exists
echo -e "\n📦 Checking Key Vault existence..."
if az keyvault show --name "$KV_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    echo "✅ Key Vault '$KV_NAME' found"
    az keyvault show --name "$KV_NAME" --query "{Location:location,VaultUri:properties.vaultUri}" -o table
else
    echo "❌ Key Vault '$KV_NAME' not found"
    exit 1
fi

# 2. Check Key Vault properties
echo -e "\n🔧 Checking Key Vault configuration..."
SOFT_DELETE=$(az keyvault show --name "$KV_NAME" --query "properties.enableSoftDelete" -o tsv)
RETENTION=$(az keyvault show --name "$KV_NAME" --query "properties.softDeleteRetentionInDays" -o tsv)

echo "   Soft Delete Enabled: $SOFT_DELETE"
echo "   Soft Delete Retention: $RETENTION days"

# 3. Check secrets
echo -e "\n🔑 Checking required secrets..."
REQUIRED_SECRETS=("OpenPayAdapter--ApiKey" "ApplicationInsights--ConnectionString")

for SECRET in "${REQUIRED_SECRETS[@]}"; do
    if az keyvault secret show --vault-name "$KV_NAME" --name "$SECRET" &>/dev/null; then
        echo "✅ Secret '$SECRET' exists"
    else
        echo "❌ Secret '$SECRET' NOT FOUND"
    fi
done

# 4. Check App Service
echo -e "\n🌐 Checking App Service..."
WEBAPP_NAME=$(az webapp list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'orderprocessing-api-xyapp-$ENVIRONMENT')].name" -o tsv | head -1)

if [ -z "$WEBAPP_NAME" ]; then
    echo "⚠️  No App Service found matching pattern"
else
    echo "✅ Found App Service: $WEBAPP_NAME"
    
    # Check Managed Identity
    IDENTITY_TYPE=$(az webapp identity show --name "$WEBAPP_NAME" --resource-group "$RESOURCE_GROUP" --query "type" -o tsv)
    if [ "$IDENTITY_TYPE" == "SystemAssigned" ]; then
        echo "   ✅ System-Assigned Managed Identity enabled"
        PRINCIPAL_ID=$(az webapp identity show --name "$WEBAPP_NAME" --resource-group "$RESOURCE_GROUP" --query "principalId" -o tsv)
        echo "   Principal ID: $PRINCIPAL_ID"
        
        # Check Key Vault access
        ACCESS=$(az keyvault show --name "$KV_NAME" --query "properties.accessPolicies[?objectId=='$PRINCIPAL_ID'].permissions.secrets" -o tsv)
        if [ -n "$ACCESS" ]; then
            echo "   ✅ Managed Identity has Key Vault access"
            echo "   Permissions: $ACCESS"
        else
            echo "   ❌ Managed Identity does NOT have Key Vault access"
        fi
    else
        echo "   ❌ System-Assigned Managed Identity NOT enabled"
    fi
fi

echo -e "\n✅ Verification complete!"
```

### Usage Examples

**PowerShell:**
```powershell
# Make sure you're logged in to Azure
Connect-AzAccount

# Run verification
./Verify-KeyVaultSetup.ps1 -ResourceGroupName "rg-orderprocessing-dev" -Environment "dev"
```

**Azure CLI:**
```bash
# Make sure you're logged in to Azure
az login

# Make script executable
chmod +x verify-keyvault-setup.sh

# Run verification
./verify-keyvault-setup.sh rg-orderprocessing-dev dev
```

## Next Steps

After verification:

1. ✅ **Populate Secrets** (if not already done):
   - Add actual API keys and connection strings to Key Vault
   - Restart App Services to pick up the values

2. ✅ **Monitor Application**:
   - Check Application Insights for telemetry
   - Review logs for any configuration errors
   - Test application endpoints

3. ✅ **Production Deployment**:
   - Repeat verification for staging/production environments
   - Enable additional security features (network restrictions, private endpoints)
   - Set up monitoring and alerts

4. ✅ **Documentation**:
   - Update team documentation with environment-specific details
   - Document secret rotation procedures
   - Create runbooks for common operations

## Additional Resources

- [Azure Key Vault Documentation](https://docs.microsoft.com/azure/key-vault/)
- [Managed Identity Overview](https://docs.microsoft.com/azure/active-directory/managed-identities-azure-resources/overview)
- [App Service Key Vault References](https://docs.microsoft.com/azure/app-service/app-service-key-vault-references)
- PR#54: Fix Key Vault parent resource error
- PR#5: Remove manual GH_PAT requirement

## Support

If you encounter issues not covered in this guide:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review Azure Activity Logs for deployment errors
3. Check GitHub Actions logs for workflow issues
4. Contact the DevOps team
