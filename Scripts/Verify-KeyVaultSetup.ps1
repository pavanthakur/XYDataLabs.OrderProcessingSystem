<#
.SYNOPSIS
    Verifies Key Vault setup for Order Processing System
.DESCRIPTION
    Checks Key Vault configuration, access policies, secrets, and App Service integration
    This script validates the setup created by PR#54 (Key Vault) and PR#5 (GitHub Workflow)
.PARAMETER ResourceGroupName
    Name of the Azure resource group
.PARAMETER Environment
    Environment name (dev, staging, prod)
.PARAMETER KeyVaultName
    Optional: Override the default Key Vault naming convention
.EXAMPLE
    .\Verify-KeyVaultSetup.ps1 -ResourceGroupName "rg-orderprocessing-dev" -Environment "dev"
.NOTES
    Requires Azure PowerShell module (Az)
    Run 'Connect-AzAccount' before executing this script
#>

param(
    [Parameter(Mandatory=$true, HelpMessage="Azure resource group name")]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false, HelpMessage="Environment (dev, staging, prod)")]
    [ValidateSet('dev','staging','prod')]
    [string]$Environment = 'dev',
    
    [Parameter(Mandatory=$false, HelpMessage="Override Key Vault name")]
    [string]$KeyVaultName = ""
)

# Initialize
$ErrorActionPreference = 'Continue'
$VerificationResults = @{
    KeyVaultExists = $false
    SoftDeleteEnabled = $false
    RequiredSecretsFound = @()
    MissingSecrets = @()
    AppServicesFound = @()
    ManagedIdentityConfigured = @()
    KeyVaultAccessGranted = @()
    OverallStatus = "Unknown"
}

# Default Key Vault name if not provided
if ([string]::IsNullOrWhiteSpace($KeyVaultName)) {
    $KeyVaultName = "kv-orderproc-$Environment"
}

$appServicePattern = "*-orderprocessing-api-xyapp-$Environment"

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   Key Vault Verification - Order Processing System        ║" -ForegroundColor Cyan
Write-Host "║   Environment: $($Environment.PadRight(43)) ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Check if logged in to Azure
Write-Host "`n🔐 Checking Azure authentication..." -ForegroundColor Yellow
try {
    $context = Get-AzContext
    if ($null -eq $context) {
        Write-Host "❌ Not logged in to Azure. Please run 'Connect-AzAccount'" -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ Logged in as: $($context.Account.Id)" -ForegroundColor Green
    Write-Host "   Subscription: $($context.Subscription.Name)" -ForegroundColor Gray
} catch {
    Write-Host "❌ Error checking Azure authentication: $_" -ForegroundColor Red
    exit 1
}

# 1. Check if Key Vault exists
Write-Host "`n📦 Step 1: Checking Key Vault existence..." -ForegroundColor Yellow
Write-Host "   Looking for: $KeyVaultName" -ForegroundColor Gray

try {
    $keyVault = Get-AzKeyVault -ResourceGroupName $ResourceGroupName -VaultName $KeyVaultName -ErrorAction SilentlyContinue

    if ($keyVault) {
        Write-Host "✅ Key Vault '$KeyVaultName' found" -ForegroundColor Green
        Write-Host "   Location: $($keyVault.Location)" -ForegroundColor Gray
        Write-Host "   Vault URI: $($keyVault.VaultUri)" -ForegroundColor Gray
        Write-Host "   Resource Group: $($keyVault.ResourceGroupName)" -ForegroundColor Gray
        $VerificationResults.KeyVaultExists = $true
    } else {
        Write-Host "❌ Key Vault '$KeyVaultName' not found in resource group '$ResourceGroupName'" -ForegroundColor Red
        Write-Host "   Please verify:" -ForegroundColor Yellow
        Write-Host "   - Resource group name is correct" -ForegroundColor Yellow
        Write-Host "   - Key Vault was created by the deployment workflow" -ForegroundColor Yellow
        Write-Host "   - You have permissions to access the Key Vault" -ForegroundColor Yellow
        $VerificationResults.OverallStatus = "Failed"
        exit 1
    }
} catch {
    Write-Host "❌ Error checking Key Vault: $_" -ForegroundColor Red
    exit 1
}

# 2. Check Key Vault configuration properties
Write-Host "`n🔧 Step 2: Checking Key Vault configuration..." -ForegroundColor Yellow

try {
    $kvDetails = Get-AzKeyVault -ResourceGroupName $ResourceGroupName -VaultName $KeyVaultName

    # Check Soft Delete
    $softDeleteEnabled = $kvDetails.EnableSoftDelete
    Write-Host "   Soft Delete Enabled: $softDeleteEnabled" -ForegroundColor $(if($softDeleteEnabled) {"Green"} else {"Red"})
    $VerificationResults.SoftDeleteEnabled = $softDeleteEnabled
    
    if ($softDeleteEnabled) {
        Write-Host "   Soft Delete Retention: $($kvDetails.SoftDeleteRetentionInDays) days" -ForegroundColor Green
        if ($kvDetails.SoftDeleteRetentionInDays -eq 90) {
            Write-Host "   ✅ Matches PR#54 specification (90 days)" -ForegroundColor Green
        }
    } else {
        Write-Host "   ⚠️  Soft Delete should be enabled (PR#54 requirement)" -ForegroundColor Yellow
    }

    # Check Purge Protection
    $purgeProtection = $kvDetails.EnablePurgeProtection
    Write-Host "   Purge Protection: $purgeProtection" -ForegroundColor $(if($purgeProtection) {"Green"} else {"Gray"})
    
    # Check SKU
    Write-Host "   SKU: $($kvDetails.Sku)" -ForegroundColor Gray
    
    # Check Tags
    if ($kvDetails.Tags) {
        Write-Host "   Tags:" -ForegroundColor Gray
        $kvDetails.Tags.GetEnumerator() | ForEach-Object {
            Write-Host "      - $($_.Key): $($_.Value)" -ForegroundColor Gray
        }
    }
} catch {
    Write-Host "❌ Error checking Key Vault configuration: $_" -ForegroundColor Red
}

# 3. Check required secrets
Write-Host "`n🔑 Step 3: Checking required secrets..." -ForegroundColor Yellow

$requiredSecrets = @(
    "OpenPayAdapter--ApiKey",
    "ApplicationInsights--ConnectionString"
)

Write-Host "   Checking for $($requiredSecrets.Count) required secret(s)..." -ForegroundColor Gray

foreach ($secretName in $requiredSecrets) {
    try {
        $secret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $secretName -ErrorAction SilentlyContinue
        if ($secret) {
            Write-Host "   ✅ Secret '$secretName' exists" -ForegroundColor Green
            Write-Host "      Created: $($secret.Created)" -ForegroundColor Gray
            Write-Host "      Updated: $($secret.Updated)" -ForegroundColor Gray
            Write-Host "      Enabled: $($secret.Enabled)" -ForegroundColor Gray
            $VerificationResults.RequiredSecretsFound += $secretName
        } else {
            Write-Host "   ❌ Secret '$secretName' NOT FOUND" -ForegroundColor Red
            Write-Host "      Action required: Create this secret in Key Vault" -ForegroundColor Yellow
            $VerificationResults.MissingSecrets += $secretName
        }
    } catch {
        Write-Host "   ❌ Error checking secret '$secretName': $_" -ForegroundColor Red
        $VerificationResults.MissingSecrets += $secretName
    }
}

if ($VerificationResults.MissingSecrets.Count -gt 0) {
    Write-Host "`n   ⚠️  Missing Secrets - Manual Action Required:" -ForegroundColor Yellow
    Write-Host "   Run the following commands to add missing secrets:" -ForegroundColor Yellow
    foreach ($secretName in $VerificationResults.MissingSecrets) {
        Write-Host "   az keyvault secret set --vault-name $KeyVaultName --name `"$secretName`" --value `"<your-value>`"" -ForegroundColor Cyan
    }
}

# 4. Check App Services
Write-Host "`n🌐 Step 4: Checking App Service configuration..." -ForegroundColor Yellow
Write-Host "   Looking for App Services matching: $appServicePattern" -ForegroundColor Gray

try {
    $webApps = Get-AzWebApp -ResourceGroupName $ResourceGroupName | Where-Object { $_.Name -like $appServicePattern }

    if ($webApps.Count -eq 0) {
        Write-Host "   ⚠️  No App Service matching pattern '$appServicePattern' found" -ForegroundColor Yellow
        Write-Host "   This might be expected if the App Service hasn't been deployed yet" -ForegroundColor Gray
    } else {
        Write-Host "   Found $($webApps.Count) App Service(s)" -ForegroundColor Green
        
        foreach ($webapp in $webApps) {
            Write-Host "`n   📱 App Service: $($webapp.Name)" -ForegroundColor Cyan
            Write-Host "      URL: https://$($webapp.DefaultHostName)" -ForegroundColor Gray
            Write-Host "      State: $($webapp.State)" -ForegroundColor Gray
            
            $VerificationResults.AppServicesFound += $webapp.Name
            
            # Check Managed Identity
            if ($webapp.Identity.Type -eq "SystemAssigned") {
                Write-Host "      ✅ System-Assigned Managed Identity enabled" -ForegroundColor Green
                Write-Host "         Principal ID: $($webapp.Identity.PrincipalId)" -ForegroundColor Gray
                $VerificationResults.ManagedIdentityConfigured += $webapp.Name
                
                # Check Key Vault access policy
                $policies = (Get-AzKeyVault -ResourceGroupName $ResourceGroupName -VaultName $KeyVaultName).AccessPolicies
                $hasAccess = $policies | Where-Object { $_.ObjectId -eq $webapp.Identity.PrincipalId }
                
                if ($hasAccess) {
                    Write-Host "      ✅ Managed Identity has Key Vault access" -ForegroundColor Green
                    Write-Host "         Secret Permissions: $($hasAccess.PermissionsToSecrets -join ', ')" -ForegroundColor Gray
                    
                    # Verify Get and List permissions
                    $hasGet = $hasAccess.PermissionsToSecrets -contains "Get"
                    $hasList = $hasAccess.PermissionsToSecrets -contains "List"
                    
                    if ($hasGet -and $hasList) {
                        Write-Host "         ✅ Has required permissions (Get, List)" -ForegroundColor Green
                        $VerificationResults.KeyVaultAccessGranted += $webapp.Name
                    } else {
                        Write-Host "         ⚠️  Missing required permissions:" -ForegroundColor Yellow
                        if (-not $hasGet) { Write-Host "            - Get" -ForegroundColor Yellow }
                        if (-not $hasList) { Write-Host "            - List" -ForegroundColor Yellow }
                    }
                } else {
                    Write-Host "      ❌ Managed Identity does NOT have Key Vault access" -ForegroundColor Red
                    Write-Host "         Action required: Grant Key Vault access to this identity" -ForegroundColor Yellow
                    Write-Host "         Command:" -ForegroundColor Yellow
                    Write-Host "         az keyvault set-policy --name $KeyVaultName --object-id $($webapp.Identity.PrincipalId) --secret-permissions get list" -ForegroundColor Cyan
                }
            } else {
                Write-Host "      ❌ System-Assigned Managed Identity NOT enabled" -ForegroundColor Red
                Write-Host "         Action required: Enable managed identity on the App Service" -ForegroundColor Yellow
            }
            
            # Check App Settings for Key Vault references
            Write-Host "      Checking App Settings for Key Vault references..." -ForegroundColor Gray
            
            try {
                $config = Get-AzWebApp -Name $webapp.Name -ResourceGroupName $ResourceGroupName
                $settings = $config.SiteConfig.AppSettings
                $kvRefs = $settings | Where-Object { $_.Value -like "*@Microsoft.KeyVault*" }
                
                if ($kvRefs.Count -gt 0) {
                    Write-Host "      ✅ Found $($kvRefs.Count) Key Vault reference(s):" -ForegroundColor Green
                    foreach ($ref in $kvRefs) {
                        Write-Host "         - $($ref.Name)" -ForegroundColor Gray
                        Write-Host "           $($ref.Value.Substring(0, [Math]::Min(80, $ref.Value.Length)))..." -ForegroundColor DarkGray
                    }
                    
                    # Verify expected references
                    $hasApiKey = $kvRefs | Where-Object { $_.Name -like "*OpenPayAdapter*ApiKey*" }
                    $hasAppInsights = $kvRefs | Where-Object { $_.Name -eq "APPLICATIONINSIGHTS_CONNECTION_STRING" }
                    
                    if ($hasApiKey) {
                        Write-Host "         ✅ OpenPayAdapter ApiKey reference configured" -ForegroundColor Green
                    } else {
                        Write-Host "         ⚠️  OpenPayAdapter ApiKey reference not found" -ForegroundColor Yellow
                    }
                    
                    if ($hasAppInsights) {
                        Write-Host "         ✅ Application Insights connection string reference configured" -ForegroundColor Green
                    } else {
                        Write-Host "         ⚠️  Application Insights connection string reference not found" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "      ⚠️  No Key Vault references found in App Settings" -ForegroundColor Yellow
                    Write-Host "         Action required: Configure App Settings to reference Key Vault secrets" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "      ⚠️  Could not retrieve App Settings: $_" -ForegroundColor Yellow
            }
        }
    }
} catch {
    Write-Host "   ❌ Error checking App Services: $_" -ForegroundColor Red
}

# 5. Check Access Policies Summary
Write-Host "`n🔐 Step 5: Access Policies Summary..." -ForegroundColor Yellow

try {
    $allPolicies = (Get-AzKeyVault -ResourceGroupName $ResourceGroupName -VaultName $KeyVaultName).AccessPolicies
    Write-Host "   Total access policies configured: $($allPolicies.Count)" -ForegroundColor Gray
    
    if ($allPolicies.Count -gt 0) {
        Write-Host "   Access policies:" -ForegroundColor Gray
        foreach ($policy in $allPolicies) {
            $displayName = $policy.DisplayName
            if ([string]::IsNullOrWhiteSpace($displayName)) {
                $displayName = "Unknown (Object ID: $($policy.ObjectId))"
            }
            Write-Host "      - $displayName" -ForegroundColor Gray
            Write-Host "        Permissions: Secrets($($policy.PermissionsToSecrets -join ', '))" -ForegroundColor DarkGray
        }
    }
} catch {
    Write-Host "   ⚠️  Could not retrieve access policies: $_" -ForegroundColor Yellow
}

# 6. Summary Report
Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                  Verification Summary                     ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

$allChecksPass = $true

Write-Host "`nKey Vault Configuration:" -ForegroundColor White
Write-Host "  • Key Vault Exists: $(if($VerificationResults.KeyVaultExists){'✅ Yes'}else{'❌ No'})" -ForegroundColor $(if($VerificationResults.KeyVaultExists){"Green"}else{"Red"})
Write-Host "  • Soft Delete Enabled: $(if($VerificationResults.SoftDeleteEnabled){'✅ Yes'}else{'❌ No'})" -ForegroundColor $(if($VerificationResults.SoftDeleteEnabled){"Green"}else{"Red"})
if (-not $VerificationResults.SoftDeleteEnabled) { $allChecksPass = $false }

Write-Host "`nSecrets Status:" -ForegroundColor White
Write-Host "  • Found: $($VerificationResults.RequiredSecretsFound.Count)/$($requiredSecrets.Count)" -ForegroundColor $(if($VerificationResults.RequiredSecretsFound.Count -eq $requiredSecrets.Count){"Green"}else{"Yellow"})
if ($VerificationResults.MissingSecrets.Count -gt 0) {
    Write-Host "  • Missing: $($VerificationResults.MissingSecrets -join ', ')" -ForegroundColor Red
    $allChecksPass = $false
}

Write-Host "`nApp Service Integration:" -ForegroundColor White
Write-Host "  • App Services Found: $($VerificationResults.AppServicesFound.Count)" -ForegroundColor $(if($VerificationResults.AppServicesFound.Count -gt 0){"Green"}else{"Yellow"})
Write-Host "  • With Managed Identity: $($VerificationResults.ManagedIdentityConfigured.Count)" -ForegroundColor $(if($VerificationResults.ManagedIdentityConfigured.Count -gt 0){"Green"}else{"Yellow"})
Write-Host "  • With Key Vault Access: $($VerificationResults.KeyVaultAccessGranted.Count)" -ForegroundColor $(if($VerificationResults.KeyVaultAccessGranted.Count -gt 0){"Green"}else{"Yellow"})

if ($VerificationResults.AppServicesFound.Count -gt 0 -and $VerificationResults.KeyVaultAccessGranted.Count -eq 0) {
    $allChecksPass = $false
}

# Overall Status
if ($allChecksPass -and $VerificationResults.MissingSecrets.Count -eq 0) {
    $VerificationResults.OverallStatus = "Success"
    Write-Host "`n✅ Overall Status: SUCCESS" -ForegroundColor Green
    Write-Host "   All critical checks passed!" -ForegroundColor Green
} elseif ($VerificationResults.MissingSecrets.Count -gt 0) {
    $VerificationResults.OverallStatus = "Incomplete"
    Write-Host "`n⚠️  Overall Status: INCOMPLETE" -ForegroundColor Yellow
    Write-Host "   Key Vault is configured but missing required secrets" -ForegroundColor Yellow
    Write-Host "   Please populate the missing secrets to complete setup" -ForegroundColor Yellow
} else {
    $VerificationResults.OverallStatus = "Failed"
    Write-Host "`n❌ Overall Status: FAILED" -ForegroundColor Red
    Write-Host "   Some critical checks failed. Review the output above" -ForegroundColor Red
    Write-Host "   and take corrective actions as suggested" -ForegroundColor Red
}

# PR References
Write-Host "`n📚 Related Changes:" -ForegroundColor Cyan
Write-Host "  • PR#54: Key Vault creation and configuration" -ForegroundColor Gray
Write-Host "  • PR#5:  GitHub workflow automation (GITHUB_TOKEN)" -ForegroundColor Gray

Write-Host "`n📖 For detailed verification steps and troubleshooting:" -ForegroundColor Cyan
Write-Host "   See: Documentation/KEY-VAULT-VERIFICATION-GUIDE.md" -ForegroundColor Gray

Write-Host "`n" 

# Return verification results
return $VerificationResults
