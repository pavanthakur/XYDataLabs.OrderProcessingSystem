# GitHub Actions OIDC Setup for Azure App Service Deployment
# Run this script once to configure federated identity credentials
#
# IMPORTANT: After running this script, you MUST:
# 1. Add the three secrets to GitHub repository secrets (Settings → Secrets and variables → Actions)
# 2. The federated credential is configured for the 'main' branch
#
# For complete instructions, see: Documentation/02-Azure-Learning-Guides/AZURE_DEPLOYMENT_GUIDE.md

param(
    # Single resource group (backward compatible). Use -ResourceGroupNames for multiple.
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName,

    # Comma-separated list of RGs for multi-environment RBAC assignment
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupNames,

    [Parameter(Mandatory=$false)]
    [string]$AppDisplayName = "GitHub-Actions-OIDC",

    # Comma-separated list of branches to create branch-based federated credentials for
    [Parameter(Mandatory=$false)]
    [string]$Branches = "main",

    # Comma-separated list of GitHub environment names to create environment-based federated credentials for (optional)
    [Parameter(Mandatory=$false)]
    [string]$Environments = "",

    # GitHub organization or username owning the repository
    [Parameter(Mandatory=$false)]
    [string]$GitHubOwner = "getpavanthakur",

    # Repository name
    [Parameter(Mandatory=$false)]
    [string]$Repository = "TestAppXY_OrderProcessingSystem",

    # Optional: Role name to assign (default Contributor). Could use Website Contributor for tighter scope.
    [Parameter(Mandatory=$false)]
    [string]$RoleName = "Contributor"
)

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "GitHub Actions OIDC Setup" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

# Step 1: Get current Azure context
Write-Host "`n[1/7] Getting Azure subscription details..." -ForegroundColor Yellow
$subscription = az account show | ConvertFrom-Json
$subscriptionId = $subscription.id
$tenantId = $subscription.tenantId

Write-Host "  Subscription: $($subscription.name)" -ForegroundColor Green
Write-Host "  Tenant ID: $tenantId" -ForegroundColor Green
Write-Host "  Subscription ID: $subscriptionId" -ForegroundColor Green

# Step 2: Check if app registration exists
Write-Host "`n[2/7] Checking for existing app registration..." -ForegroundColor Yellow
$existingApp = az ad app list --display-name $AppDisplayName | ConvertFrom-Json

if ($existingApp.Count -gt 0) {
    Write-Host "  Found existing app: $AppDisplayName" -ForegroundColor Green
    $appId = $existingApp[0].appId
    $appObjectId = $existingApp[0].id
} else {
    Write-Host "  Creating new app registration..." -ForegroundColor Yellow
    $newApp = az ad app create --display-name $AppDisplayName | ConvertFrom-Json
    $appId = $newApp.appId
    $appObjectId = $newApp.id
    Write-Host "  Created app: $AppDisplayName" -ForegroundColor Green
}

Write-Host "  App (Client) ID: $appId" -ForegroundColor Green
Write-Host "  Object ID: $appObjectId" -ForegroundColor Green

# Step 3: Create service principal if not exists
Write-Host "`n[3/7] Checking for service principal..." -ForegroundColor Yellow
$existingSp = az ad sp list --filter "appId eq '$appId'" | ConvertFrom-Json

if ($existingSp.Count -eq 0) {
    Write-Host "  Creating service principal..." -ForegroundColor Yellow
    $sp = az ad sp create --id $appId | ConvertFrom-Json
    $spObjectId = $sp.id
    Write-Host "  Service principal created" -ForegroundColor Green
} else {
    $spObjectId = $existingSp[0].id
    Write-Host "  Service principal already exists" -ForegroundColor Green
}

# Step 4: Configure federated credentials
Write-Host "`n[4/7] Configuring federated credentials..." -ForegroundColor Yellow

$existingCreds = az ad app federated-credential list --id $appObjectId | ConvertFrom-Json
if (-not $existingCreds) { $existingCreds = @() }

# Delete credentials with incorrect subjects (missing repository name)
$invalidCreds = $existingCreds | Where-Object { $_.subject -notmatch "repo:$GitHubOwner/$Repository:" }
if ($invalidCreds.Count -gt 0) {
    Write-Host "  🧹 Cleaning up $($invalidCreds.Count) invalid federated credentials..." -ForegroundColor Yellow
    foreach ($invalidCred in $invalidCreds) {
        Write-Host "    Deleting: $($invalidCred.name) (subject: $($invalidCred.subject))" -ForegroundColor Gray
        az ad app federated-credential delete --id $appObjectId --federated-credential-id $invalidCred.id 2>$null | Out-Null
    }
    # Re-fetch after cleanup
    $existingCreds = az ad app federated-credential list --id $appObjectId | ConvertFrom-Json
    if (-not $existingCreds) { $existingCreds = @() }
}

# Branch-based subjects
$branchList = $Branches.Split(",", [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() } | Where-Object { $_ }
foreach ($branch in $branchList) {
    $credName = "github-$($branch)-oidc"
    $subject = "repo:$GitHubOwner/$Repository:ref:refs/heads/$branch"
    $exists = $existingCreds | Where-Object { $_.name -eq $credName -and $_.subject -eq $subject }
    if ($exists) {
        Write-Host "  [$credName] Already exists (branch: $branch)" -ForegroundColor Green
        continue
    }
    $credentialJson = @{
        name = $credName
        issuer = "https://token.actions.githubusercontent.com"
        subject = $subject
        audiences = @("api://AzureADTokenExchange")
    } | ConvertTo-Json
    $tempFile = [System.IO.Path]::GetTempFileName()
    $credentialJson | Out-File -FilePath $tempFile -Encoding UTF8
    az ad app federated-credential create --id $appObjectId --parameters $tempFile | Out-Null
    Remove-Item $tempFile -ErrorAction SilentlyContinue
    Write-Host "  [$credName] Created (branch: $branch)" -ForegroundColor Cyan
}

# Environment-based subjects
$envList = $Environments.Split(",", [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() } | Where-Object { $_ }
foreach ($env in $envList) {
    $credName = "github-env-$($env)-oidc"
    $subject = "repo:$GitHubOwner/$Repository:environment:$env"
    $exists = $existingCreds | Where-Object { $_.name -eq $credName -and $_.subject -eq $subject }
    if ($exists) {
        Write-Host "  [$credName] Already exists (environment: $env)" -ForegroundColor Green
        continue
    }
    $credentialJson = @{
        name = $credName
        issuer = "https://token.actions.githubusercontent.com"
        subject = $subject
        audiences = @("api://AzureADTokenExchange")
    } | ConvertTo-Json
    $tempFile = [System.IO.Path]::GetTempFileName()
    $credentialJson | Out-File -FilePath $tempFile -Encoding UTF8
    az ad app federated-credential create --id $appObjectId --parameters $tempFile | Out-Null
    Remove-Item $tempFile -ErrorAction SilentlyContinue
    Write-Host "  [$credName] Created (environment: $env)" -ForegroundColor Cyan
}

if ($branchList.Count -eq 0 -and $envList.Count -eq 0) {
    Write-Host "  No federated credentials requested (Branches/Environments empty)." -ForegroundColor Yellow
}

# Step 5: Assign Contributor role to resource group
Write-Host "`n[5/7] Assigning $RoleName role..." -ForegroundColor Yellow

# Resolve RG list
$rgList = @()
if ($ResourceGroupNames) {
    $rgList = $ResourceGroupNames.Split(',', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}
elseif ($ResourceGroupName) {
    $rgList = @($ResourceGroupName)
}
else {
    Write-Host "  ⚠️  No resource groups specified - RBAC assignment will be skipped." -ForegroundColor Yellow
    Write-Host "  💡 Resource groups will be created during bootstrap. RBAC will be assigned then." -ForegroundColor Cyan
    $rgList = @()
}

$rbacSummary = @()
if ($rgList.Count -gt 0) {
    foreach ($rg in $rgList) {
        Write-Host "  Processing RG: $rg" -ForegroundColor Cyan
        # Validate RG exists
        $rgExists = az group exists -n $rg 2>$null
        if ($rgExists -ne 'true') {
            Write-Host "    Skipping (RG not found)" -ForegroundColor Yellow
            $rbacSummary += [PSCustomObject]@{ ResourceGroup=$rg; Status='NotFound'; Role=$RoleName }
            continue
        }
        $scope = "/subscriptions/$subscriptionId/resourceGroups/$rg"
        $existingAssignment = az role assignment list --assignee $spObjectId --role $RoleName --scope $scope | ConvertFrom-Json
        if (-not $existingAssignment -or $existingAssignment.Count -eq 0) {
            az role assignment create --assignee $spObjectId --role $RoleName --scope $scope | Out-Null
            Write-Host "    Assigned $RoleName" -ForegroundColor Green
            $rbacSummary += [PSCustomObject]@{ ResourceGroup=$rg; Status='Assigned'; Role=$RoleName }
        } else {
            Write-Host "    Already assigned" -ForegroundColor Gray
            $rbacSummary += [PSCustomObject]@{ ResourceGroup=$rg; Status='Exists'; Role=$RoleName }
        }
    }

    Write-Host "`n  RBAC Summary:" -ForegroundColor Yellow
    $rbacSummary | Format-Table -AutoSize
} else {
    Write-Host "  No resource groups to process - RBAC assignment skipped." -ForegroundColor Gray
}

# Step 6: Display GitHub Secrets
Write-Host "`n[6/7] GitHub Repository Secrets Configuration" -ForegroundColor Yellow
Write-Host "  Add these secrets to: https://github.com/getpavanthakur/TestAppXY_OrderProcessingSystem/settings/secrets/actions" -ForegroundColor Cyan
Write-Host ""
Write-Host "  AZUREAPPSERVICE_CLIENTID:        $appId" -ForegroundColor White
Write-Host "  AZUREAPPSERVICE_TENANTID:        $tenantId" -ForegroundColor White
Write-Host "  AZUREAPPSERVICE_SUBSCRIPTIONID:  $subscriptionId" -ForegroundColor White
Write-Host ""

# Step 7: Copy to clipboard (optional)
Write-Host "[7/7] Setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Add the secrets above to GitHub repository secrets:" -ForegroundColor White
Write-Host "     https://github.com/getpavanthakur/TestAppXY_OrderProcessingSystem/settings/secrets/actions" -ForegroundColor Cyan
Write-Host "     GitHub → Settings → Secrets and variables → Actions → New repository secret" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Update workflow files to include branches/environments you just configured (if not already)." -ForegroundColor White
Write-Host "  3. Run the workflow manually or push changes to a configured branch to trigger deployment." -ForegroundColor White
Write-Host "  4. (Optional) Re-run with -ResourceGroupNames to grant RBAC for additional environments." -ForegroundColor White
Write-Host "     https://github.com/getpavanthakur/TestAppXY_OrderProcessingSystem/actions" -ForegroundColor Cyan
Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan

# Export values for easy copy
$output = @"

=== COPY THESE VALUES TO GITHUB SECRETS ===

AZUREAPPSERVICE_CLIENTID:        $appId
AZUREAPPSERVICE_TENANTID:        $tenantId
AZUREAPPSERVICE_SUBSCRIPTIONID:  $subscriptionId

===========================================
"@

$output | Set-Clipboard -ErrorAction SilentlyContinue
Write-Host "Secrets copied to clipboard!" -ForegroundColor Green
