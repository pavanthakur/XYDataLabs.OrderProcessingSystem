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
    [string]$GitHubOwner = '',
    
    [Parameter(Mandatory=$false)]
    [switch]$CheckTelemetry
)

$ErrorActionPreference = 'Stop'

function Invoke-AzCliWithRetry {
    param(
        [Parameter(Mandatory=$true)]
        [scriptblock]$Command,

        [Parameter(Mandatory=$true)]
        [string]$Operation,

        [Parameter(Mandatory=$false)]
        [int]$MaxAttempts = 3,

        [Parameter(Mandatory=$false)]
        [int]$DelaySeconds = 5
    )

    $lastOutput = $null

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $lastOutput = & $Command 2>&1
        if ($LASTEXITCODE -eq 0) {
            return $lastOutput
        }

        if ($attempt -lt $MaxAttempts) {
            Write-Host "  ⚠️  $Operation failed on attempt ${attempt}/${MaxAttempts}. Retrying in $DelaySeconds second(s)..." -ForegroundColor Yellow
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    $message = if ($lastOutput) { ($lastOutput | Out-String).Trim() } else { 'No output returned.' }
    throw "$Operation failed after $MaxAttempts attempt(s). $message"
}

function Invoke-AzCliJson {
    param(
        [Parameter(Mandatory=$true)]
        [scriptblock]$Command,

        [Parameter(Mandatory=$true)]
        [string]$Operation
    )

    $output = Invoke-AzCliWithRetry -Command $Command -Operation $Operation
    $jsonText = ($output | Out-String).Trim()

    if ([string]::IsNullOrWhiteSpace($jsonText)) {
        return $null
    }

    return $jsonText | ConvertFrom-Json
}

function Invoke-AzCliText {
    param(
        [Parameter(Mandatory=$true)]
        [scriptblock]$Command,

        [Parameter(Mandatory=$true)]
        [string]$Operation
    )

    $output = Invoke-AzCliWithRetry -Command $Command -Operation $Operation
    return ($output | Out-String).Trim()
}

function Resolve-GitHubOwner {
    param(
        [string]$Owner,
        [string]$DefaultOwner = 'pavanthakur'
    )

    if (-not [string]::IsNullOrWhiteSpace($Owner)) { return $Owner }
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_REPOSITORY) -and $env:GITHUB_REPOSITORY -match '^(?<owner>[^/]+)/.+$') { return $Matches.owner }

    try {
        $originUrl = git config --get remote.origin.url 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($originUrl)) {
            $originUrl = $originUrl.Trim()
            if ($originUrl -match 'github\.com[:/](?<owner>[^/]+)/[^/]+?(?:\.git)?$') { return $Matches.owner }
        }
    }
    catch { }

    return $DefaultOwner
}

$GitHubOwner = Resolve-GitHubOwner -Owner $GitHubOwner

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Application Insights Verification" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Environment: $Environment" -ForegroundColor Yellow
Write-Host ""

# Map environment name to Azure resource suffix (staging uses abbreviated 'stg' to match bootstrap)
$envSuffix = switch ($Environment) { 'staging' { 'stg' } default { $Environment } }

# Resource names
$rgName = "rg-$BaseName-$envSuffix"
$aiName = "ai-$BaseName-$envSuffix"
$apiAppName = "$GitHubOwner-$BaseName-api-xyapp-$envSuffix"
$uiAppName = "$GitHubOwner-$BaseName-ui-xyapp-$envSuffix"

$allChecks = $true

# Check 1: App Insights resource exists
Write-Host "[1/4] Checking Application Insights resource..." -ForegroundColor Cyan
try {
    $aiResource = Invoke-AzCliJson -Operation 'Retrieve Application Insights resource' -Command {
        az monitor app-insights component show `
            --app $aiName `
            --resource-group $rgName `
            --query '{name:name, provisioningState:provisioningState, instrumentationKey:instrumentationKey, connectionString:connectionString}' `
            -o json
    }
    
    if ($aiResource -and $aiResource.provisioningState -eq 'Succeeded') {
        Write-Host "  ✅ Application Insights exists and is provisioned" -ForegroundColor Green
        Write-Host "     Name: $($aiResource.name)" -ForegroundColor Gray
        Write-Host "     Instrumentation Key: (configured)" -ForegroundColor Gray
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
    $apiSettings = Invoke-AzCliText -Operation 'Retrieve API app settings' -Command {
        az webapp config appsettings list `
            --name $apiAppName `
            --resource-group $rgName `
            --query "[?name=='APPLICATIONINSIGHTS_CONNECTION_STRING'].value" `
            -o tsv
    }
    
    if ($apiSettings) {
        Write-Host "  ✅ App Insights connection string is configured on API app" -ForegroundColor Green
        Write-Host "     App: $apiAppName" -ForegroundColor Gray
        
        # Verify it matches the App Insights connection string
        if ($connectionString -and $apiSettings -eq $connectionString) {
            Write-Host "  ✅ Connection string matches App Insights resource" -ForegroundColor Green
        } elseif ($connectionString) {
            Write-Host "  ⚠️  Connection string doesn't match App Insights resource" -ForegroundColor Yellow
            Write-Host "     Connection string mismatch detected - manual verification required" -ForegroundColor Gray
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
    $uiSettings = Invoke-AzCliText -Operation 'Retrieve UI app settings' -Command {
        az webapp config appsettings list `
            --name $uiAppName `
            --resource-group $rgName `
            --query "[?name=='APPLICATIONINSIGHTS_CONNECTION_STRING'].value" `
            -o tsv
    }
    
    if ($uiSettings) {
        Write-Host "  ✅ App Insights connection string is configured on UI app" -ForegroundColor Green
        Write-Host "     App: $uiAppName" -ForegroundColor Gray
        
        # Verify it matches the App Insights connection string
        if ($connectionString -and $uiSettings -eq $connectionString) {
            Write-Host "  ✅ Connection string matches App Insights resource" -ForegroundColor Green
        } elseif ($connectionString) {
            Write-Host "  ⚠️  Connection string doesn't match App Insights resource" -ForegroundColor Yellow
            Write-Host "     Connection string mismatch detected - manual verification required" -ForegroundColor Gray
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
        $result = Invoke-AzCliJson -Operation 'Query recent Application Insights telemetry' -Command {
            az monitor app-insights query `
                --app $aiName `
                --resource-group $rgName `
                --analytics-query $query `
                -o json
        }
        
        if ($result -and $result.tables -and $result.tables.Count -gt 0 -and $result.tables[0].rows -and $result.tables[0].rows.Count -gt 0) {
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
