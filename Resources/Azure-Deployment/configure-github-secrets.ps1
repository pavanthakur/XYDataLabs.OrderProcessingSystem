<#
.SYNOPSIS
  Automatically configures GitHub repository secrets for Azure OIDC deployment
.DESCRIPTION
  Retrieves Azure OIDC credentials and automatically adds them as GitHub repository secrets.
  Requires GitHub CLI (gh) to be installed and authenticated.
.PARAMETER Repository
  GitHub repository in format owner/repo (e.g., getpavanthakur/TestAppXY_OrderProcessingSystem)
.PARAMETER Force
  Overwrite existing secrets without prompting
.EXAMPLE
  ./configure-github-secrets.ps1 -Repository getpavanthakur/TestAppXY_OrderProcessingSystem
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$Repository = "getpavanthakur/TestAppXY_OrderProcessingSystem",
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "GitHub Secrets Configuration" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check GitHub CLI
Write-Host "[1/5] Checking GitHub CLI..." -ForegroundColor Cyan
$ghInstalled = Get-Command gh -ErrorAction SilentlyContinue
if (-not $ghInstalled) {
    Write-Host "  [ERROR] GitHub CLI (gh) not found" -ForegroundColor Red
    Write-Host "  [INSTALL] Download from: https://cli.github.com/" -ForegroundColor Yellow
    Write-Host "  [INSTALL] Or run: winget install --id GitHub.cli" -ForegroundColor Yellow
    exit 1
}
Write-Host "  [OK] GitHub CLI found: $(gh --version | Select-Object -First 1)" -ForegroundColor Green

# Step 2: Check GitHub authentication
Write-Host "[2/5] Checking GitHub authentication..." -ForegroundColor Cyan
try {
    $ghAuthStatus = gh auth status 2>&1 | Out-String
    if ($ghAuthStatus -match "Logged in to github.com") {
        Write-Host "  [OK] Authenticated to github.com" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Not authenticated to GitHub" -ForegroundColor Yellow
        Write-Host "  [ACTION] Running: gh auth login" -ForegroundColor Yellow
        gh auth login
    }
} catch {
    Write-Host "  [ERROR] GitHub authentication failed" -ForegroundColor Red
    Write-Host "  [ACTION] Run: gh auth login" -ForegroundColor Yellow
    exit 1
}

# Step 3: Retrieve Azure credentials
Write-Host "[3/5] Retrieving Azure OIDC credentials..." -ForegroundColor Cyan

# Get current subscription
$sub = az account show 2>$null | ConvertFrom-Json
if (-not $sub) {
    Write-Host "  [ERROR] Not logged into Azure CLI" -ForegroundColor Red
    Write-Host "  [ACTION] Run: az login" -ForegroundColor Yellow
    exit 1
}

$subscriptionId = $sub.id
$tenantId = $sub.tenantId
Write-Host "  [OK] Subscription: $($sub.name)" -ForegroundColor Green
Write-Host "       ID: $subscriptionId" -ForegroundColor Gray
Write-Host "       Tenant: $tenantId" -ForegroundColor Gray

# Get GitHub Actions OIDC app
$app = az ad app list --display-name "GitHub-Actions-OIDC" 2>$null | ConvertFrom-Json
if (-not $app -or $app.Count -eq 0) {
    Write-Host "  [ERROR] GitHub-Actions-OIDC app registration not found" -ForegroundColor Red
    Write-Host "  [ACTION] Run bootstrap-enterprise-infra.ps1 first to create OIDC app" -ForegroundColor Yellow
    exit 1
}

$clientId = $app[0].appId
Write-Host "  [OK] App Registration: GitHub-Actions-OIDC" -ForegroundColor Green
Write-Host "       Client ID: $clientId" -ForegroundColor Gray

# Step 4: Prepare secrets
Write-Host "[4/5] Preparing secrets..." -ForegroundColor Cyan
$secrets = @{
    "AZUREAPPSERVICE_CLIENTID" = $clientId
    "AZUREAPPSERVICE_TENANTID" = $tenantId
    "AZUREAPPSERVICE_SUBSCRIPTIONID" = $subscriptionId
}

Write-Host "  [INFO] Secrets to configure:" -ForegroundColor Yellow
foreach ($key in $secrets.Keys) {
    $maskedValue = $secrets[$key].Substring(0, 8) + "..." + $secrets[$key].Substring($secrets[$key].Length - 4)
    Write-Host "    $key = $maskedValue" -ForegroundColor Gray
}

# Step 5: Set GitHub secrets
Write-Host "[5/5] Setting GitHub repository secrets..." -ForegroundColor Cyan

$successCount = 0
$failCount = 0

foreach ($secretName in $secrets.Keys) {
    $secretValue = $secrets[$secretName]
    
    try {
        # Check if secret exists
        $existingSecret = gh secret list --repo $Repository 2>$null | Select-String -Pattern "^$secretName"
        
        if ($existingSecret -and -not $Force) {
            Write-Host "  [SKIP] $secretName (already exists, use -Force to overwrite)" -ForegroundColor Yellow
            $successCount++
            continue
        }
        
        # Set secret
        $secretValue | gh secret set $secretName --repo $Repository 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            if ($existingSecret) {
                Write-Host "  [UPDATED] $secretName" -ForegroundColor Cyan
            } else {
                Write-Host "  [CREATED] $secretName" -ForegroundColor Green
            }
            $successCount++
        } else {
            Write-Host "  [FAILED] $secretName" -ForegroundColor Red
            $failCount++
        }
    } catch {
        Write-Host "  [ERROR] $secretName - $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
    }
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "CONFIGURATION COMPLETE" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Repository: $Repository" -ForegroundColor White
Write-Host "  Success:    $successCount / $($secrets.Count)" -ForegroundColor $(if ($successCount -eq $secrets.Count) { "Green" } else { "Yellow" })
Write-Host "  Failed:     $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })
Write-Host ""

# Verify secrets
Write-Host "Verification:" -ForegroundColor Cyan
Write-Host "  View secrets: https://github.com/$Repository/settings/secrets/actions" -ForegroundColor Gray
Write-Host "  List secrets: gh secret list --repo $Repository" -ForegroundColor Gray
Write-Host ""

if ($successCount -eq $secrets.Count) {
    Write-Host "[SUCCESS] All GitHub secrets configured!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. Push code to dev branch to trigger deployment" -ForegroundColor White
    Write-Host "  2. Monitor workflow: https://github.com/$Repository/actions" -ForegroundColor White
    Write-Host ""
    exit 0
} else {
    Write-Host "[WARNING] Some secrets failed to configure" -ForegroundColor Yellow
    Write-Host "  Review errors above and configure manually if needed" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}
