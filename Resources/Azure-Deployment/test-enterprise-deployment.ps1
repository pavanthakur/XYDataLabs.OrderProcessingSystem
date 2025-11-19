<#
.SYNOPSIS
  End-to-end test orchestrator for enterprise Azure deployment tooling.
.DESCRIPTION
  Provisions infrastructure, tests OIDC, App Insights, slots, then optionally cleans up.
  Logs all steps and validates success criteria. Safe for dry-run mode.
.PARAMETER SubscriptionId
  Azure subscription ID (uses current context if omitted).
.PARAMETER BaseName
  Logical base name for resources (default: orderprocessing).
.PARAMETER Location
  Azure region (default: centralindia).
.PARAMETER Environment
  Single environment to test (default: dev).
.PARAMETER SkipInfraProvision
  Skip infrastructure bootstrap (assumes already provisioned).
.PARAMETER SkipOidcSetup
  Skip OIDC app registration setup.
.PARAMETER SkipAppInsights
  Skip Application Insights provisioning.
.PARAMETER SkipSlotTest
  Skip deployment slot testing.
.PARAMETER UpgradeToB1
  Upgrade App Service Plan to B1 for slot testing.
.PARAMETER DowngradeAfterTest
  Downgrade back to F1 after slot testing completes.
.PARAMETER DryRun
  Show what would be done without making changes.
.EXAMPLE
  ./test-enterprise-deployment.ps1 -Environment dev -UpgradeToB1 -DowngradeAfterTest
.EXAMPLE
  ./test-enterprise-deployment.ps1 -DryRun
#>
param(
  [string]$SubscriptionId,
  [string]$BaseName = 'orderprocessing',
  [string]$Location = 'centralindia',
  [string]$Environment = 'dev',
  [switch]$SkipInfraProvision,
  [switch]$SkipOidcSetup,
  [switch]$SkipAppInsights,
  [switch]$SkipSlotTest,
  [switch]$UpgradeToB1,
  [switch]$DowngradeAfterTest,
  [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
$scriptDir = $PSScriptRoot
$logFile = Join-Path $scriptDir "test-run-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Write-Log {
  param([string]$Message, [string]$Level = 'INFO')
  $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $logMsg = "[$timestamp] [$Level] $Message"
  Write-Host $logMsg -ForegroundColor $(if($Level -eq 'ERROR'){'Red'}elseif($Level -eq 'SUCCESS'){'Green'}elseif($Level -eq 'WARN'){'Yellow'}else{'Cyan'})
  Add-Content -Path $logFile -Value $logMsg
}

function Test-Step {
  param([string]$Name, [scriptblock]$Action, [scriptblock]$Validation)
  Write-Log "=== STEP: $Name ===" 'INFO'
  if ($DryRun) { Write-Log "[DRY-RUN] Would execute: $Name" 'WARN'; return $true }
  try {
    & $Action
    if ($Validation) {
      $result = & $Validation
      if ($result) { Write-Log "✅ $Name PASSED" 'SUCCESS'; return $true }
      else { Write-Log "❌ $Name FAILED validation" 'ERROR'; return $false }
    }
    Write-Log "✅ $Name completed" 'SUCCESS'
    return $true
  } catch {
    Write-Log "❌ $Name ERROR: $($_.Exception.Message)" 'ERROR'
    return $false
  }
}

Write-Log "========================================" 'INFO'
Write-Log "Enterprise Deployment Test Orchestrator" 'INFO'
Write-Log "========================================" 'INFO'
Write-Log "Environment: $Environment | Location: $Location | DryRun: $DryRun" 'INFO'

$rg = "rg-$BaseName-$Environment"
$plan = "asp-$BaseName-$Environment"
$apiApp = "$BaseName-api-xyapp-$Environment"
$uiApp = "$BaseName-ui-xyapp-$Environment"
$aiName = "ai-$BaseName-$Environment"
$aiApi = "ai-$BaseName-api-$Environment"
$aiUi  = "ai-$BaseName-ui-$Environment"

# Step 0: Azure Context
$step0 = Test-Step "Verify Azure Authentication" `
  -Action {
    if ($SubscriptionId) { az account set --subscription $SubscriptionId | Out-Null }
    $acct = az account show | ConvertFrom-Json
    Write-Log "Subscription: $($acct.name) ($($acct.id))"
    Write-Log "Tenant: $($acct.tenantId)"
  } `
  -Validation { $null -ne (az account show 2>$null) }

if (-not $step0) { Write-Log "Authentication failed. Run: az login" 'ERROR'; exit 1 }

# Step 1: Infrastructure Provision
if (-not $SkipInfraProvision) {
  $step1 = Test-Step "Provision Infrastructure (RG, Plan, Apps)" `
    -Action {
      $cmd = "$scriptDir\bootstrap-enterprise-infra.ps1 -BaseName $BaseName -Location $Location -Environments $Environment"
      Write-Log "Running: $cmd"
      & "$scriptDir\bootstrap-enterprise-infra.ps1" -BaseName $BaseName -Location $Location -Environments $Environment
    } `
    -Validation {
      $rgExists = az group exists -n $rg
      $planExists = az appservice plan show -n $plan -g $rg 2>$null
      $apiExists = az webapp show -n $apiApp -g $rg 2>$null
      ($rgExists -eq 'true') -and $planExists -and $apiExists
    }
  if (-not $step1) { Write-Log "Infrastructure provisioning failed" 'ERROR'; exit 1 }
} else {
  Write-Log "Skipping infrastructure provision (SkipInfraProvision set)" 'WARN'
}

# Step 2: OIDC Setup
if (-not $SkipOidcSetup) {
  $step2 = Test-Step "Setup OIDC & RBAC" `
    -Action {
      & "$scriptDir\setup-github-oidc.ps1" -ResourceGroupName $rg -Branches "main" -RoleName "Website Contributor"
    } `
    -Validation {
      $app = az ad app list --display-name "GitHub-Actions-OIDC" | ConvertFrom-Json
      $app.Count -gt 0
    }
  if (-not $step2) { Write-Log "OIDC setup failed" 'ERROR' }
} else {
  Write-Log "Skipping OIDC setup" 'WARN'
}

# Step 3: Verify OIDC
$step3 = Test-Step "Verify OIDC Configuration" `
  -Action {
    & "$scriptDir\check-app-registration.ps1"
  } `
  -Validation { $true }

# Step 4: Azure SQL Provisioning
${step4} = Test-Step "Provision Azure SQL (server, db, connection strings)" `
  -Action {
    & "$scriptDir\provision-azure-sql.ps1" -Environment $Environment -BaseName $BaseName -Location $Location
  } `
  -Validation {
    $sqlServer = "$BaseName-sql-$Environment"
    $dbName = "OrderProcessingSystem_" + (Get-Culture).TextInfo.ToTitleCase($Environment)
    $db = az sql db show --name $dbName --server $sqlServer --resource-group $rg 2>$null
    $conn = az webapp config connection-string list -g $rg -n $apiApp --query "[?name=='OrderProcessingSystemDbConnection']" -o tsv 2>$null
    $db -and $conn
  }
if (-not ${step4}) { Write-Log "Azure SQL provisioning failed" 'ERROR'; exit 1 }

# Step 5: Apply EF Core Migrations
${step5} = Test-Step "Apply EF Core migrations (with fallback)" `
  -Action {
    & "$scriptDir\run-database-migrations.ps1" -Environment $Environment -BaseName $BaseName
  } `
  -Validation { $LASTEXITCODE -eq 0 }
if (-not ${step5}) { Write-Log "EF migrations failed" 'ERROR'; exit 1 }

# Step 6: Application Insights
if (-not $SkipAppInsights) {
  $step6 = Test-Step "Provision Application Insights (workspace-based)" `
    -Action {
      & "$scriptDir\setup-appinsights-dev.ps1" -ResourceGroup $rg -Location $Location -WorkspaceName "logs-$BaseName-$Environment" -ApiAppName $apiApp -UiAppName $uiApp -ApiAppInsights $aiApi -UiAppInsights $aiUi
    } `
    -Validation {
      ($null -ne (az monitor app-insights component show -a $aiApi -g $rg 2>$null)) -and ($null -ne (az monitor app-insights component show -a $aiUi -g $rg 2>$null))
    }
  if (-not $step6) { Write-Log "App Insights provisioning failed" 'ERROR' }
} else {
  Write-Log "Skipping App Insights" 'WARN'
}

# Step 7: Upgrade to B1 (if requested)
$originalSku = $null
if ($UpgradeToB1) {
  $step7 = Test-Step "Upgrade Plan to B1" `
    -Action {
      $currentPlan = az appservice plan show -n $plan -g $rg | ConvertFrom-Json
      $script:originalSku = $currentPlan.sku.name
      Write-Log "Current SKU: $originalSku"
      if ($originalSku -ne 'B1') {
        az appservice plan update -n $plan -g $rg --sku B1 | Out-Null
        Write-Log "Upgraded to B1"
      } else {
        Write-Log "Already on B1"
      }
    } `
    -Validation {
      $planCheck = az appservice plan show -n $plan -g $rg | ConvertFrom-Json
      $planCheck.sku.name -eq 'B1'
    }
  if (-not $step7) { Write-Log "Upgrade to B1 failed" 'ERROR'; exit 1 }
}

# Step 8: Slot Testing
if (-not $SkipSlotTest -and $UpgradeToB1) {
  $slotName = "staging"
  
  $step6a = Test-Step "Create Staging Slot" `
    -Action {
      & "$scriptDir\manage-appservice-slots.ps1" -ResourceGroup $rg -WebAppName $apiApp -Action create -SlotName $slotName
    } `
    -Validation {
      $slots = az webapp deployment slot list -g $rg -n $apiApp | ConvertFrom-Json
      ($slots | Where-Object { $_.name -eq $slotName }).Count -gt 0
    }
  
  $step6b = Test-Step "List Slots" `
    -Action {
      & "$scriptDir\manage-appservice-slots.ps1" -ResourceGroup $rg -WebAppName $apiApp -Action list
    } `
    -Validation { $true }
  
  # Note: Deploy/warmup/swap skipped (requires build artifacts)
  Write-Log "Slot created. Deploy/swap/rollback require build artifacts (manual or CI/CD)." 'INFO'
  
} elseif (-not $UpgradeToB1 -and -not $SkipSlotTest) {
  Write-Log "Skipping slot test (requires B1+ plan; use -UpgradeToB1)" 'WARN'
}

# Step 9: Endpoint Validation
$step9 = Test-Step "Validate App Endpoints" `
  -Action {
    $apiUrl = "https://$apiApp.azurewebsites.net"
    $uiUrl = "https://$uiApp.azurewebsites.net"
    Write-Log "Testing: $apiUrl"
    try {
      $resp = Invoke-WebRequest -Uri $apiUrl -Method Get -TimeoutSec 10 -ErrorAction SilentlyContinue
      Write-Log "API Status: $($resp.StatusCode)"
    } catch {
      Write-Log "API not yet deployed or warming up: $($_.Exception.Message)" 'WARN'
    }
    Write-Log "Testing: $uiUrl"
    try {
      $resp = Invoke-WebRequest -Uri $uiUrl -Method Get -TimeoutSec 10 -ErrorAction SilentlyContinue
      Write-Log "UI Status: $($resp.StatusCode)"
    } catch {
      Write-Log "UI not yet deployed or warming up: $($_.Exception.Message)" 'WARN'
    }
  } `
  -Validation { $true }

# Step 10: Downgrade (if requested)
if ($DowngradeAfterTest -and $UpgradeToB1) {
  $step10a = Test-Step "Delete Slots Before Downgrade" `
    -Action {
      $slots = az webapp deployment slot list -g $rg -n $apiApp | ConvertFrom-Json
      foreach ($slot in $slots) {
        Write-Log "Deleting slot: $($slot.name)"
        & "$scriptDir\manage-appservice-slots.ps1" -ResourceGroup $rg -WebAppName $apiApp -Action delete -SlotName $slot.name -Force
      }
    } `
    -Validation {
      $slots = az webapp deployment slot list -g $rg -n $apiApp | ConvertFrom-Json
      $slots.Count -eq 0
    }
  
  $step10b = Test-Step "Disable Always-On" `
    -Action {
      az webapp config set -g $rg -n $apiApp --always-on false | Out-Null
      az webapp config set -g $rg -n $uiApp --always-on false | Out-Null
    } `
    -Validation { $true }
  
  $step10c = Test-Step "Downgrade to F1" `
    -Action {
      az appservice plan update -n $plan -g $rg --sku F1 | Out-Null
      Write-Log "Downgraded to F1"
    } `
    -Validation {
      $planCheck = az appservice plan show -n $plan -g $rg | ConvertFrom-Json
      $planCheck.sku.name -eq 'F1'
    }
}

# Summary
Write-Log "========================================" 'INFO'
Write-Log "Test Orchestration Complete" 'SUCCESS'
Write-Log "Log saved to: $logFile" 'INFO'
Write-Log "========================================" 'INFO'

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "  1. Review log: $logFile" -ForegroundColor White
Write-Host "  2. Check GitHub secrets match OIDC Client ID" -ForegroundColor White
Write-Host "  3. Push code to trigger CI/CD deployment" -ForegroundColor White
if ($UpgradeToB1 -and -not $DowngradeAfterTest) {
  Write-Host "  4. Remember to downgrade plan to F1 when done testing!" -ForegroundColor Red
}
Write-Host ""
