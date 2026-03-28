# populate-keyvault-secrets.ps1
# Populate Azure Key Vault with application secrets
# This script adds all required secrets to Key Vault after infrastructure provisioning

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment,
    
    [Parameter(Mandatory=$false)]
    [string]$BaseName = 'orderprocessing',
    
    [Parameter(Mandatory=$false)]
    [string]$GitHubOwner = 'pavanthakur',
    
    [Parameter(Mandatory=$false)]
    [string]$OpenPayMerchantId,

    [Parameter(Mandatory=$false)]
    [string]$OpenPayPrivateKey,

    [Parameter(Mandatory=$false)]
    [string]$OpenPayDeviceSessionId,

    [Parameter(Mandatory=$false)]
    [bool]$OpenPayIsProduction = $false,

    [Parameter(Mandatory=$false)]
    [string]$OpenPayRedirectUrl,

    [Parameter(Mandatory=$false)]
    [string]$ApiHttpsCertPassword,

    [Parameter(Mandatory=$false)]
    [string]$UiHttpsCertPassword,

    [Parameter(Mandatory=$false)]
    [string]$OpenPayApiKey,
    
    [Parameter(Mandatory=$false)]
    [string]$ApplicationInsightsConnectionString,

    # Multitenant — Dedicated tenant connection strings (ADR-009: never stored in DB, must be in Key Vault)
    # Key Vault secret name: DedicatedTenantConnectionStrings--TenantC
    # Format: "Server=tcp:<server>.database.windows.net,1433;Initial Catalog=<db>;Encrypt=True;Authentication=Active Directory Default"
    # Required for DbInitializer.SeedDedicatedTenants() to migrate and seed TenantC dedicated DB at app startup.
    # Without this secret, TenantC requests return HTTP 400 (fail-loud, per ADR-009).
    [Parameter(Mandatory=$false)]
    [string]$DedicatedTenantConnectionStringTenantC
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
            # Execute the command — capture both stdout and stderr
            $result = Invoke-Expression $Command 2>&1
            $exitCode = $LASTEXITCODE
            
            # Flatten the result (may contain ErrorRecord objects from 2>&1) to a plain string
            $resultStr = ($result | ForEach-Object { "$_" }) -join "`n"
            
            if ($resultStr -match "ConnectionResetError|Connection aborted|forcibly closed") {
                throw "Connection error detected in output"
            }
            
            # Return result with exit code and a pre-flattened string for easy display
            return @{
                Success = ($exitCode -eq 0)
                Output = $resultStr
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

function Set-KeyVaultSecretValue {
    param(
        [Parameter(Mandatory=$true)]
        [string]$VaultName,

        [Parameter(Mandatory=$true)]
        [string]$SecretName,

        [Parameter(Mandatory=$true)]
        [string]$SecretValue
    )

    $secretCmd = "az keyvault secret set --vault-name $VaultName --name '$SecretName' --value '$SecretValue' --output json"
    return Invoke-AzCommandWithRetry -Command $secretCmd
}

Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         POPULATE KEY VAULT SECRETS                            ║" -ForegroundColor Cyan
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

# Map environment name to Azure resource suffix (staging uses abbreviated 'stg' to match bootstrap)
$envSuffix = switch ($Environment) { 'staging' { 'stg' } default { $Environment } }

# Resource names
$rgName = "rg-$BaseName-$envSuffix"
# Shorten base name for Key Vault (max 24 chars total)
$shortBaseName = $BaseName.Substring(0, [Math]::Min(15, $BaseName.Length))
$kvName = "kv-$shortBaseName-$envSuffix"
$aiName = "ai-$BaseName-$envSuffix"

Write-Host "📋 Configuration:" -ForegroundColor Yellow
Write-Host "  Environment: $Environment" -ForegroundColor Gray
Write-Host "  Base Name: $BaseName (length: $($BaseName.Length))" -ForegroundColor Gray
Write-Host "  Short Base Name: $shortBaseName (length: $($shortBaseName.Length))" -ForegroundColor Gray
Write-Host "  Resource Group: $rgName" -ForegroundColor Gray
Write-Host "  Key Vault: $kvName (length: $($kvName.Length))" -ForegroundColor Gray
Write-Host "  App Insights: $aiName" -ForegroundColor Gray
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host ""

$secretsAdded = 0
$secretsFailed = 0

try {
    # Verify Key Vault exists
    Write-Host "🔍 Verifying Key Vault exists..." -ForegroundColor Cyan
    $kvCmd = "az keyvault show --name $kvName --resource-group $rgName"
    $kvResult = Invoke-AzCommandWithRetry -Command $kvCmd
    
    if (-not $kvResult.Success) {
        Write-Host "  ❌ Key Vault not found: $kvName" -ForegroundColor Red
        Write-Host "  Error details: $($kvResult.Output)" -ForegroundColor Red
        Write-Host ""
        Write-Host "Checking if Key Vault exists with different name..." -ForegroundColor Yellow
        $listKvCmd = "az keyvault list --resource-group $rgName --query '[].name' -o tsv"
        $listKvResult = Invoke-AzCommandWithRetry -Command $listKvCmd
        
        if ($listKvResult.Success -and $listKvResult.Output) {
            Write-Host "  Found Key Vaults in $rgName`:" -ForegroundColor Yellow
            $listKvResult.Output -split "`n" | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
        } else {
            Write-Host "  No Key Vaults found in resource group $rgName" -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Error "Key Vault '$kvName' does not exist in resource group '$rgName'"
    }
    
    # Parse the JSON to get Key Vault properties
    try {
        $kvObj = $kvResult.Output | ConvertFrom-Json
        Write-Host "  ✅ Key Vault found: $kvName" -ForegroundColor Green
        Write-Host "     Location: $($kvObj.location)" -ForegroundColor Gray
        Write-Host "     Provisioning State: $($kvObj.properties.provisioningState)" -ForegroundColor Gray
        Write-Host "     RBAC Authorization: $($kvObj.properties.enableRbacAuthorization)" -ForegroundColor Gray
        Write-Host "     Vault URI: $($kvObj.properties.vaultUri)" -ForegroundColor Gray
    } catch {
        Write-Host "  ✅ Key Vault found (unable to parse details)" -ForegroundColor Green
    }
    Write-Host ""
    
    # 1. Add OpenPay and HTTPS certificate secrets
    Write-Host "🔑 [1/3] Adding OpenPay and HTTPS certificate secrets..." -ForegroundColor Cyan

    if ([string]::IsNullOrWhiteSpace($OpenPayPrivateKey) -and -not [string]::IsNullOrWhiteSpace($OpenPayApiKey)) {
        Write-Host "  ⚠️  OpenPayApiKey is deprecated. Using it as OpenPayPrivateKey for backward compatibility." -ForegroundColor Yellow
        $OpenPayPrivateKey = $OpenPayApiKey
    }

    if ([string]::IsNullOrWhiteSpace($OpenPayMerchantId)) {
        $OpenPayMerchantId = "set-openpay-merchant-id-$Environment"
        Write-Host "  ⚠️  OpenPayMerchantId not provided. Placeholder secret will be created." -ForegroundColor Yellow
    }

    if ([string]::IsNullOrWhiteSpace($OpenPayPrivateKey)) {
        $OpenPayPrivateKey = "set-openpay-private-key-$Environment"
        Write-Host "  ⚠️  OpenPayPrivateKey not provided. Placeholder secret will be created." -ForegroundColor Yellow
    }

    if ([string]::IsNullOrWhiteSpace($OpenPayDeviceSessionId)) {
        $OpenPayDeviceSessionId = "set-openpay-device-session-id-$Environment"
        Write-Host "  ⚠️  OpenPayDeviceSessionId not provided. Placeholder secret will be created." -ForegroundColor Yellow
    }

    if ([string]::IsNullOrWhiteSpace($OpenPayRedirectUrl)) {
        $OpenPayRedirectUrl = switch ($Environment) {
            'dev' { 'https://your-domain.com/payment/callback' }
            'staging' { 'https://stg-domain.com/payment/callback' }
            'prod' { 'https://production-domain.com/payment/callback' }
        }
        Write-Host "  ⚠️  OpenPayRedirectUrl not provided. Using environment default: $OpenPayRedirectUrl" -ForegroundColor Yellow
    }

    if ([string]::IsNullOrWhiteSpace($ApiHttpsCertPassword)) {
        $ApiHttpsCertPassword = "set-api-https-cert-password-$Environment"
        Write-Host "  ⚠️  ApiHttpsCertPassword not provided. Placeholder secret will be created." -ForegroundColor Yellow
    }

    if ([string]::IsNullOrWhiteSpace($UiHttpsCertPassword)) {
        $UiHttpsCertPassword = "set-ui-https-cert-password-$Environment"
        Write-Host "  ⚠️  UiHttpsCertPassword not provided. Placeholder secret will be created." -ForegroundColor Yellow
    }

    $secretMap = [ordered]@{
        'OpenPay--MerchantId' = $OpenPayMerchantId
        'OpenPay--PrivateKey' = $OpenPayPrivateKey
        'OpenPay--DeviceSessionId' = $OpenPayDeviceSessionId
        'OpenPay--IsProduction' = $OpenPayIsProduction.ToString().ToLowerInvariant()
        'OpenPay--RedirectUrl' = $OpenPayRedirectUrl
        'ApiSettings--API--https--CertPassword' = $ApiHttpsCertPassword
        'ApiSettings--UI--https--CertPassword' = $UiHttpsCertPassword
    }

    foreach ($secretEntry in $secretMap.GetEnumerator()) {
        try {
            $secretResult = Set-KeyVaultSecretValue -VaultName $kvName -SecretName $secretEntry.Key -SecretValue $secretEntry.Value

            if ($secretResult.Success) {
                Write-Host "  ✅ $($secretEntry.Key) added successfully" -ForegroundColor Green
                $secretsAdded++
            } else {
                Write-Host "  ❌ Failed to add $($secretEntry.Key)" -ForegroundColor Red
                Write-Host "  Error details: $($secretResult.Output)" -ForegroundColor Red
                $secretsFailed++
            }
        } catch {
            Write-Host "  ❌ Exception adding $($secretEntry.Key): $($_.Exception.Message)" -ForegroundColor Red
            $secretsFailed++
        }
    }
    
    Write-Host ""
    
    # 2. Add Dedicated Tenant Connection Strings (multitenant architecture — ADR-009)
    Write-Host "🔑 [2/4] Adding Dedicated Tenant connection strings..." -ForegroundColor Cyan
    Write-Host "  ℹ️  Required for DbInitializer.SeedDedicatedTenants() to migrate/seed TenantC dedicated DB at startup." -ForegroundColor Gray
    Write-Host "  ℹ️  Without this, TenantC requests return HTTP 400 (fail-loud per ADR-009)." -ForegroundColor Gray

    if ([string]::IsNullOrWhiteSpace($DedicatedTenantConnectionStringTenantC)) {
        $envSufTitle = (Get-Culture).TextInfo.ToTitleCase($Environment)
        $envSufDb    = switch ($Environment) { 'staging' { 'Stg' } default { $envSufTitle } }
        $DedicatedTenantConnectionStringTenantC = "Server=tcp:$BaseName-sql-$envSuffix.database.windows.net,1433;Initial Catalog=OrderProcessingSystem_TenantC_$envSufDb;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;Authentication=Active Directory Default"
        Write-Host "  ⚠️  DedicatedTenantConnectionStringTenantC not provided. Managed Identity placeholder will be created." -ForegroundColor Yellow
        Write-Host "      Value: $DedicatedTenantConnectionStringTenantC" -ForegroundColor Gray
        Write-Host "      Update this secret in Key Vault once the TenantC dedicated database is provisioned." -ForegroundColor Yellow
    }

    try {
        $tcResult = Set-KeyVaultSecretValue -VaultName $kvName -SecretName 'DedicatedTenantConnectionStrings--TenantC' -SecretValue $DedicatedTenantConnectionStringTenantC
        if ($tcResult.Success) {
            Write-Host "  ✅ DedicatedTenantConnectionStrings--TenantC added successfully" -ForegroundColor Green
            $secretsAdded++
        } else {
            Write-Host "  ❌ Failed to add DedicatedTenantConnectionStrings--TenantC" -ForegroundColor Red
            Write-Host "  Error details: $($tcResult.Output)" -ForegroundColor Red
            $secretsFailed++
        }
    } catch {
        Write-Host "  ❌ Exception adding DedicatedTenantConnectionStrings--TenantC: $($_.Exception.Message)" -ForegroundColor Red
        $secretsFailed++
    }

    Write-Host ""
    
    # 3. Add Application Insights Connection String
    Write-Host "🔑 [3/4] Adding Application Insights Connection String..." -ForegroundColor Cyan
    
    if ([string]::IsNullOrWhiteSpace($ApplicationInsightsConnectionString)) {
        # Retrieve from Application Insights resource
        Write-Host "  🔍 Retrieving connection string from Application Insights..." -ForegroundColor Gray
        
        try {
            $aiCmd = "az monitor app-insights component show --app $aiName --resource-group $rgName --query connectionString -o tsv"
            $aiResult = Invoke-AzCommandWithRetry -Command $aiCmd
            
            if ($aiResult.Success -and -not [string]::IsNullOrWhiteSpace($aiResult.Output)) {
                $ApplicationInsightsConnectionString = $aiResult.Output.Trim()
                Write-Host "  ✅ Retrieved connection string from App Insights" -ForegroundColor Green
            } else {
                Write-Host "  ⚠️  Could not retrieve App Insights connection string" -ForegroundColor Yellow
                Write-Host "  ℹ️  Skipping Application Insights connection string" -ForegroundColor Gray
                $ApplicationInsightsConnectionString = $null
            }
        } catch {
            Write-Host "  ⚠️  Exception retrieving App Insights: $($_.Exception.Message)" -ForegroundColor Yellow
            $ApplicationInsightsConnectionString = $null
        }
    }
    
    if (-not [string]::IsNullOrWhiteSpace($ApplicationInsightsConnectionString)) {
        try {
            $secretCmd = "az keyvault secret set --vault-name $kvName --name 'ApplicationInsights--ConnectionString' --value '$ApplicationInsightsConnectionString' --output json"
            $secretResult = Invoke-AzCommandWithRetry -Command $secretCmd
            
            if ($secretResult.Success) {
                Write-Host "  ✅ ApplicationInsights--ConnectionString added successfully" -ForegroundColor Green
                $secretsAdded++
            } else {
                Write-Host "  ❌ Failed to add ApplicationInsights--ConnectionString" -ForegroundColor Red
                Write-Host "  Error details: $($secretResult.Output)" -ForegroundColor Red
                $secretsFailed++
            }
        } catch {
            Write-Host "  ❌ Exception adding ApplicationInsights--ConnectionString: $($_.Exception.Message)" -ForegroundColor Red
            $secretsFailed++
        }
    }
    
    Write-Host ""
    Write-Host "🔑 [4/4] Key Vault secret population complete." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
    Write-Host "📊 Secret Population Summary:" -ForegroundColor Cyan
    Write-Host "  ✅ Secrets Added: $secretsAdded" -ForegroundColor Green
    if ($secretsFailed -gt 0) {
        Write-Host "  ❌ Secrets Failed: $secretsFailed" -ForegroundColor Red
    }
    Write-Host ""
    
    # Verify secrets were added
    Write-Host "🔍 Verifying secrets in Key Vault..." -ForegroundColor Cyan
    $listSecretsCmd = "az keyvault secret list --vault-name $kvName --query '[].name' -o tsv"
    $listSecretsResult = Invoke-AzCommandWithRetry -Command $listSecretsCmd
    
    if ($listSecretsResult.Success -and $listSecretsResult.Output) {
        $secretList = $listSecretsResult.Output -split "`n" | Where-Object { $_ }
        Write-Host "  Secrets in Key Vault ($($secretList.Count)):" -ForegroundColor Yellow
        foreach ($secret in $secretList) {
            Write-Host "    - $secret" -ForegroundColor Gray
        }
    } else {
        Write-Host "  ⚠️  No secrets found in Key Vault (may indicate verification issue)" -ForegroundColor Yellow
    }
    
    Write-Host ""
    
    # Set KEY_VAULT_NAME environment variable on App Services
    Write-Host "⚙️  Setting KEY_VAULT_NAME environment variable on App Services..." -ForegroundColor Cyan
    $apiAppName = "$GitHubOwner-$BaseName-api-xyapp-$envSuffix"
    $uiAppName = "$GitHubOwner-$BaseName-ui-xyapp-$envSuffix"
    
    # Set on API App
    try {
        $checkApiCmd = "az webapp show -g $rgName -n $apiAppName --query 'name' -o tsv"
        $checkApiResult = Invoke-AzCommandWithRetry -Command $checkApiCmd
        
        if ($checkApiResult.Success -and -not [string]::IsNullOrWhiteSpace($checkApiResult.Output)) {
            $setApiEnvCmd = "az webapp config appsettings set -g $rgName -n $apiAppName --settings KEY_VAULT_NAME=$kvName -o none"
            $setApiEnvResult = Invoke-AzCommandWithRetry -Command $setApiEnvCmd
            
            if ($setApiEnvResult.Success) {
                Write-Host "  ✅ KEY_VAULT_NAME set on API App" -ForegroundColor Green
            } else {
                Write-Host "  ⚠️  Failed to set KEY_VAULT_NAME on API App" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "  ⚠️  Exception setting KEY_VAULT_NAME on API App: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    # Set on UI App
    try {
        $checkUiCmd = "az webapp show -g $rgName -n $uiAppName --query 'name' -o tsv"
        $checkUiResult = Invoke-AzCommandWithRetry -Command $checkUiCmd
        
        if ($checkUiResult.Success -and -not [string]::IsNullOrWhiteSpace($checkUiResult.Output)) {
            $setUiEnvCmd = "az webapp config appsettings set -g $rgName -n $uiAppName --settings KEY_VAULT_NAME=$kvName -o none"
            $setUiEnvResult = Invoke-AzCommandWithRetry -Command $setUiEnvCmd
            
            if ($setUiEnvResult.Success) {
                Write-Host "  ✅ KEY_VAULT_NAME set on UI App" -ForegroundColor Green
            } else {
                Write-Host "  ⚠️  Failed to set KEY_VAULT_NAME on UI App" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "  ⚠️  Exception setting KEY_VAULT_NAME on UI App: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host "✅ KEY VAULT SECRET POPULATION COMPLETE" -ForegroundColor Green
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host ""
    Write-Host "End Time (UTC): $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host ""
    
    if ($secretsFailed -gt 0) {
        Write-Host "⚠️  Some secrets failed to add. Review errors above." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Troubleshooting:" -ForegroundColor Cyan
        Write-Host "  1. Key Vault Name: Check if '$kvName' is the correct name" -ForegroundColor Gray
        Write-Host "     Run: az keyvault list -g $rgName --query '[].name' -o tsv" -ForegroundColor DarkGray
        Write-Host "  2. RBAC Authorization: Verify you have 'Key Vault Secrets Officer' role" -ForegroundColor Gray
        Write-Host "     Run: az role assignment list --scope /subscriptions/<sub-id>/resourceGroups/$rgName/providers/Microsoft.KeyVault/vaults/$kvName" -ForegroundColor DarkGray
        Write-Host "  3. Access Policies: Check Key Vault access policies (if not using RBAC)" -ForegroundColor Gray
        Write-Host "     Run: az keyvault show -n $kvName -g $rgName --query properties.accessPolicies" -ForegroundColor DarkGray
        Write-Host "  4. Network Access: Ensure Key Vault firewall allows your IP" -ForegroundColor Gray
        Write-Host "     Run: az keyvault show -n $kvName -g $rgName --query properties.networkAcls" -ForegroundColor DarkGray
        Write-Host "  5. Key Vault Status: Verify Key Vault is not in soft-deleted state" -ForegroundColor Gray
        Write-Host "     Run: az keyvault list-deleted --query ""[?name=='$kvName']""" -ForegroundColor DarkGray
        Write-Host ""
        exit 1
    }
    
} catch {
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Red
    Write-Host "❌ EXCEPTION DURING SECRET POPULATION" -ForegroundColor Red
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Red
    Write-Host ""
    Write-Host "Exception Message: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Stack Trace:" -ForegroundColor Yellow
    Write-Host "$($_.ScriptStackTrace)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Timestamp (UTC): $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host ""
    Write-Error "Secret population failed: $($_.Exception.Message)"
    exit 1
}
