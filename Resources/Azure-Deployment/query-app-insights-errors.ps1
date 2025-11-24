# query-app-insights-errors.ps1
# Query Application Insights for errors and warnings
# Usage: ./query-app-insights-errors.ps1 -Environment dev -BaseName orderprocessing

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'dev',
    
    [Parameter(Mandatory=$false)]
    [string]$BaseName = 'orderprocessing',
    
    [Parameter(Mandatory=$false)]
    [int]$HoursBack = 24
)

$ErrorActionPreference = 'Stop'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Application Insights Error Query" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Generate resource names
$rgName = "rg-$BaseName-$Environment"
$aiName = "ai-$BaseName-$Environment"

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Environment:          $Environment" -ForegroundColor Gray
Write-Host "  Resource Group:       $rgName" -ForegroundColor Gray
Write-Host "  App Insights:         $aiName" -ForegroundColor Gray
Write-Host "  Time Range:           Last $HoursBack hours" -ForegroundColor Gray
Write-Host ""

# Check if Application Insights exists
Write-Host "[1/4] Checking Application Insights resource..." -ForegroundColor Cyan
$aiExists = az monitor app-insights component show -a $aiName -g $rgName --query "name" -o tsv 2>$null

if (-not $aiExists -or $aiExists -ne $aiName) {
    Write-Host "  [ERROR] Application Insights resource not found: $aiName" -ForegroundColor Red
    Write-Host "  [HINT] Run bootstrap workflow to provision Application Insights" -ForegroundColor Yellow
    exit 1
}
Write-Host "  [OK] Application Insights found: $aiName" -ForegroundColor Green
Write-Host ""

# Get Application Insights App ID
Write-Host "[2/4] Getting Application Insights App ID..." -ForegroundColor Cyan
$appId = az monitor app-insights component show -a $aiName -g $rgName --query "appId" -o tsv 2>$null

if (-not $appId) {
    Write-Host "  [ERROR] Failed to get Application Insights App ID" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] App ID: $appId" -ForegroundColor Green
Write-Host ""

# Query for exceptions/errors
Write-Host "[3/4] Querying for exceptions and errors..." -ForegroundColor Cyan
$timeSpan = "PT${HoursBack}H"

# Query for exceptions
$exceptionsQuery = @"
exceptions
| where timestamp > ago($HoursBack h)
| summarize Count=count() by type, problemId, outerMessage
| order by Count desc
| take 20
"@

try {
    $exceptions = az monitor app-insights query --app $appId --analytics-query $exceptionsQuery --query "tables[0].rows" -o json 2>$null
    
    if ($exceptions) {
        $exceptionData = $exceptions | ConvertFrom-Json
        if ($exceptionData.Count -gt 0) {
            Write-Host "  [FOUND] $($exceptionData.Count) exception types:" -ForegroundColor Yellow
            # Query returns: [type, problemId, Count, outerMessage]
            foreach ($ex in $exceptionData) {
                $exType = $ex[0]
                $exCount = $ex[2]
                $exMessage = $ex[3]
                Write-Host "    • Type: $exType" -ForegroundColor Red
                Write-Host "      Count: $exCount" -ForegroundColor Gray
                Write-Host "      Message: $exMessage" -ForegroundColor Gray
                Write-Host ""
            }
        } else {
            Write-Host "  [OK] No exceptions found in last $HoursBack hours" -ForegroundColor Green
        }
    } else {
        Write-Host "  [INFO] No exception data available yet" -ForegroundColor Gray
    }
} catch {
    Write-Host "  [WARN] Failed to query exceptions: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""

# Query for failed requests
Write-Host "[4/4] Querying for failed requests..." -ForegroundColor Cyan
$failedRequestsQuery = @"
requests
| where timestamp > ago($HoursBack h)
| where success == false
| summarize Count=count() by resultCode, name
| order by Count desc
| take 20
"@

try {
    $failedRequests = az monitor app-insights query --app $appId --analytics-query $failedRequestsQuery --query "tables[0].rows" -o json 2>$null
    
    if ($failedRequests) {
        $failedData = $failedRequests | ConvertFrom-Json
        if ($failedData.Count -gt 0) {
            Write-Host "  [FOUND] $($failedData.Count) failed request types:" -ForegroundColor Yellow
            # Query returns: [Count, resultCode, name]
            foreach ($req in $failedData) {
                $reqCount = $req[0]
                $reqStatusCode = $req[1]
                $reqEndpoint = $req[2]
                Write-Host "    • Status Code: $reqStatusCode" -ForegroundColor Red
                Write-Host "      Count: $reqCount" -ForegroundColor Gray
                Write-Host "      Endpoint: $reqEndpoint" -ForegroundColor Gray
                Write-Host ""
            }
        } else {
            Write-Host "  [OK] No failed requests found in last $HoursBack hours" -ForegroundColor Green
        }
    } else {
        Write-Host "  [INFO] No request data available yet" -ForegroundColor Gray
    }
} catch {
    Write-Host "  [WARN] Failed to query requests: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "QUERY COMPLETE" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Additional queries
Write-Host "📊 Additional Insights:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Portal: https://portal.azure.com" -ForegroundColor Gray
Write-Host "  Navigate to: Application Insights → $aiName → Logs" -ForegroundColor Gray
Write-Host ""
Write-Host "  Useful queries:" -ForegroundColor Yellow
Write-Host "    • traces | where timestamp > ago(1h) | order by timestamp desc" -ForegroundColor Gray
Write-Host "    • exceptions | where timestamp > ago(1h) | order by timestamp desc" -ForegroundColor Gray
Write-Host "    • requests | where timestamp > ago(1h) | order by timestamp desc" -ForegroundColor Gray
Write-Host "    • dependencies | where timestamp > ago(1h) | order by timestamp desc" -ForegroundColor Gray
Write-Host ""

exit 0
