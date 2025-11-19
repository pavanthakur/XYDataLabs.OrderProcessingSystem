# Fix Federated Credential for GitHub-Actions-OIDC
# This adds the missing federated credential to the correct app registration

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Fix Federated Credential" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

$appName = "GitHub-Actions-OIDC"
$expectedClientId = "b0e89b89-4cc4-4b56-a633-3e753960085f"

Write-Host "`n[1/3] Finding App Registration: $appName" -ForegroundColor Yellow
$app = az ad app list --display-name $appName | ConvertFrom-Json

if ($app.Count -eq 0) {
    Write-Host "❌ Error: App Registration '$appName' not found!" -ForegroundColor Red
    exit 1
}

$appId = $app[0].appId
$appObjectId = $app[0].id

Write-Host "   Found: $appName" -ForegroundColor Green
Write-Host "   Client ID: $appId" -ForegroundColor White
Write-Host "   Object ID: $appObjectId" -ForegroundColor Gray

if ($appId -ne $expectedClientId) {
    Write-Host "❌ Error: Client ID mismatch!" -ForegroundColor Red
    Write-Host "   Expected: $expectedClientId" -ForegroundColor White
    Write-Host "   Found: $appId" -ForegroundColor White
    exit 1
}

Write-Host "`n[2/3] Checking existing federated credentials..." -ForegroundColor Yellow
$existingCreds = az ad app federated-credential list --id $appObjectId | ConvertFrom-Json

$credName = "github-main-oidc"
$credExists = $existingCreds | Where-Object { $_.name -eq $credName }

if ($credExists) {
    Write-Host "   ✅ Federated credential '$credName' already exists" -ForegroundColor Green
    Write-Host "   Subject: $($credExists.subject)" -ForegroundColor Gray
    Write-Host "`n   No action needed. Setup is complete!" -ForegroundColor Green
    exit 0
}

Write-Host "   Creating federated credential..." -ForegroundColor Yellow

Write-Host "`n[3/3] Adding federated credential for branch: main" -ForegroundColor Yellow

# Create credential JSON
$credentialJson = @{
    name = "github-main-oidc"
    issuer = "https://token.actions.githubusercontent.com"
    subject = "repo:getpavanthakur/TestAppXY_OrderProcessingSystem:ref:refs/heads/main"
    audiences = @("api://AzureADTokenExchange")
} | ConvertTo-Json

# Create temp file
$tempFile = [System.IO.Path]::GetTempFileName()
$credentialJson | Out-File -FilePath $tempFile -Encoding UTF8

try {
    az ad app federated-credential create --id $appObjectId --parameters $tempFile | Out-Null
    Write-Host "   ✅ Federated credential created successfully!" -ForegroundColor Green
    Write-Host "      Name: github-main-oidc" -ForegroundColor White
    Write-Host "      Subject: repo:getpavanthakur/TestAppXY_OrderProcessingSystem:ref:refs/heads/main" -ForegroundColor Gray
} catch {
    Write-Host "   ❌ Error creating federated credential: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    Remove-Item $tempFile -ErrorAction SilentlyContinue
}

Write-Host "`n=====================================" -ForegroundColor Cyan
Write-Host "✅ Setup Complete!" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Cyan

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "1. Your GitHub secrets are already correct:" -ForegroundColor White
Write-Host "   AZUREAPPSERVICE_CLIENTID: $appId" -ForegroundColor Gray
Write-Host ""
Write-Host "2. You can now safely DELETE the old app registration:" -ForegroundColor White
Write-Host "   Azure Portal → Entra ID → App registrations → GitHub-Actions-OrderProcessing-OIDC → Delete" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Test deployment:" -ForegroundColor White
Write-Host "   GitHub Actions → Run workflow manually" -ForegroundColor Gray
Write-Host ""
