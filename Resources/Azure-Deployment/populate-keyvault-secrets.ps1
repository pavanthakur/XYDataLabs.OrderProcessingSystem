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

# Resource names
$rgName = "rg-$BaseName-$Environment"
$kvName = "kv-orderproc-$Environment"
$aiName = "ai-$BaseName-$Environment"

Write-Host "📋 Configuration:" -ForegroundColor Yellow
Write-Host "  Environment: $Environment" -ForegroundColor Gray
Write-Host "  Resource Group: $rgName" -ForegroundColor Gray
Write-Host "  Key Vault: $kvName" -ForegroundColor Gray
Write-Host "  App Insights: $aiName" -ForegroundColor Gray
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host ""

$secretsAdded = 0
$secretsFailed = 0

try {
    # Verify Key Vault exists
    Write-Host "🔍 Verifying Key Vault exists..." -ForegroundColor Cyan
    $kv = az keyvault show --name $kvName --resource-group $rgName 2>$null | ConvertFrom-Json
    
    if (-not $kv) {
        Write-Host "  ❌ Key Vault not found: $kvName" -ForegroundColor Red
        Write-Error "Key Vault '$kvName' does not exist in resource group '$rgName'"
    }
    
    Write-Host "  ✅ Key Vault found" -ForegroundColor Green
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
        az keyvault secret set `
            --vault-name $kvName `
            --name "OpenPayAdapter--ApiKey" `
            --value $OpenPayApiKey `
            --output none 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✅ OpenPayAdapter--ApiKey added successfully" -ForegroundColor Green
            $secretsAdded++
        } else {
            Write-Host "  ❌ Failed to add OpenPayAdapter--ApiKey (exit code: $LASTEXITCODE)" -ForegroundColor Red
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
            az keyvault secret set `
                --vault-name $kvName `
                --name "ApplicationInsights--ConnectionString" `
                --value $ApplicationInsightsConnectionString `
                --output none 2>&1 | Out-Null
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✅ ApplicationInsights--ConnectionString added successfully" -ForegroundColor Green
                $secretsAdded++
            } else {
                Write-Host "  ❌ Failed to add ApplicationInsights--ConnectionString (exit code: $LASTEXITCODE)" -ForegroundColor Red
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
        Write-Host "  1. Verify you have 'Key Vault Secrets Officer' role" -ForegroundColor Gray
        Write-Host "  2. Check Key Vault access policies" -ForegroundColor Gray
        Write-Host "  3. Ensure Key Vault firewall allows your IP" -ForegroundColor Gray
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
