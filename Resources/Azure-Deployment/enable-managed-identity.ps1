# enable-managed-identity.ps1
# Enable System-Assigned Managed Identity for App Services and grant Key Vault access
# This script addresses the issue where Managed Identity is not assigned or doesn't have Key Vault access

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment,
    
    [Parameter(Mandatory=$false)]
    [string]$BaseName = 'orderprocessing',
    
    [Parameter(Mandatory=$false)]
    [string]$GitHubOwner = 'pavanthakur'
)

$ErrorActionPreference = 'Stop'

# Retry function for Azure CLI commands with exponential backoff
function Invoke-AzCommandWithRetry {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Command,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxRetries = 3,
        
        [Parameter(Mandatory=$false)]
        [int]$InitialDelaySeconds = 2
    )
    
    $attempt = 0
    $delay = $InitialDelaySeconds
    
    while ($attempt -lt $MaxRetries) {
        $attempt++
        try {
            # Execute the command
            $result = Invoke-Expression $Command 2>&1
            $exitCode = $LASTEXITCODE
            
            # Check for connection reset error in the output
            $resultStr = $result | Out-String
            if ($resultStr -match "ConnectionResetError|Connection aborted|forcibly closed") {
                throw "Connection error detected in output"
            }
            
            # Return result with exit code
            return @{
                Success = ($exitCode -eq 0)
                Output = $result
                ExitCode = $exitCode
            }
        }
        catch {
            $errorMsg = $_.Exception.Message
            if ($errorMsg -match "ConnectionResetError|Connection aborted|forcibly closed" -and $attempt -lt $MaxRetries) {
                Write-Host "  ⚠️  Connection error on attempt $attempt/$MaxRetries, retrying in $delay seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds $delay
                $delay = $delay * 2  # Exponential backoff
            }
            else {
                # Re-throw if it's not a connection error or we've exhausted retries
                throw
            }
        }
    }
    
    # If we get here, all retries failed
    throw "Command failed after $MaxRetries attempts: $Command"
}

Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         ENABLE MANAGED IDENTITY & KEY VAULT ACCESS            ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Start Time (UTC): $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host ""

# Validate parameters
if ([string]::IsNullOrWhiteSpace($BaseName)) {
    Write-Error "BaseName parameter cannot be null or empty"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($GitHubOwner)) {
    Write-Error "GitHubOwner parameter cannot be null or empty"
    exit 1
}

# Resource names
$rgName = "rg-$BaseName-$Environment"
$apiAppName = "$GitHubOwner-$BaseName-api-xyapp-$Environment"
$uiAppName = "$GitHubOwner-$BaseName-ui-xyapp-$Environment"
# Shorten base name for Key Vault (max 24 chars total)
$shortBaseName = $BaseName.Substring(0, [Math]::Min(15, $BaseName.Length))
$kvName = "kv-$shortBaseName-$Environment"

Write-Host "📋 Configuration:" -ForegroundColor Yellow
Write-Host "  Environment: $Environment" -ForegroundColor Gray
Write-Host "  Resource Group: $rgName" -ForegroundColor Gray
Write-Host "  API App: $apiAppName" -ForegroundColor Gray
Write-Host "  UI App: $uiAppName" -ForegroundColor Gray
Write-Host "  Key Vault: $kvName" -ForegroundColor Gray
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host ""

$identitiesEnabled = 0
$accessPoliciesGranted = 0
$errors = 0

try {
    # Verify resource group exists
    Write-Host "🔍 Verifying resource group exists..." -ForegroundColor Cyan
    $rgCmd = "az group show --name $rgName"
    $rgResult = Invoke-AzCommandWithRetry -Command $rgCmd
    
    if (-not $rgResult.Success) {
        Write-Host "  ❌ Resource group not found: $rgName" -ForegroundColor Red
        Write-Error "Resource group '$rgName' does not exist. Please deploy infrastructure first."
    }
    Write-Host "  ✅ Resource group found: $rgName" -ForegroundColor Green
    Write-Host ""
    
    # Verify Key Vault exists
    Write-Host "🔍 Verifying Key Vault exists..." -ForegroundColor Cyan
    $kvCmd = "az keyvault show --name $kvName --resource-group $rgName"
    $kvResult = Invoke-AzCommandWithRetry -Command $kvCmd
    
    if (-not $kvResult.Success) {
        Write-Host "  ❌ Key Vault not found: $kvName" -ForegroundColor Red
        Write-Host ""
        Write-Host "Checking for Key Vaults in resource group..." -ForegroundColor Yellow
        $listKvCmd = "az keyvault list --resource-group $rgName --query '[].name' -o tsv"
        $listKvResult = Invoke-AzCommandWithRetry -Command $listKvCmd
        
        if ($listKvResult.Success -and $listKvResult.Output) {
            Write-Host "  Found Key Vaults:" -ForegroundColor Yellow
            $listKvResult.Output -split "`n" | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
            Write-Host "  Update the script parameter if Key Vault has a different name" -ForegroundColor Yellow
        }
        Write-Error "Key Vault '$kvName' does not exist in resource group '$rgName'"
    }
    Write-Host "  ✅ Key Vault found: $kvName" -ForegroundColor Green
    Write-Host ""
    
    # 1. Enable Managed Identity for API App
    Write-Host "🔑 [1/4] Enabling Managed Identity for API App..." -ForegroundColor Cyan
    try {
        # Check if App Service exists
        $checkCmd = "az webapp show -g $rgName -n $apiAppName --query 'name' -o tsv"
        $checkResult = Invoke-AzCommandWithRetry -Command $checkCmd
        
        if (-not $checkResult.Success -or [string]::IsNullOrWhiteSpace($checkResult.Output)) {
            Write-Host "  ⚠️  API App '$apiAppName' not found - skipping" -ForegroundColor Yellow
        } else {
            $apiExists = $checkResult.Output
            # Check if identity already exists
            $identityCmd = "az webapp identity show -g $rgName -n $apiAppName --query principalId -o tsv"
            $identityResult = Invoke-AzCommandWithRetry -Command $identityCmd
            
            if ($identityResult.Success -and -not [string]::IsNullOrWhiteSpace($identityResult.Output)) {
                $apiIdentity = $identityResult.Output.Trim()
                Write-Host "  ℹ️  Managed Identity already exists: $apiIdentity" -ForegroundColor Gray
            } else {
                # Enable system-assigned identity
                $assignCmd = "az webapp identity assign -g $rgName -n $apiAppName --query principalId -o tsv"
                $assignResult = Invoke-AzCommandWithRetry -Command $assignCmd
                
                if ($assignResult.Success) {
                    $apiIdentity = $assignResult.Output.Trim()
                    Write-Host "  ✅ Managed Identity enabled: $apiIdentity" -ForegroundColor Green
                    $identitiesEnabled++
                } else {
                    Write-Host "  ❌ Failed to enable Managed Identity" -ForegroundColor Red
                    Write-Host "  Error: $($assignResult.Output)" -ForegroundColor Red
                    $errors++
                }
            }
        }
    } catch {
        Write-Host "  ❌ Exception enabling API Managed Identity: $($_.Exception.Message)" -ForegroundColor Red
        $errors++
    }
    Write-Host ""
    
    # 2. Enable Managed Identity for UI App
    Write-Host "🔑 [2/4] Enabling Managed Identity for UI App..." -ForegroundColor Cyan
    try {
        # Check if App Service exists
        $checkCmd = "az webapp show -g $rgName -n $uiAppName --query 'name' -o tsv"
        $checkResult = Invoke-AzCommandWithRetry -Command $checkCmd
        
        if (-not $checkResult.Success -or [string]::IsNullOrWhiteSpace($checkResult.Output)) {
            Write-Host "  ⚠️  UI App '$uiAppName' not found - skipping" -ForegroundColor Yellow
        } else {
            $uiExists = $checkResult.Output
            # Check if identity already exists
            $identityCmd = "az webapp identity show -g $rgName -n $uiAppName --query principalId -o tsv"
            $identityResult = Invoke-AzCommandWithRetry -Command $identityCmd
            
            if ($identityResult.Success -and -not [string]::IsNullOrWhiteSpace($identityResult.Output)) {
                $uiIdentity = $identityResult.Output.Trim()
                Write-Host "  ℹ️  Managed Identity already exists: $uiIdentity" -ForegroundColor Gray
            } else {
                # Enable system-assigned identity
                $assignCmd = "az webapp identity assign -g $rgName -n $uiAppName --query principalId -o tsv"
                $assignResult = Invoke-AzCommandWithRetry -Command $assignCmd
                
                if ($assignResult.Success) {
                    $uiIdentity = $assignResult.Output.Trim()
                    Write-Host "  ✅ Managed Identity enabled: $uiIdentity" -ForegroundColor Green
                    $identitiesEnabled++
                } else {
                    Write-Host "  ❌ Failed to enable Managed Identity" -ForegroundColor Red
                    Write-Host "  Error: $($assignResult.Output)" -ForegroundColor Red
                    $errors++
                }
            }
        }
    } catch {
        Write-Host "  ❌ Exception enabling UI Managed Identity: $($_.Exception.Message)" -ForegroundColor Red
        $errors++
    }
    Write-Host ""
    
    # 3. Grant API App access to Key Vault
    Write-Host "🔐 [3/4] Granting API App access to Key Vault..." -ForegroundColor Cyan
    if (-not [string]::IsNullOrWhiteSpace($apiIdentity)) {
        try {
            # Check if access policy already exists
            $policyCmd = "az keyvault show -n $kvName -g $rgName --query ""properties.accessPolicies[?objectId=='$apiIdentity']"" -o json"
            $policyResult = Invoke-AzCommandWithRetry -Command $policyCmd
            
            if ($policyResult.Success) {
                $existingPolicy = $policyResult.Output | ConvertFrom-Json
                
                if ($existingPolicy -and $existingPolicy.Count -gt 0) {
                    Write-Host "  ℹ️  Access policy already exists for API App" -ForegroundColor Gray
                    # Check permissions
                    $hasGetSecret = $existingPolicy[0].permissions.secrets -contains 'get'
                    $hasListSecret = $existingPolicy[0].permissions.secrets -contains 'list'
                    if ($hasGetSecret -and $hasListSecret) {
                        Write-Host "  ✅ API App has required permissions (get, list)" -ForegroundColor Green
                    } else {
                        Write-Host "  ⚠️  API App missing some permissions, updating..." -ForegroundColor Yellow
                        $setPolicyCmd = "az keyvault set-policy -n $kvName --object-id $apiIdentity --secret-permissions get list"
                        $setPolicyResult = Invoke-AzCommandWithRetry -Command $setPolicyCmd
                        
                        if ($setPolicyResult.Success) {
                            Write-Host "  ✅ Access policy updated" -ForegroundColor Green
                            $accessPoliciesGranted++
                        } else {
                            Write-Host "  ❌ Failed to update access policy" -ForegroundColor Red
                            Write-Host "  Error: $($setPolicyResult.Output)" -ForegroundColor Red
                            $errors++
                        }
                    }
                } else {
                    # Grant access
                    $setPolicyCmd = "az keyvault set-policy -n $kvName --object-id $apiIdentity --secret-permissions get list"
                    $setPolicyResult = Invoke-AzCommandWithRetry -Command $setPolicyCmd
                    
                    if ($setPolicyResult.Success) {
                        Write-Host "  ✅ Access policy granted to API App" -ForegroundColor Green
                        $accessPoliciesGranted++
                    } else {
                        Write-Host "  ❌ Failed to grant access policy" -ForegroundColor Red
                        Write-Host "  Error: $($setPolicyResult.Output)" -ForegroundColor Red
                        $errors++
                    }
                }
            }
        } catch {
            Write-Host "  ❌ Exception granting API access: $($_.Exception.Message)" -ForegroundColor Red
            $errors++
        }
    } else {
        Write-Host "  ⚠️  API App Managed Identity not available - skipping" -ForegroundColor Yellow
    }
    Write-Host ""
    
    # 4. Grant UI App access to Key Vault
    Write-Host "🔐 [4/4] Granting UI App access to Key Vault..." -ForegroundColor Cyan
    if (-not [string]::IsNullOrWhiteSpace($uiIdentity)) {
        try {
            # Check if access policy already exists
            $policyCmd = "az keyvault show -n $kvName -g $rgName --query ""properties.accessPolicies[?objectId=='$uiIdentity']"" -o json"
            $policyResult = Invoke-AzCommandWithRetry -Command $policyCmd
            
            if ($policyResult.Success) {
                $existingPolicy = $policyResult.Output | ConvertFrom-Json
                
                if ($existingPolicy -and $existingPolicy.Count -gt 0) {
                    Write-Host "  ℹ️  Access policy already exists for UI App" -ForegroundColor Gray
                    # Check permissions
                    $hasGetSecret = $existingPolicy[0].permissions.secrets -contains 'get'
                    $hasListSecret = $existingPolicy[0].permissions.secrets -contains 'list'
                    if ($hasGetSecret -and $hasListSecret) {
                        Write-Host "  ✅ UI App has required permissions (get, list)" -ForegroundColor Green
                    } else {
                        Write-Host "  ⚠️  UI App missing some permissions, updating..." -ForegroundColor Yellow
                        $setPolicyCmd = "az keyvault set-policy -n $kvName --object-id $uiIdentity --secret-permissions get list"
                        $setPolicyResult = Invoke-AzCommandWithRetry -Command $setPolicyCmd
                        
                        if ($setPolicyResult.Success) {
                            Write-Host "  ✅ Access policy updated" -ForegroundColor Green
                            $accessPoliciesGranted++
                        } else {
                            Write-Host "  ❌ Failed to update access policy" -ForegroundColor Red
                            Write-Host "  Error: $($setPolicyResult.Output)" -ForegroundColor Red
                            $errors++
                        }
                    }
                } else {
                    # Grant access
                    $setPolicyCmd = "az keyvault set-policy -n $kvName --object-id $uiIdentity --secret-permissions get list"
                    $setPolicyResult = Invoke-AzCommandWithRetry -Command $setPolicyCmd
                    
                    if ($setPolicyResult.Success) {
                        Write-Host "  ✅ Access policy granted to UI App" -ForegroundColor Green
                        $accessPoliciesGranted++
                    } else {
                        Write-Host "  ❌ Failed to grant access policy" -ForegroundColor Red
                        Write-Host "  Error: $($setPolicyResult.Output)" -ForegroundColor Red
                        $errors++
                    }
                }
            }
        } catch {
            Write-Host "  ❌ Exception granting UI access: $($_.Exception.Message)" -ForegroundColor Red
            $errors++
        }
    } else {
        Write-Host "  ⚠️  UI App Managed Identity not available - skipping" -ForegroundColor Yellow
    }
    Write-Host ""
    
    # Set KEY_VAULT_NAME environment variable on App Services
    Write-Host "⚙️  Setting KEY_VAULT_NAME environment variable..." -ForegroundColor Cyan
    
    if (-not [string]::IsNullOrWhiteSpace($apiExists)) {
        try {
            $setEnvCmd = "az webapp config appsettings set -g $rgName -n $apiAppName --settings KEY_VAULT_NAME=$kvName -o none"
            $setEnvResult = Invoke-AzCommandWithRetry -Command $setEnvCmd
            
            if ($setEnvResult.Success) {
                Write-Host "  ✅ KEY_VAULT_NAME set on API App" -ForegroundColor Green
            } else {
                Write-Host "  ⚠️  Failed to set KEY_VAULT_NAME on API App" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  ⚠️  Exception setting KEY_VAULT_NAME on API App: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    
    if (-not [string]::IsNullOrWhiteSpace($uiExists)) {
        try {
            $setEnvCmd = "az webapp config appsettings set -g $rgName -n $uiAppName --settings KEY_VAULT_NAME=$kvName -o none"
            $setEnvResult = Invoke-AzCommandWithRetry -Command $setEnvCmd
            
            if ($setEnvResult.Success) {
                Write-Host "  ✅ KEY_VAULT_NAME set on UI App" -ForegroundColor Green
            } else {
                Write-Host "  ⚠️  Failed to set KEY_VAULT_NAME on UI App" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  ⚠️  Exception setting KEY_VAULT_NAME on UI App: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    Write-Host ""
    
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
    Write-Host "📊 Summary:" -ForegroundColor Cyan
    if ($identitiesEnabled -gt 0) {
        Write-Host "  ✅ Managed Identities Enabled: $identitiesEnabled" -ForegroundColor Green
    }
    if ($accessPoliciesGranted -gt 0) {
        Write-Host "  ✅ Access Policies Granted: $accessPoliciesGranted" -ForegroundColor Green
    }
    if ($errors -gt 0) {
        Write-Host "  ❌ Errors Encountered: $errors" -ForegroundColor Red
    }
    Write-Host ""
    
    # Verification
    Write-Host "🔍 Verification..." -ForegroundColor Cyan
    Write-Host "  API App Identity:" -ForegroundColor Yellow
    if (-not [string]::IsNullOrWhiteSpace($apiIdentity)) {
        Write-Host "    Principal ID: $apiIdentity" -ForegroundColor Gray
    } else {
        Write-Host "    Not configured" -ForegroundColor Gray
    }
    
    Write-Host "  UI App Identity:" -ForegroundColor Yellow
    if (-not [string]::IsNullOrWhiteSpace($uiIdentity)) {
        Write-Host "    Principal ID: $uiIdentity" -ForegroundColor Gray
    } else {
        Write-Host "    Not configured" -ForegroundColor Gray
    }
    Write-Host ""
    
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host "✅ MANAGED IDENTITY CONFIGURATION COMPLETE" -ForegroundColor Green
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host ""
    Write-Host "End Time (UTC): $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host ""
    
    if ($errors -gt 0) {
        Write-Host "⚠️  Some operations failed. Review errors above." -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }
    
    Write-Host "📝 Next Steps:" -ForegroundColor Cyan
    Write-Host "  1. Populate Key Vault with secrets (if not already done):" -ForegroundColor Gray
    Write-Host "     ./Resources/Azure-Deployment/populate-keyvault-secrets.ps1 -Environment $Environment" -ForegroundColor DarkGray
    Write-Host "  2. Restart App Services to pick up new configuration:" -ForegroundColor Gray
    Write-Host "     az webapp restart -g $rgName -n $apiAppName" -ForegroundColor DarkGray
    Write-Host "     az webapp restart -g $rgName -n $uiAppName" -ForegroundColor DarkGray
    Write-Host "  3. Verify setup:" -ForegroundColor Gray
    Write-Host "     ./Resources/Azure-Deployment/verify-azure-setup.ps1" -ForegroundColor DarkGray
    Write-Host ""
    
} catch {
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Red
    Write-Host "❌ EXCEPTION DURING MANAGED IDENTITY CONFIGURATION" -ForegroundColor Red
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Red
    Write-Host ""
    Write-Host "Exception Message: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Stack Trace:" -ForegroundColor Yellow
    Write-Host "$($_.ScriptStackTrace)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Timestamp (UTC): $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host ""
    Write-Error "Managed Identity configuration failed: $($_.Exception.Message)"
    exit 1
}
