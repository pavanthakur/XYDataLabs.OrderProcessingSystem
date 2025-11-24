# verify-deployment-endpoints.ps1
# Verify all deployment endpoints are accessible
# Usage: ./verify-deployment-endpoints.ps1 -Environment dev -GitHubOwner pavanthakur

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'dev',
    
    [Parameter(Mandatory=$false)]
    [string]$BaseName = 'orderprocessing',
    
    [Parameter(Mandatory=$false)]
    [string]$GitHubOwner = 'pavanthakur'
)

$ErrorActionPreference = 'Continue'  # Continue on errors to test all endpoints

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deployment Endpoint Verification" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Generate app names
$apiAppName = "$GitHubOwner-$BaseName-api-xyapp-$Environment"
$uiAppName = "$GitHubOwner-$BaseName-ui-xyapp-$Environment"

# Generate URLs
$apiBaseUrl = "https://$apiAppName.azurewebsites.net"
$apiSwaggerUrl = "$apiBaseUrl/swagger"
$uiBaseUrl = "https://$uiAppName.azurewebsites.net"

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Environment:    $Environment" -ForegroundColor Gray
Write-Host "  API App:        $apiAppName" -ForegroundColor Gray
Write-Host "  UI App:         $uiAppName" -ForegroundColor Gray
Write-Host ""

$allSuccess = $true

# Test API Base URL
Write-Host "[1/3] Testing API base endpoint..." -ForegroundColor Cyan
Write-Host "      URL: $apiBaseUrl" -ForegroundColor Gray
try {
    $response = Invoke-WebRequest -Uri $apiBaseUrl -Method Get -TimeoutSec 30 -UseBasicParsing -ErrorAction Stop
    Write-Host "  [OK] Status: $($response.StatusCode) $($response.StatusDescription)" -ForegroundColor Green
    Write-Host "  [OK] API is responding" -ForegroundColor Green
} catch {
    Write-Host "  [ERROR] API endpoint failed" -ForegroundColor Red
    Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    $allSuccess = $false
}
Write-Host ""

# Test Swagger URL
Write-Host "[2/3] Testing Swagger UI..." -ForegroundColor Cyan
Write-Host "      URL: $apiSwaggerUrl" -ForegroundColor Gray
try {
    $response = Invoke-WebRequest -Uri $apiSwaggerUrl -Method Get -TimeoutSec 30 -UseBasicParsing -ErrorAction Stop
    Write-Host "  [OK] Status: $($response.StatusCode) $($response.StatusDescription)" -ForegroundColor Green
    Write-Host "  [OK] Swagger UI is accessible" -ForegroundColor Green
    
    # Check if response contains swagger-related content
    if ($response.Content -match "swagger|Swagger|OpenAPI") {
        Write-Host "  [OK] Swagger content detected in response" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Response doesn't appear to contain Swagger content" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  [ERROR] Swagger endpoint failed" -ForegroundColor Red
    Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  [HINT] Check ASPNETCORE_ENVIRONMENT is set to 'Development', 'Staging', or 'Production'" -ForegroundColor Yellow
    $allSuccess = $false
}
Write-Host ""

# Test UI URL
Write-Host "[3/3] Testing UI endpoint..." -ForegroundColor Cyan
Write-Host "      URL: $uiBaseUrl" -ForegroundColor Gray
try {
    $response = Invoke-WebRequest -Uri $uiBaseUrl -Method Get -TimeoutSec 30 -UseBasicParsing -ErrorAction Stop
    Write-Host "  [OK] Status: $($response.StatusCode) $($response.StatusDescription)" -ForegroundColor Green
    Write-Host "  [OK] UI is responding" -ForegroundColor Green
} catch {
    Write-Host "  [ERROR] UI endpoint failed" -ForegroundColor Red
    Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    $allSuccess = $false
}
Write-Host ""

# Summary
Write-Host "========================================" -ForegroundColor Cyan
if ($allSuccess) {
    Write-Host "✅ ALL ENDPOINTS VERIFIED" -ForegroundColor Green
} else {
    Write-Host "⚠️  SOME ENDPOINTS FAILED" -ForegroundColor Yellow
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Direct links
Write-Host "📋 Quick Access Links:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  API Swagger:  $apiSwaggerUrl" -ForegroundColor White
Write-Host "  API Base:     $apiBaseUrl" -ForegroundColor White
Write-Host "  UI:           $uiBaseUrl" -ForegroundColor White
Write-Host ""

# Azure Portal Links
Write-Host "🔗 Azure Portal:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  API App Service:  https://portal.azure.com/#view/Microsoft_Azure_WACenterPoint/WebsiteBlade/id/%2Fsubscriptions%2F{subscription-id}%2FresourceGroups%2Frg-$BaseName-$Environment%2Fproviders%2FMicrosoft.Web%2Fsites%2F$apiAppName" -ForegroundColor Gray
Write-Host "  UI App Service:   https://portal.azure.com/#view/Microsoft_Azure_WACenterPoint/WebsiteBlade/id/%2Fsubscriptions%2F{subscription-id}%2FresourceGroups%2Frg-$BaseName-$Environment%2Fproviders%2FMicrosoft.Web%2Fsites%2F$uiAppName" -ForegroundColor Gray
Write-Host ""

if ($allSuccess) {
    exit 0
} else {
    exit 1
}
