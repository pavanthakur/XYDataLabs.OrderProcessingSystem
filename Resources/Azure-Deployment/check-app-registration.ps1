# Enhanced script to inspect OIDC App Registration and enumerate federated credentials
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "App Registration Verification" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

Write-Host "`nSearching for App Registration 'GitHub-Actions-OIDC'..." -ForegroundColor Yellow
$apps = az ad app list --display-name "GitHub-Actions-OIDC" | ConvertFrom-Json

if (-not $apps -or $apps.Count -eq 0) {
    Write-Host "  ❌ App registration not found." -ForegroundColor Red
    Write-Host "  Run: .\Resources\Azure-Deployment\setup-github-oidc.ps1 -ResourceGroupName <RG_NAME>" -ForegroundColor Yellow
    return
}

$app = $apps[0]
Write-Host "`n--- App Registration Details ---" -ForegroundColor Cyan
Write-Host "  Display Name : $($app.displayName)" -ForegroundColor White
Write-Host "  Client ID    : $($app.appId)" -ForegroundColor White
Write-Host "  Object ID    : $($app.id)" -ForegroundColor Gray

Write-Host "`n--- Federated Credentials ---" -ForegroundColor Cyan
$creds = az ad app federated-credential list --id $app.id | ConvertFrom-Json
if (-not $creds) { $creds = @() }

$branchCreds = $creds | Where-Object { $_.subject -like "repo:*:ref:*" }
$envCreds    = $creds | Where-Object { $_.subject -like "repo:*:environment:*" }
$otherCreds  = $creds | Where-Object { ($_.subject -notlike "repo:*:ref:*") -and ($_.subject -notlike "repo:*:environment:*") }

if ($branchCreds.Count -gt 0) {
    Write-Host "  ✅ Branch-based credentials:" -ForegroundColor Green
    foreach ($c in $branchCreds) { Write-Host "     - $($c.name) :: $($c.subject)" -ForegroundColor Gray }
} else { Write-Host "  ❌ No branch-based credentials found." -ForegroundColor Red }

if ($envCreds.Count -gt 0) {
    Write-Host "  ✅ Environment-based credentials:" -ForegroundColor Green
    foreach ($c in $envCreds) { Write-Host "     - $($c.name) :: $($c.subject)" -ForegroundColor Gray }
} else { Write-Host "  (None) environment-based credentials." -ForegroundColor DarkGray }

if ($otherCreds.Count -gt 0) {
    Write-Host "  ⚠️ Other credential subjects detected:" -ForegroundColor Yellow
    foreach ($c in $otherCreds) { Write-Host "     - $($c.name) :: $($c.subject)" -ForegroundColor Gray }
}

Write-Host "`n--- GitHub Actions Secrets ---" -ForegroundColor Cyan
Write-Host "  Ensure repository secrets are set:" -ForegroundColor White
Write-Host "     AZUREAPPSERVICE_CLIENTID    = $($app.appId)" -ForegroundColor Gray
Write-Host "     AZUREAPPSERVICE_TENANTID     = <TENANT_ID>" -ForegroundColor Gray
Write-Host "     AZUREAPPSERVICE_SUBSCRIPTIONID = <SUBSCRIPTION_ID>" -ForegroundColor Gray

Write-Host "`n--- Recommendations ---" -ForegroundColor Cyan
if ($branchCreds.Count -eq 0) {
    Write-Host "  Add branch credentials: re-run setup-github-oidc.ps1 with -Branches main,staging,dev" -ForegroundColor Yellow
}
if ($envCreds.Count -eq 0) {
    Write-Host "  Optional: add environment credentials via -Environments Production,QA if approvals desired." -ForegroundColor DarkYellow
}
Write-Host "  Keep only this app registration; remove deprecated duplicates if any exist." -ForegroundColor White
Write-Host "  Validate GitHub workflows deploy successfully using OIDC (id-token permission present)." -ForegroundColor White

Write-Host "`nAll checks complete." -ForegroundColor Cyan
