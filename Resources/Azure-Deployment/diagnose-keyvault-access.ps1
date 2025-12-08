# diagnose-keyvault-access.ps1
# Comprehensive diagnostic script to identify Key Vault access issues

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'dev',
    
    [Parameter(Mandatory=$false)]
    [string]$BaseName = 'orderprocessing',
    
    [Parameter(Mandatory=$false)]
    [string]$GitHubOwner = 'pavanthakur'
)

Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     KEY VAULT ACCESS DIAGNOSTIC - $($Environment.ToUpper().PadRight(29))║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

$rg = "rg-$BaseName-$Environment"
$apiApp = "$GitHubOwner-$BaseName-api-xyapp-$Environment"
$uiApp = "$GitHubOwner-$BaseName-ui-xyapp-$Environment"

# Step 1: Check if Resource Group exists
Write-Host "`n[Step 1] Verifying Resource Group..." -ForegroundColor Yellow
$rgExists = az group exists -n $rg 2>$null
if ($rgExists -eq 'true') {
    Write-Host "  ✅ Resource Group exists: $rg" -ForegroundColor Green
} else {
    Write-Host "  ❌ Resource Group does not exist: $rg" -ForegroundColor Red
    Write-Host "  💡 Run the Azure Bootstrap workflow to create infrastructure" -ForegroundColor Cyan
    exit 1
}

# Step 2: Find Key Vault
Write-Host "`n[Step 2] Locating Key Vault..." -ForegroundColor Yellow
$kvs = az resource list -g $rg --resource-type "Microsoft.KeyVault/vaults" --query "[].name" -o json 2>$null | ConvertFrom-Json
if (-not $kvs -or $kvs.Count -eq 0) {
    Write-Host "  ❌ No Key Vault found in resource group" -ForegroundColor Red
    Write-Host "  💡 Run the Azure Bootstrap workflow to create Key Vault" -ForegroundColor Cyan
    exit 1
}

$kvName = $kvs[0]
Write-Host "  ✅ Key Vault found: $kvName" -ForegroundColor Green

# Step 3: Validate Key Vault name format
Write-Host "`n[Step 3] Validating Key Vault name format..." -ForegroundColor Yellow
if ($kvName -match '^[a-zA-Z0-9\-]{3,24}$') {
    Write-Host "  ✅ Key Vault name format is valid" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  Key Vault name format may be invalid: $kvName" -ForegroundColor Yellow
    Write-Host "     Key Vault names must be 3-24 characters, alphanumeric and hyphens only" -ForegroundColor Gray
}

# Step 4: Check KEY_VAULT_NAME environment variable on App Services
Write-Host "`n[Step 4] Checking KEY_VAULT_NAME environment variable..." -ForegroundColor Yellow

# Check if App Services exist first
$apiAppExists = az webapp show -g $rg -n $apiApp --query "name" -o tsv 2>$null
$uiAppExists = az webapp show -g $rg -n $uiApp --query "name" -o tsv 2>$null

$apiKvEnv = $null
$uiKvEnv = $null

if ($apiAppExists) {
    $apiKvEnv = az webapp config appsettings list -g $rg -n $apiApp --query "[?name=='KEY_VAULT_NAME'].value" -o tsv 2>$null
} else {
    Write-Host "  ⚠️  API App Service not found: $apiApp" -ForegroundColor Yellow
}

if ($uiAppExists) {
    $uiKvEnv = az webapp config appsettings list -g $rg -n $uiApp --query "[?name=='KEY_VAULT_NAME'].value" -o tsv 2>$null
} else {
    Write-Host "  ⚠️  UI App Service not found: $uiApp" -ForegroundColor Yellow
}

if ($apiKvEnv -eq $kvName) {
    Write-Host "  ✅ API App has correct KEY_VAULT_NAME: $apiKvEnv" -ForegroundColor Green
} elseif ($apiKvEnv) {
    Write-Host "  ⚠️  API App has KEY_VAULT_NAME but value mismatch: $apiKvEnv (expected: $kvName)" -ForegroundColor Yellow
} else {
    Write-Host "  ❌ API App missing KEY_VAULT_NAME environment variable" -ForegroundColor Red
    Write-Host "  💡 Run: az webapp config appsettings set -g $rg -n $apiApp --settings KEY_VAULT_NAME=$kvName" -ForegroundColor Cyan
}

if ($uiKvEnv -eq $kvName) {
    Write-Host "  ✅ UI App has correct KEY_VAULT_NAME: $uiKvEnv" -ForegroundColor Green
} elseif ($uiKvEnv) {
    Write-Host "  ⚠️  UI App has KEY_VAULT_NAME but value mismatch: $uiKvEnv (expected: $kvName)" -ForegroundColor Yellow
} else {
    Write-Host "  ❌ UI App missing KEY_VAULT_NAME environment variable" -ForegroundColor Red
    Write-Host "  💡 Run: az webapp config appsettings set -g $rg -n $uiApp --settings KEY_VAULT_NAME=$kvName" -ForegroundColor Cyan
}

# Step 5: Check Managed Identity on App Services
Write-Host "`n[Step 5] Checking Managed Identity..." -ForegroundColor Yellow
$apiIdentity = az webapp identity show -g $rg -n $apiApp --query principalId -o tsv 2>$null
$uiIdentity = az webapp identity show -g $rg -n $uiApp --query principalId -o tsv 2>$null

if ($apiIdentity) {
    Write-Host "  ✅ API App has Managed Identity: $apiIdentity" -ForegroundColor Green
} else {
    Write-Host "  ❌ API App does not have Managed Identity" -ForegroundColor Red
    Write-Host "  💡 Run: az webapp identity assign -g $rg -n $apiApp" -ForegroundColor Cyan
}

if ($uiIdentity) {
    Write-Host "  ✅ UI App has Managed Identity: $uiIdentity" -ForegroundColor Green
} else {
    Write-Host "  ❌ UI App does not have Managed Identity" -ForegroundColor Red
    Write-Host "  💡 Run: az webapp identity assign -g $rg -n $uiApp" -ForegroundColor Cyan
}

# Step 6: Check Key Vault access policies
Write-Host "`n[Step 6] Checking Key Vault access policies..." -ForegroundColor Yellow

# Initialize policy variables
$apiPolicy = $null
$uiPolicy = $null

if ($apiIdentity) {
    $apiPolicy = az keyvault show -n $kvName -g $rg --query "properties.accessPolicies[?objectId=='$apiIdentity']" -o json 2>$null | ConvertFrom-Json
    if ($apiPolicy -and $apiPolicy.Count -gt 0) {
        $permissions = $apiPolicy[0].permissions.secrets -join ', '
        Write-Host "  ✅ API App has Key Vault access - Permissions: $permissions" -ForegroundColor Green
    } else {
        Write-Host "  ❌ API App Managed Identity does not have Key Vault access policies" -ForegroundColor Red
        Write-Host "  💡 Run: az keyvault set-policy -n $kvName --object-id $apiIdentity --secret-permissions get list" -ForegroundColor Cyan
    }
}

if ($uiIdentity) {
    $uiPolicy = az keyvault show -n $kvName -g $rg --query "properties.accessPolicies[?objectId=='$uiIdentity']" -o json 2>$null | ConvertFrom-Json
    if ($uiPolicy -and $uiPolicy.Count -gt 0) {
        $permissions = $uiPolicy[0].permissions.secrets -join ', '
        Write-Host "  ✅ UI App has Key Vault access - Permissions: $permissions" -ForegroundColor Green
    } else {
        Write-Host "  ❌ UI App Managed Identity does not have Key Vault access policies" -ForegroundColor Red
        Write-Host "  💡 Run: az keyvault set-policy -n $kvName --object-id $uiIdentity --secret-permissions get list" -ForegroundColor Cyan
    }
}

# Step 7: Check Key Vault secrets
Write-Host "`n[Step 7] Checking Key Vault secrets..." -ForegroundColor Yellow

# Initialize secrets variable
$secrets = $null

try {
    $secrets = az keyvault secret list --vault-name $kvName --query "[].name" -o json 2>$null | ConvertFrom-Json
    if ($secrets -and $secrets.Count -gt 0) {
        Write-Host "  ✅ Key Vault has $($secrets.Count) secret(s):" -ForegroundColor Green
        $secrets | ForEach-Object { Write-Host "     - $_" -ForegroundColor Gray }
    } else {
        Write-Host "  ⚠️  Key Vault is empty (no secrets)" -ForegroundColor Yellow
        Write-Host "  💡 Run: ./Resources/Azure-Deployment/populate-keyvault-secrets.ps1 -Environment $Environment" -ForegroundColor Cyan
    }
} catch {
    Write-Host "  ⚠️  Unable to list secrets (check your permissions)" -ForegroundColor Yellow
}

# Step 8: Check ASPNETCORE_ENVIRONMENT
Write-Host "`n[Step 8] Checking ASPNETCORE_ENVIRONMENT..." -ForegroundColor Yellow
$apiEnv = az webapp config appsettings list -g $rg -n $apiApp --query "[?name=='ASPNETCORE_ENVIRONMENT'].value" -o tsv 2>$null
$uiEnv = az webapp config appsettings list -g $rg -n $uiApp --query "[?name=='ASPNETCORE_ENVIRONMENT'].value" -o tsv 2>$null

$expectedEnv = switch ($Environment) {
    'dev' { 'Development' }
    'staging' { 'Staging' }
    'prod' { 'Production' }
}

if ($apiEnv -eq $expectedEnv) {
    Write-Host "  ✅ API App ASPNETCORE_ENVIRONMENT: $apiEnv" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  API App ASPNETCORE_ENVIRONMENT: $apiEnv (expected: $expectedEnv)" -ForegroundColor Yellow
}

if ($uiEnv -eq $expectedEnv) {
    Write-Host "  ✅ UI App ASPNETCORE_ENVIRONMENT: $uiEnv" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  UI App ASPNETCORE_ENVIRONMENT: $uiEnv (expected: $expectedEnv)" -ForegroundColor Yellow
}

# Step 9: Test Key Vault connectivity
Write-Host "`n[Step 9] Testing Key Vault connectivity..." -ForegroundColor Yellow
$kvUri = "https://$kvName.vault.azure.net/"
Write-Host "  🔍 Key Vault URI: $kvUri" -ForegroundColor Gray

# Try to ping the Key Vault endpoint
try {
    $response = Invoke-WebRequest -Uri $kvUri -Method Head -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
    Write-Host "  ✅ Key Vault endpoint is reachable" -ForegroundColor Green
} catch {
    if ($_.Exception.Response.StatusCode -eq 'Unauthorized' -or $_.Exception.Response.StatusCode -eq 401) {
        Write-Host "  ✅ Key Vault endpoint is reachable (401 Unauthorized is expected without credentials)" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️  Key Vault endpoint may not be reachable: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Summary
Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "DIAGNOSTIC SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

$issues = @()
if (-not $apiKvEnv -or $apiKvEnv -ne $kvName) { $issues += "API App missing or incorrect KEY_VAULT_NAME" }
if (-not $uiKvEnv -or $uiKvEnv -ne $kvName) { $issues += "UI App missing or incorrect KEY_VAULT_NAME" }
if (-not $apiIdentity) { $issues += "API App missing Managed Identity" }
if (-not $uiIdentity) { $issues += "UI App missing Managed Identity" }
if ($apiIdentity -and (-not $apiPolicy -or $apiPolicy.Count -eq 0)) { $issues += "API App Managed Identity lacks Key Vault access" }
if ($uiIdentity -and (-not $uiPolicy -or $uiPolicy.Count -eq 0)) { $issues += "UI App Managed Identity lacks Key Vault access" }
if (-not $secrets -or $secrets.Count -eq 0) { $issues += "Key Vault is empty (no secrets)" }

if ($issues.Count -eq 0) {
    Write-Host "✅ All checks passed! Key Vault configuration appears correct." -ForegroundColor Green
    Write-Host "`nIf applications still fail to start, check application logs for detailed error messages." -ForegroundColor Cyan
} else {
    Write-Host "❌ Found $($issues.Count) issue(s):" -ForegroundColor Red
    $issues | ForEach-Object { Write-Host "   - $_" -ForegroundColor Yellow }
    Write-Host "`n💡 RECOMMENDED ACTION:" -ForegroundColor Cyan
    Write-Host "   Run: ./Resources/Azure-Deployment/enable-managed-identity.ps1 -Environment $Environment" -ForegroundColor White
    Write-Host "   This will fix Managed Identity and access policy issues." -ForegroundColor Gray
    Write-Host "`n   Then run: ./Resources/Azure-Deployment/populate-keyvault-secrets.ps1 -Environment $Environment" -ForegroundColor White
    Write-Host "   This will populate required secrets in Key Vault." -ForegroundColor Gray
}

Write-Host "`n"
