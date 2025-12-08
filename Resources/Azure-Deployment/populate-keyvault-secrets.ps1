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
    [string]$OpenPayApiKey,
    
    [Parameter(Mandatory=$false)]
    [string]$ApplicationInsightsConnectionString
)

$ErrorActionPreference = 'Stop'

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

# Resource names
$rgName = "rg-$BaseName-$Environment"
# Shorten base name for Key Vault (max 24 chars total)
$shortBaseName = $BaseName.Substring(0, [Math]::Min(15, $BaseName.Length))
$kvName = "kv-$shortBaseName-$Environment"
$aiName = "ai-$BaseName-$Environment"

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
    $kvError = $null
    $kv = az keyvault show --name $kvName --resource-group $rgName 2>&1 | Out-String
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ❌ Key Vault not found: $kvName" -ForegroundColor Red
        Write-Host "  Error details: $kv" -ForegroundColor Red
        Write-Host ""
        Write-Host "Checking if Key Vault exists with different name..." -ForegroundColor Yellow
        $allKvs = az keyvault list --resource-group $rgName --query "[].name" -o tsv 2>&1
        if ($LASTEXITCODE -eq 0 -and $allKvs) {
            Write-Host "  Found Key Vaults in $rgName`:" -ForegroundColor Yellow
            $allKvs -split "`n" | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
        } else {
            Write-Host "  No Key Vaults found in resource group $rgName" -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Error "Key Vault '$kvName' does not exist in resource group '$rgName'"
    }
    
    # Parse the JSON to get Key Vault properties
    try {
        $kvObj = $kv | ConvertFrom-Json
        Write-Host "  ✅ Key Vault found: $kvName" -ForegroundColor Green
        Write-Host "     Location: $($kvObj.location)" -ForegroundColor Gray
        Write-Host "     Provisioning State: $($kvObj.properties.provisioningState)" -ForegroundColor Gray
        Write-Host "     RBAC Authorization: $($kvObj.properties.enableRbacAuthorization)" -ForegroundColor Gray
        Write-Host "     Vault URI: $($kvObj.properties.vaultUri)" -ForegroundColor Gray
    } catch {
        Write-Host "  ✅ Key Vault found (unable to parse details)" -ForegroundColor Green
    }
    Write-Host ""
    
    # 1. Add OpenPayAdapter API Key
    Write-Host "🔑 [1/2] Adding OpenPayAdapter API Key..." -ForegroundColor Cyan
    
    if ([string]::IsNullOrWhiteSpace($OpenPayApiKey)) {
        # Generate a placeholder value for development/testing
        Write-Host "  ⚠️  No API key provided, using placeholder value" -ForegroundColor Yellow
        $OpenPayApiKey = "openpay-api-key-placeholder-$Environment-$(Get-Date -Format 'yyyyMMdd')"
        Write-Host "  ℹ️  NOTE: Replace this with actual API key before production use" -ForegroundColor Yellow
    }
    
    try {
        $output = az keyvault secret set `
            --vault-name $kvName `
            --name "OpenPayAdapter--ApiKey" `
            --value $OpenPayApiKey `
            --output json 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✅ OpenPayAdapter--ApiKey added successfully" -ForegroundColor Green
            $secretsAdded++
        } else {
            Write-Host "  ❌ Failed to add OpenPayAdapter--ApiKey (exit code: $LASTEXITCODE)" -ForegroundColor Red
            Write-Host "  Error details: $output" -ForegroundColor Red
            $secretsFailed++
        }
    } catch {
        Write-Host "  ❌ Exception adding OpenPayAdapter--ApiKey: $($_.Exception.Message)" -ForegroundColor Red
        $secretsFailed++
    }
    
    Write-Host ""
    
    # 2. Add Application Insights Connection String
    Write-Host "🔑 [2/2] Adding Application Insights Connection String..." -ForegroundColor Cyan
    
    if ([string]::IsNullOrWhiteSpace($ApplicationInsightsConnectionString)) {
        # Retrieve from Application Insights resource
        Write-Host "  🔍 Retrieving connection string from Application Insights..." -ForegroundColor Gray
        
        try {
            $aiConnString = az monitor app-insights component show `
                --app $aiName `
                --resource-group $rgName `
                --query connectionString `
                -o tsv 2>$null
            
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($aiConnString)) {
                $ApplicationInsightsConnectionString = $aiConnString
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
            $output = az keyvault secret set `
                --vault-name $kvName `
                --name "ApplicationInsights--ConnectionString" `
                --value $ApplicationInsightsConnectionString `
                --output json 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✅ ApplicationInsights--ConnectionString added successfully" -ForegroundColor Green
                $secretsAdded++
            } else {
                Write-Host "  ❌ Failed to add ApplicationInsights--ConnectionString (exit code: $LASTEXITCODE)" -ForegroundColor Red
                Write-Host "  Error details: $output" -ForegroundColor Red
                $secretsFailed++
            }
        } catch {
            Write-Host "  ❌ Exception adding ApplicationInsights--ConnectionString: $($_.Exception.Message)" -ForegroundColor Red
            $secretsFailed++
        }
    }
    
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
    $secrets = az keyvault secret list --vault-name $kvName --query "[].name" -o tsv 2>$null
    
    if ($secrets) {
        $secretList = $secrets -split "`n" | Where-Object { $_ }
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
    $apiAppName = "$GitHubOwner-$BaseName-api-xyapp-$Environment"
    $uiAppName = "$GitHubOwner-$BaseName-ui-xyapp-$Environment"
    
    # Set on API App
    try {
        $apiExists = az webapp show -g $rgName -n $apiAppName --query "name" -o tsv 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($apiExists)) {
            $result = az webapp config appsettings set -g $rgName -n $apiAppName --settings KEY_VAULT_NAME=$kvName -o none 2>&1
            if ($LASTEXITCODE -eq 0) {
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
        $uiExists = az webapp show -g $rgName -n $uiAppName --query "name" -o tsv 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($uiExists)) {
            $result = az webapp config appsettings set -g $rgName -n $uiAppName --settings KEY_VAULT_NAME=$kvName -o none 2>&1
            if ($LASTEXITCODE -eq 0) {
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
