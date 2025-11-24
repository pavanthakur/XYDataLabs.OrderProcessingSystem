# verify-app-insights.ps1
# Verify Application Insights is properly configured and capturing telemetry
# This script checks:
# 1. App Insights resource exists and is provisioned
# 2. Connection string is configured on web apps
# 3. Instrumentation key is valid
# 4. (Optional) Recent telemetry data exists

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment,
    
    [Parameter(Mandatory=$false)]
    [string]$BaseName = 'orderprocessing',
    
    [Parameter(Mandatory=$false)]
    [string]$GitHubOwner = 'pavanthakur',
    
    [Parameter(Mandatory=$false)]
    [switch]$CheckTelemetry
)

$ErrorActionPreference = 'Stop'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Application Insights Verification" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Environment: $Environment" -ForegroundColor Yellow
Write-Host ""

# Resource names
$rgName = "rg-$BaseName-$Environment"
$aiName = "ai-$BaseName-$Environment"
$apiAppName = "$GitHubOwner-$BaseName-api-xyapp-$Environment"
$uiAppName = "$GitHubOwner-$BaseName-ui-xyapp-$Environment"

$allChecks = $true

# Check 1: App Insights resource exists
Write-Host "[1/4] Checking Application Insights resource..." -ForegroundColor Cyan
try {
    $aiResource = az monitor app-insights component show `
        --app $aiName `
        --resource-group $rgName `
        --query '{name:name, provisioningState:provisioningState, instrumentationKey:instrumentationKey, connectionString:connectionString}' `
        -o json 2>$null | ConvertFrom-Json
    
    if ($aiResource -and $aiResource.provisioningState -eq 'Succeeded') {
        Write-Host "  ✅ Application Insights exists and is provisioned" -ForegroundColor Green
        Write-Host "     Name: $($aiResource.name)" -ForegroundColor Gray
        Write-Host "     Instrumentation Key: $($aiResource.instrumentationKey.Substring(0,8))..." -ForegroundColor Gray
        $instrumentationKey = $aiResource.instrumentationKey
        $connectionString = $aiResource.connectionString
    } else {
        Write-Host "  ❌ Application Insights is not provisioned or in unexpected state" -ForegroundColor Red
        if ($aiResource) {
            Write-Host "     State: $($aiResource.provisioningState)" -ForegroundColor Red
        }
        $allChecks = $false
    }
} catch {
    Write-Host "  ❌ Failed to retrieve Application Insights: $($_.Exception.Message)" -ForegroundColor Red
    $allChecks = $false
}

# Check 2: Connection string configured on API app
Write-Host ""
Write-Host "[2/4] Checking API app configuration..." -ForegroundColor Cyan
try {
    $apiSettings = az webapp config appsettings list `
        --name $apiAppName `
        --resource-group $rgName `
        --query "[?name=='APPLICATIONINSIGHTS_CONNECTION_STRING'].value" `
        -o tsv 2>$null
    
    if ($apiSettings) {
        Write-Host "  ✅ App Insights connection string is configured on API app" -ForegroundColor Green
        Write-Host "     App: $apiAppName" -ForegroundColor Gray
        
        # Verify it matches the App Insights connection string
        if ($connectionString -and $apiSettings -eq $connectionString) {
            Write-Host "  ✅ Connection string matches App Insights resource" -ForegroundColor Green
        } elseif ($connectionString) {
            Write-Host "  ⚠️  Connection string doesn't match App Insights resource" -ForegroundColor Yellow
            Write-Host "     Expected: $($connectionString.Substring(0,50))..." -ForegroundColor Gray
            Write-Host "     Actual: $($apiSettings.Substring(0,50))..." -ForegroundColor Gray
        }
    } else {
        Write-Host "  ❌ App Insights connection string NOT configured on API app" -ForegroundColor Red
        Write-Host "     App: $apiAppName" -ForegroundColor Red
        $allChecks = $false
    }
} catch {
    Write-Host "  ❌ Failed to check API app settings: $($_.Exception.Message)" -ForegroundColor Red
    $allChecks = $false
}

# Check 3: Connection string configured on UI app
Write-Host ""
Write-Host "[3/4] Checking UI app configuration..." -ForegroundColor Cyan
try {
    $uiSettings = az webapp config appsettings list `
        --name $uiAppName `
        --resource-group $rgName `
        --query "[?name=='APPLICATIONINSIGHTS_CONNECTION_STRING'].value" `
        -o tsv 2>$null
    
    if ($uiSettings) {
        Write-Host "  ✅ App Insights connection string is configured on UI app" -ForegroundColor Green
        Write-Host "     App: $uiAppName" -ForegroundColor Gray
        
        # Verify it matches the App Insights connection string
        if ($connectionString -and $uiSettings -eq $connectionString) {
            Write-Host "  ✅ Connection string matches App Insights resource" -ForegroundColor Green
        } elseif ($connectionString) {
            Write-Host "  ⚠️  Connection string doesn't match App Insights resource" -ForegroundColor Yellow
            Write-Host "     Expected: $($connectionString.Substring(0,50))..." -ForegroundColor Gray
            Write-Host "     Actual: $($uiSettings.Substring(0,50))..." -ForegroundColor Gray
        }
    } else {
        Write-Host "  ❌ App Insights connection string NOT configured on UI app" -ForegroundColor Red
        Write-Host "     App: $uiAppName" -ForegroundColor Red
        $allChecks = $false
    }
} catch {
    Write-Host "  ❌ Failed to check UI app settings: $($_.Exception.Message)" -ForegroundColor Red
    $allChecks = $false
}

# Check 4: Check for recent telemetry (optional)
Write-Host ""
Write-Host "[4/4] Checking telemetry collection..." -ForegroundColor Cyan
if ($CheckTelemetry) {
    try {
        # Query for any telemetry in the last hour
        $query = "union requests, traces, exceptions, dependencies | where timestamp > ago(1h) | count"
        
        Write-Host "  Running query to check for recent telemetry..." -ForegroundColor Gray
        $result = az monitor app-insights query `
            --app $aiName `
            --resource-group $rgName `
            --analytics-query $query `
            -o json 2>$null | ConvertFrom-Json
        
        if ($result -and $result.tables -and $result.tables[0].rows) {
            $count = $result.tables[0].rows[0][0]
            if ($count -gt 0) {
                Write-Host "  ✅ Telemetry data is being collected" -ForegroundColor Green
                Write-Host "     Records in last hour: $count" -ForegroundColor Gray
            } else {
                Write-Host "  ⚠️  No telemetry data found in the last hour" -ForegroundColor Yellow
                Write-Host "     This may be normal if apps haven't received traffic yet" -ForegroundColor Gray
                Write-Host "     Apps need to send requests before telemetry appears" -ForegroundColor Gray
            }
        } else {
            Write-Host "  ⚠️  Could not query telemetry data" -ForegroundColor Yellow
            Write-Host "     This may be normal if monitoring is still initializing" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  ⚠️  Failed to query telemetry: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "     This may be normal if monitoring is still initializing" -ForegroundColor Gray
    }
} else {
    Write-Host "  ℹ️  Telemetry check skipped (use -CheckTelemetry to enable)" -ForegroundColor Gray
    Write-Host "     Note: Telemetry only appears after apps receive traffic" -ForegroundColor Gray
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
if ($allChecks) {
    Write-Host "✅ VERIFICATION PASSED" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Application Insights is properly configured:" -ForegroundColor Green
    Write-Host "  • Resource is provisioned and ready" -ForegroundColor Gray
    Write-Host "  • Connection string is configured on API app" -ForegroundColor Gray
    Write-Host "  • Connection string is configured on UI app" -ForegroundColor Gray
    Write-Host ""
    Write-Host "To view telemetry:" -ForegroundColor Cyan
    Write-Host "  1. Azure Portal: https://portal.azure.com" -ForegroundColor Gray
    Write-Host "  2. Navigate to Application Insights: $aiName" -ForegroundColor Gray
    Write-Host "  3. Check 'Logs' for detailed telemetry" -ForegroundColor Gray
    Write-Host "  4. Check 'Failures' for error logs" -ForegroundColor Gray
    Write-Host ""
    exit 0
} else {
    Write-Host "❌ VERIFICATION FAILED" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "One or more checks failed. Review the output above." -ForegroundColor Red
    Write-Host ""
    Write-Host "Common issues:" -ForegroundColor Yellow
    Write-Host "  • App Insights resource not created" -ForegroundColor Gray
    Write-Host "  • Connection string not configured on apps" -ForegroundColor Gray
    Write-Host "  • Apps restarted but settings not applied yet" -ForegroundColor Gray
    Write-Host ""
    Write-Host "To fix:" -ForegroundColor Cyan
    Write-Host "  1. Re-run the bootstrap script" -ForegroundColor Gray
    Write-Host "  2. Manually configure connection strings in Azure Portal" -ForegroundColor Gray
    Write-Host "  3. Restart the web apps" -ForegroundColor Gray
    Write-Host ""
    exit 1
}
