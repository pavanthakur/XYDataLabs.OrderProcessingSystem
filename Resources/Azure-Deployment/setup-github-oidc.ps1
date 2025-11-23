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
    [string]$GitHubOwner = "pavanthakur",

    # Repository name
    [Parameter(Mandatory=$false)]
    [string]$Repository = "XYDataLabs.OrderProcessingSystem",

    # Optional: Role name to assign (default Contributor). Could use Website Contributor for tighter scope.
    [Parameter(Mandatory=$false)]
    [string]$RoleName = "Contributor"
)

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "GitHub Actions OIDC Setup" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

# DEBUG: Log all received parameters
Write-Host "`n[DEBUG] Parameters received by script:" -ForegroundColor Magenta
Write-Host "  Branches: '$Branches'" -ForegroundColor Gray
Write-Host "  Environments: '$Environments'" -ForegroundColor Gray
Write-Host "  GitHubOwner: '$GitHubOwner'" -ForegroundColor Gray
Write-Host "  Repository: '$Repository'" -ForegroundColor Gray
Write-Host "  AppDisplayName: '$AppDisplayName'" -ForegroundColor Gray

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

# Build list of credentials we're about to create/manage
$branchList = $Branches.Split(",", [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() } | Where-Object { $_ }
$environmentList = $Environments.Split(",", [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() } | Where-Object { $_ }

$managedCredentials = @()
foreach ($branch in $branchList) {
    $managedCredentials += "github-$($branch)-oidc"
}
foreach ($env in $environmentList) {
    $managedCredentials += "github-env-$($env)-oidc"
}

# Only delete credentials that:
# 1. Have incorrect subjects (missing repository name), AND
# 2. Are in the list of credentials we're about to manage (selected environments)
$expectedPattern = "repo:${GitHubOwner}/${Repository}"
Write-Host "  Managing credentials for: $($managedCredentials -join ', ')" -ForegroundColor Gray
Write-Host "  Checking for invalid subjects among managed credentials..." -ForegroundColor Gray

$invalidCreds = $existingCreds | Where-Object { 
    # Check if this credential is one we're managing
    $isManagedCred = $managedCredentials -contains $_.name
    # Check if it has incorrect subject
    $hasInvalidSubject = -not $_.subject.StartsWith($expectedPattern)
    # Only delete if BOTH conditions are true
    return ($isManagedCred -and $hasInvalidSubject)
}

if ($invalidCreds.Count -gt 0) {
    Write-Host "  🧹 Cleaning up $($invalidCreds.Count) invalid credential(s) for selected environments..." -ForegroundColor Yellow
    foreach ($invalidCred in $invalidCreds) {
        Write-Host "    Deleting: $($invalidCred.name) (subject: $($invalidCred.subject))" -ForegroundColor Gray
        $deleteResult = az ad app federated-credential delete --id $appObjectId --federated-credential-id $invalidCred.id 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "    Failed to delete credential: $deleteResult"
        }
    }
    # Re-fetch after cleanup
    $existingCreds = az ad app federated-credential list --id $appObjectId | ConvertFrom-Json
    if (-not $existingCreds) { $existingCreds = @() }
    Write-Host "  ✅ Cleanup complete. Total remaining credentials: $($existingCreds.Count)" -ForegroundColor Green
} else {
    Write-Host "  ✅ No invalid credentials found for selected environments" -ForegroundColor Green
    if ($existingCreds.Count -gt 0) {
        Write-Host "  ℹ️  Preserving $($existingCreds.Count) existing credential(s) for other environments" -ForegroundColor Cyan
    }
}

# Branch-based subjects (using $branchList from above)
Write-Host "  Creating branch-based credentials (GitHubOwner=$GitHubOwner, Repository=$Repository)..." -ForegroundColor Gray
foreach ($branch in $branchList) {
    $credName = "github-$($branch)-oidc"
    $subject = "repo:${GitHubOwner}/${Repository}:ref:refs/heads/${branch}"
    Write-Host "    Creating [$credName] with subject: $subject" -ForegroundColor Gray
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

# Environment-based subjects (using $environmentList from above)
Write-Host "  Creating environment-based credentials (GitHubOwner=$GitHubOwner, Repository=$Repository)..." -ForegroundColor Gray
foreach ($env in $environmentList) {
    $credName = "github-env-$($env)-oidc"
    $subject = "repo:${GitHubOwner}/${Repository}:environment:${env}"
    Write-Host "    Creating [$credName] with subject: $subject" -ForegroundColor Gray
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

# Step 5: Assign Contributor role to subscription (required for OIDC login)
Write-Host "`n[5/7] Assigning $RoleName role..." -ForegroundColor Yellow

# First, assign role at subscription level (required for Azure login to work)
Write-Host "  Assigning $RoleName at subscription level..." -ForegroundColor Cyan
$subscriptionScope = "/subscriptions/$subscriptionId"
$existingSubAssignment = az role assignment list --assignee $spObjectId --role $RoleName --scope $subscriptionScope | ConvertFrom-Json
if (-not $existingSubAssignment -or $existingSubAssignment.Count -eq 0) {
    try {
        az role assignment create --assignee $spObjectId --role $RoleName --scope $subscriptionScope 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    ✅ Assigned $RoleName at subscription level" -ForegroundColor Green
        } else {
            Write-Host "    ⚠️  Failed to assign $RoleName at subscription level" -ForegroundColor Yellow
            Write-Host "    You may need higher permissions. Service principal may not be able to login until this is fixed." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "    ⚠️  Exception assigning subscription role: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "    ✅ $RoleName already assigned at subscription level" -ForegroundColor Green
}

# Resolve RG list
$rgList = @()
if ($ResourceGroupNames) {
    $rgList = $ResourceGroupNames.Split(',', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}
elseif ($ResourceGroupName) {
    $rgList = @($ResourceGroupName)
}
else {
    Write-Host "  ℹ️  No resource groups specified - only subscription-level RBAC assigned." -ForegroundColor Cyan
    Write-Host "  💡 Resource groups will be created during bootstrap with inherited permissions." -ForegroundColor Cyan
    $rgList = @()
}

$rbacSummary = @()
if ($rgList.Count -gt 0) {
    Write-Host "`n  Assigning $RoleName to specific resource groups..." -ForegroundColor Cyan
    foreach ($rg in $rgList) {
        Write-Host "    Processing RG: $rg" -ForegroundColor Gray
        # Validate RG exists
        $rgExists = az group exists -n $rg 2>$null
        if ($rgExists -ne 'true') {
            Write-Host "      Skipping (RG not found)" -ForegroundColor Yellow
            $rbacSummary += [PSCustomObject]@{ ResourceGroup=$rg; Status='NotFound'; Role=$RoleName }
            continue
        }
        $scope = "/subscriptions/$subscriptionId/resourceGroups/$rg"
        $existingAssignment = az role assignment list --assignee $spObjectId --role $RoleName --scope $scope | ConvertFrom-Json
        if (-not $existingAssignment -or $existingAssignment.Count -eq 0) {
            az role assignment create --assignee $spObjectId --role $RoleName --scope $scope | Out-Null
            Write-Host "      ✅ Assigned $RoleName" -ForegroundColor Green
            $rbacSummary += [PSCustomObject]@{ ResourceGroup=$rg; Status='Assigned'; Role=$RoleName }
        } else {
            Write-Host "      Already assigned" -ForegroundColor Gray
            $rbacSummary += [PSCustomObject]@{ ResourceGroup=$rg; Status='Exists'; Role=$RoleName }
        }
    }

    Write-Host "`n  Resource Group RBAC Summary:" -ForegroundColor Yellow
    $rbacSummary | Format-Table -AutoSize
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
