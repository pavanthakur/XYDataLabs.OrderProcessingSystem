<#
.SYNOPSIS
  Bootstrap enterprise-grade Azure infra: Resource Groups, AppService Plans and WebApps (API + UI) + GitHub OIDC.
.DESCRIPTION
  Merged/finalized script (consolidates orig, draft, and before-final). Includes logging, retry helpers, "super-retry" webapp create, post-deploy self-test and OIDC + RBAC setup.
.PARAMETER SubscriptionId
  Optional: Azure subscription id to operate in.
.PARAMETER BaseName
  Base name for resources (default: 'orderprocessing').
.PARAMETER Location
  Azure region for resources (default: 'centralindia').
.PARAMETER Environment
  Target environment: 'dev', 'stg', or 'prod' (required).
.PARAMETER ApiSuffix
  API suffix for web app names (default: 'api-xyapp').
.PARAMETER UiSuffix
  UI suffix for web app names (default: 'ui-xyapp').
.PARAMETER DevSku
  Plan sku for dev (default 'F1')
.PARAMETER StagingSku
  Plan sku for staging (default 'B1')
.PARAMETER ProductionSku
  Plan sku for production (default 'P1v3')
.PARAMETER GitHubOwner
  GitHub repository owner/organization name (default 'pavanthakur')
#>

param(
    [Parameter(Mandatory = $false)] [string]$SubscriptionId,
    [Parameter(Mandatory = $false)] [string]$BaseName = 'orderprocessing',
    [Parameter(Mandatory = $false)] [string]$Location = 'centralindia',
    [Parameter(Mandatory = $true)] [ValidateSet('dev','stg','prod')] [string]$Environment,
    [Parameter(Mandatory = $false)] [string]$ApiSuffix = 'api-xyapp',
    [Parameter(Mandatory = $false)] [string]$UiSuffix = 'ui-xyapp',
    [Parameter(Mandatory = $false)] [string]$DevSku = 'F1',
    [Parameter(Mandatory = $false)] [string]$StagingSku = 'B1',
    [Parameter(Mandatory = $false)] [string]$ProductionSku = 'P1v3',
    [Parameter(Mandatory = $false)] [string]$GitHubOwner = 'pavanthakur',
    [Parameter(Mandatory = $false)] [switch]$DryRun,
    [Parameter(Mandatory = $false)] [ValidateSet('text','json')] [string]$LogFormat = 'text'
)

# Repository name (fixed for this project)
$GitHubRepo = 'TestAppXY_OrderProcessingSystem'

# Structured logging support
$global:BootstrapLog = @()
function Add-LogEntry {
    param([string]$Phase,[string]$Action,[string]$Status,[string]$Detail="")
    if ($LogFormat -eq 'json') {
        $global:BootstrapLog += [PSCustomObject]@{ timestamp=(Get-Date).ToString('o'); phase=$Phase; action=$Action; status=$Status; detail=$Detail }
    }
}

Add-LogEntry -Phase 'init' -Action 'start' -Status 'ok' -Detail "env=$Environment;location=$Location"

# Dry-run mode: compute planned names and exit before changes
if ($DryRun) {
    $rg     = "rg-$BaseName-$Environment"
    $plan   = "asp-$BaseName-$Environment"
    $apiApp = "$GitHubOwner-$BaseName-$ApiSuffix-$Environment"
    $uiApp  = "$GitHubOwner-$BaseName-$UiSuffix-$Environment"
    $aiName = "ai-$BaseName-$Environment"
    Write-Host "=== DRY RUN PLAN ===" -ForegroundColor Cyan
    Write-Host "Resource Group : $rg" -ForegroundColor Gray
    Write-Host "App Service Plan: $plan (SKU: $(switch($Environment){'dev'{$DevSku};'stg'{$StagingSku};'prod'{$ProductionSku}}))" -ForegroundColor Gray
    Write-Host "API WebApp      : $apiApp" -ForegroundColor Gray
    Write-Host "UI WebApp       : $uiApp" -ForegroundColor Gray
    Write-Host "App Insights    : $aiName" -ForegroundColor Gray
    Write-Host "OIDC App        : GitHub-Actions-OIDC (branches: dev, stg, main)" -ForegroundColor Gray
    Add-LogEntry -Phase 'plan' -Action 'dry-run' -Status 'ok' -Detail "rg=$rg;plan=$plan;api=$apiApp;ui=$uiApp;ai=$aiName"
    if ($LogFormat -eq 'json') {
        $dryLog = Join-Path $PSScriptRoot "logs/bootstrap-dryrun-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        $global:BootstrapLog | ConvertTo-Json -Depth 4 | Out-File $dryLog -Encoding UTF8
        Write-Host "JSON log written: $dryLog" -ForegroundColor Green
    }
    Write-Host "=== DRY RUN COMPLETE ===" -ForegroundColor Cyan
    return
}

# Logging directory and file
$logDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$logFile = Join-Path $logDir ("bootstrap-" + (Get-Date -Format "yyyy-MM-dd-HH-mm-ss") + ".log")

function Write-Log {
    param([string]$Message, [string]$Level = "INFO", [ConsoleColor]$Color = "White")
    $ts = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    $entry = "$ts [$Level] $Message"
    try { Write-Host $entry -ForegroundColor $Color } catch { Write-Output $entry }
    try { Add-Content -Path $logFile -Value $entry } catch {}
}

Write-Log "=== Bootstrap started ===" "INFO" "Cyan"

# Super retry synchronous webapp creation helper
function New-WebAppWithSuperRetry {
    param([string]$ResourceGroup, [string]$PlanName, [string]$AppName, [int]$MaxAttempts = 5, [int]$InitialWaitMinutes = 2, [int]$RetryDelaySeconds = 60)
    $lastErr = $null
    # Try Azure CLI first, fallback to PowerShell REST API
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        Write-Log "Creating WebApp '$AppName' (Attempt $i/$MaxAttempts)..." "INFO" "Yellow"
        
        if ($i -le 2) {
            # Try Azure CLI first
            $result = az webapp create -g $ResourceGroup -p $PlanName -n $AppName --runtime "dotnet:8" 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "WebApp '$AppName' created via Azure CLI - waiting ${InitialWaitMinutes} minutes..." "INFO" "Cyan"
                Write-Host "  [WAIT] Allowing Azure time to provision webapp (${InitialWaitMinutes} min)..." -ForegroundColor Yellow
                $waitSeconds = $InitialWaitMinutes * 60
                $checkInterval = 30
                $elapsed = 0
                Write-Host "  [PROGRESS] [" -NoNewline -ForegroundColor Cyan
                while ($elapsed -lt $waitSeconds) {
                    Start-Sleep -Seconds $checkInterval
                    $elapsed += $checkInterval
                    Write-Host "#" -NoNewline -ForegroundColor Green
                }
                Write-Host "]" -ForegroundColor Cyan
                return @{ Success = $true; Output = $result }
            } else {
                $lastErr = $result
                Write-Log "Attempt $i (Azure CLI) failed: $result" "WARN" "Yellow"
            }
        } else {
            # Fallback to PowerShell REST API
            try {
                Write-Log "Attempting via PowerShell REST API..." "INFO" "Cyan"
                $token = az account get-access-token --query accessToken -o tsv
                $subscription = az account show --query id -o tsv
                $headers = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" }
                $serverFarmId = "/subscriptions/$subscription/resourceGroups/$ResourceGroup/providers/Microsoft.Web/serverfarms/$PlanName"
                $body = @{
                    location = "centralindia"
                    kind = "app"
                    properties = @{
                        serverFarmId = $serverFarmId
                        reserved = $false
                        siteConfig = @{ netFrameworkVersion = "v8.0" }
                    }
                } | ConvertTo-Json -Depth 10
                $uri = "https://management.azure.com/subscriptions/$subscription/resourceGroups/$ResourceGroup/providers/Microsoft.Web/sites/${AppName}?api-version=2023-12-01"
                $result = Invoke-RestMethod -Method Put -Uri $uri -Headers $headers -Body $body
                Write-Log "WebApp '$AppName' created via REST API - waiting ${InitialWaitMinutes} minutes..." "INFO" "Green"
                Write-Host "  [WAIT] Allowing Azure time to provision webapp (${InitialWaitMinutes} min)..." -ForegroundColor Yellow
                $waitSeconds = $InitialWaitMinutes * 60
                $checkInterval = 30
                $elapsed = 0
                Write-Host "  [PROGRESS] [" -NoNewline -ForegroundColor Cyan
                while ($elapsed -lt $waitSeconds) {
                    Start-Sleep -Seconds $checkInterval
                    $elapsed += $checkInterval
                    Write-Host "#" -NoNewline -ForegroundColor Green
                }
                Write-Host "]" -ForegroundColor Cyan
                return @{ Success = $true; Output = $result }
            } catch {
                $lastErr = $_.Exception.Message
                Write-Log "Attempt $i (REST API) failed: $lastErr" "WARN" "Yellow"
            }
        }
        
        if ($i -lt $MaxAttempts) {
            Write-Host "  [RETRY] Waiting $RetryDelaySeconds seconds before retry..." -ForegroundColor Yellow
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
    return @{ Success = $false; Error = $lastErr }
}

# Post-deploy self-test
function Test-WebEndpoint {
    param([string]$Url, [string]$Name)
    try {
        $r = Invoke-WebRequest -Uri $Url -TimeoutSec 10 -ErrorAction Stop
        Write-Log "[TEST] $Name responded HTTP $($r.StatusCode)" "INFO" "Green"
        return $true
    } catch {
        Write-Log "[TEST] $Name not responding: $($_.Exception.Message)" "WARN" "Red"
        return $false
    }
}

# Ensure Add-StepStatus exists
if (-not (Get-Command Add-StepStatus -ErrorAction SilentlyContinue)) {
    function Add-StepStatus { param([string]$Name,[string]$Status,[string]$Details=""); $global:StepStatus += [PSCustomObject]@{Name=$Name;Status=$Status;Details=$Details} }
}

$scriptStartTime = Get-Date
Write-Host "[INFO] Bootstrap started at: $scriptStartTime" -ForegroundColor Cyan

$global:StepStatus = @()
function Add-StepStatus {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Details = ""
    )
    $global:StepStatus += [PSCustomObject]@{
        Name    = $Name
        Status  = $Status
        Details = $Details
    }
}

function Resolve-Sku($env) {
    switch ($env) {
        'dev' { return $DevSku }
        'stg' { return $StagingSku }
        'prod' { return $ProductionSku }
        default { return $DevSku }
    }
}

function Invoke-AzCommandWithRetry {
    param(
        [Parameter(Mandatory = $true)] [scriptblock]$Command,
        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 10
    )
    $attempt = 0
    $lastError = $null
    while ($attempt -lt $MaxRetries) {
        $attempt++
        try {
            $result = & $Command 2>&1
            if ($LASTEXITCODE -eq 0) { return @{ Success = $true; Output = $result } }
            $lastError = $result
            Write-Log "  Attempt $attempt failed (exit code: $LASTEXITCODE), retrying in $DelaySeconds seconds..." "WARN" "Yellow"
        }
        catch {
            $lastError = $_.Exception.Message
            Write-Log "  Attempt $attempt failed: $lastError" "WARN" "Yellow"
        }
        if ($attempt -lt $MaxRetries) { Start-Sleep -Seconds $DelaySeconds }
    }
    return @{ Success = $false; Output = $null; Error = $lastError }
}

function Wait-ForWebAppProvisioning {
    param(
        [Parameter(Mandatory = $true)] [string]$ResourceGroup,
        [Parameter(Mandatory = $true)] [string]$WebAppName,
        [int]$WaitMinutes = 10
    )
    $waitSeconds = $WaitMinutes * 60
    $checkInterval = 30
    $elapsed = 0
    $url = "https://$WebAppName.azurewebsites.net"
    Write-Host "`n  [WAIT] Waiting up to $WaitMinutes minutes for Azure to provision $WebAppName..." -ForegroundColor Cyan
    Write-Host "  [INFO] Azure portal may show resources faster than CLI due to eventual consistency" -ForegroundColor Yellow
    Write-Host "  [URL] Testing URL: $url" -ForegroundColor Gray
    Write-Host "  [PROGRESS] [" -NoNewline -ForegroundColor Cyan
    $progressChars = $waitSeconds / $checkInterval
    $currentProgress = 0
    while ($elapsed -lt $waitSeconds) {
        Start-Sleep -Seconds $checkInterval
        $elapsed += $checkInterval
        $currentProgress++
        if ($currentProgress -le $progressChars) { Write-Host "#" -NoNewline -ForegroundColor Green }
        $cliCheck = az webapp show -g $ResourceGroup -n $WebAppName --query "name" -o tsv 2>$null
        if ($cliCheck -eq $WebAppName) {
            Write-Host "]" -ForegroundColor Cyan
            Write-Host "`n  [OK] Webapp verified via CLI after $([math]::Round($elapsed/60, 1)) minutes" -ForegroundColor Green
            return $true
        }
        try {
            $webCheck = Invoke-WebRequest -Uri $url -Method Get -TimeoutSec 5 -ErrorAction SilentlyContinue
            if ($webCheck.StatusCode -eq 200) {
                Write-Host "]" -ForegroundColor Cyan
                Write-Host "`n  [OK] Webapp responded HTTP 200 after $([math]::Round($elapsed/60, 1)) minutes" -ForegroundColor Green
                return $true
            }
        } catch { }
    }
    Write-Host "]" -ForegroundColor Cyan
    Write-Host "`n  Wait time completed ($WaitMinutes minutes)" -ForegroundColor Yellow
    Write-Host "  Check Azure Portal manually: https://portal.azure.com" -ForegroundColor Yellow
    return $false
}

function Wait-ForResourceGroupReady {
    param(
        [Parameter(Mandatory = $true)] [string]$ResourceGroup,
        [int]$TimeoutMinutes = 5,
        [int]$IntervalSeconds = 60
    )
    $timeoutSeconds = $TimeoutMinutes * 60
    $elapsed = 0
    Write-Host "  [WAIT] Ensuring resource group '$ResourceGroup' is ready (max ${TimeoutMinutes}m, every ${IntervalSeconds}s)..." -ForegroundColor Cyan
    Write-Host "  [PROGRESS] [" -NoNewline -ForegroundColor Cyan
    $progressChars = [math]::Ceiling($timeoutSeconds / $IntervalSeconds)
    $printed = 0
    while ($elapsed -lt $timeoutSeconds) {
        try {
            $exists = az group exists -n $ResourceGroup 2>$null
            if ($exists -eq 'true') { Write-Host "]" -ForegroundColor Cyan; return $true }
        } catch {}
        Start-Sleep -Seconds $IntervalSeconds
        $elapsed += $IntervalSeconds
        $printed++
        if ($printed -le $progressChars) { Write-Host "#" -NoNewline -ForegroundColor Green }
    }
    Write-Host "]" -ForegroundColor Cyan
    Write-Host "  [FAIL] Resource group not found or not ready after ${TimeoutMinutes} minutes: $ResourceGroup" -ForegroundColor Red
    return $false
}

Write-Host "[0/7] Selecting subscription..." -ForegroundColor Yellow
if ($SubscriptionId) { az account set --subscription $SubscriptionId | Out-Null }
$sub = az account show | ConvertFrom-Json
Write-Host "  Using Subscription: $($sub.name) ($($sub.id))" -ForegroundColor Green

# Register required resource providers for Application Insights
Write-Host "`n[1/7] Registering required Azure resource providers..." -ForegroundColor Yellow
$requiredProviders = @('Microsoft.OperationalInsights', 'Microsoft.Insights')
foreach ($provider in $requiredProviders) {
    try {
        Write-Host "  Checking provider: $provider..." -ForegroundColor Gray
        $providerState = az provider show --namespace $provider --query "registrationState" -o tsv 2>$null
        
        if ($providerState -eq 'Registered') {
            Write-Host "  [OK] Provider already registered: $provider" -ForegroundColor Green
        } else {
            Write-Host "  Registering provider: $provider..." -ForegroundColor Cyan
            az provider register --namespace $provider --wait 2>&1 | Out-Null
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [OK] Provider registered successfully: $provider" -ForegroundColor Green
                Add-LogEntry -Phase 'providers' -Action "register-$provider" -Status 'ok'
            } else {
                Write-Host "  [WARN] Failed to register provider: $provider (may require subscription permissions)" -ForegroundColor Yellow
                Add-LogEntry -Phase 'providers' -Action "register-$provider" -Status 'warning' -Detail 'Registration failed'
            }
        }
    } catch {
        Write-Host "  [WARN] Error checking/registering provider $provider : $($_.Exception.Message)" -ForegroundColor Yellow
        Add-LogEntry -Phase 'providers' -Action "register-$provider" -Status 'error' -Detail $_.Exception.Message
    }
}
Write-Host "  Provider registration check complete" -ForegroundColor Green

$envList = @($Environment)
if (-not $envList) { Write-Error "No environments specified."; exit 1 }
Write-Host "[DEBUG] Processing environment: $Environment" -ForegroundColor Magenta

# Start OIDC App Registration creation in parallel
Write-Host "`n[PARALLEL] Starting GitHub Actions OIDC App Registration..." -ForegroundColor Cyan
$appDisplayName = "GitHub-Actions-OIDC"
$oidcJob = Start-Job -ScriptBlock {
    param($appName, $tenantId, $subscriptionId)
    try {
        $existingAppOutput = az ad app list --display-name $appName 2>&1
        $listExitCode = $LASTEXITCODE
        $errorMessage = $existingAppOutput -join "`n"
        
        # Handle insufficient privileges error gracefully - app may already exist
        if ($listExitCode -ne 0 -and $errorMessage -match "Insufficient privileges|insufficient|Forbidden|403") {
            # Try to get the app directly if it exists, otherwise attempt to create it
            $getAppOutput = az ad app list --filter "displayName eq '$($appName -replace "'", "''")'" 2>&1
            if ($LASTEXITCODE -eq 0) {
                $existingApp = $getAppOutput | ConvertFrom-Json
                if ($existingApp -and $existingApp.Count -gt 0) {
                    $appId = $existingApp[0].appId
                    $appObjectId = $existingApp[0].id
                    $appCreated = $false
                } else {
                    # App doesn't exist, try to create it
                    $newAppOutput = az ad app create --display-name $appName 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        return @{ Success = $true; AppId = $null; AppObjectId = $null; SpObjectId = $null; TenantId = $tenantId; SubscriptionId = $subscriptionId; AppCreated = $false; SpCreated = $false; Error = $null; PermissionWarning = "Insufficient privileges to list/create apps. OIDC app may need manual setup." }
                    }
                    $newApp = $newAppOutput | ConvertFrom-Json
                    $appId = $newApp.appId
                    $appObjectId = $newApp.id
                    $appCreated = $true
                }
            } else {
                # Cannot list or filter apps - return success with warning
                return @{ Success = $true; AppId = $null; AppObjectId = $null; SpObjectId = $null; TenantId = $tenantId; SubscriptionId = $subscriptionId; AppCreated = $false; SpCreated = $false; Error = $null; PermissionWarning = "Insufficient privileges to list apps. OIDC app may already exist or need manual setup." }
            }
        } elseif ($listExitCode -ne 0) {
            return @{ Success = $false; AppId = $null; AppObjectId = $null; SpObjectId = $null; TenantId = $tenantId; SubscriptionId = $subscriptionId; AppCreated = $false; SpCreated = $false; Error = "Failed to list existing apps: $errorMessage" }
        } else {
            $existingApp = $existingAppOutput | ConvertFrom-Json
            if ($existingApp -and $existingApp.Count -gt 0) {
                $appId = $existingApp[0].appId
                $appObjectId = $existingApp[0].id
                $appCreated = $false
            } else {
                $newAppOutput = az ad app create --display-name $appName 2>&1
                if ($LASTEXITCODE -ne 0) {
                    return @{ Success = $false; AppId = $null; AppObjectId = $null; SpObjectId = $null; TenantId = $tenantId; SubscriptionId = $subscriptionId; AppCreated = $false; SpCreated = $false; Error = "Failed to create app: $newAppOutput" }
                }
                $newApp = $newAppOutput | ConvertFrom-Json
                $appId = $newApp.appId
                $appObjectId = $newApp.id
                $appCreated = $true
            }
        }

        $existingSpOutput = az ad sp list --filter "appId eq '$appId'" 2>&1
        if ($LASTEXITCODE -ne 0) {
            return @{ Success = $false; AppId = $appId; AppObjectId = $appObjectId; SpObjectId = $null; TenantId = $tenantId; SubscriptionId = $subscriptionId; AppCreated = $appCreated; SpCreated = $false; Error = "Failed to list existing service principals: $existingSpOutput" }
        }
        $existingSp = $existingSpOutput | ConvertFrom-Json
        if ($existingSp -and $existingSp.Count -gt 0) {
            $spObjectId = $existingSp[0].id
            $spCreated = $false
        } else {
            $spOutput = az ad sp create --id $appId 2>&1
            if ($LASTEXITCODE -ne 0) {
                return @{ Success = $false; AppId = $appId; AppObjectId = $appObjectId; SpObjectId = $null; TenantId = $tenantId; SubscriptionId = $subscriptionId; AppCreated = $appCreated; SpCreated = $false; Error = "Failed to create service principal: $spOutput" }
            }
            $sp = $spOutput | ConvertFrom-Json
            $spObjectId = $sp.id
            $spCreated = $true
        }

        return @{ Success = $true; AppId = $appId; AppObjectId = $appObjectId; SpObjectId = $spObjectId; TenantId = $tenantId; SubscriptionId = $subscriptionId; AppCreated = $appCreated; SpCreated = $spCreated; Error = $null }
    }
    catch {
        return @{ Success = $false; AppId = $null; AppObjectId = $null; SpObjectId = $null; TenantId = $tenantId; SubscriptionId = $subscriptionId; AppCreated = $false; SpCreated = $false; Error = $_.Exception.Message }
    }
} -ArgumentList $appDisplayName, $sub.tenantId, $sub.id

$created = @()

foreach ($env in $envList) {
    Write-Host "`n[env:$env] Processing environment resources" -ForegroundColor Yellow
    $rg = "rg-$BaseName-$env"
    $plan = "asp-$BaseName-$env"
    # Prepend GitHub owner to webapp names for global uniqueness
    $apiApp = "$GitHubOwner-$BaseName-$ApiSuffix-$env"
    $uiApp = "$GitHubOwner-$BaseName-$UiSuffix-$env"
    $sku = Resolve-Sku $env

    # Resource Group
    $rgExists = az group exists -n $rg
    if ($rgExists -eq 'false') {
        Write-Host "  Creating resource group: $rg ..." -ForegroundColor Yellow
        az group create -n $rg -l $Location --tags env=$env app=$BaseName | Out-Null
        Write-Host "  RG create requested: $rg" -ForegroundColor Cyan
        Add-StepStatus -Name "Create Resource Group ($rg)" -Status "Success" -Details "Created in $Location"
    }
    else {
        Write-Host "  RG exists: $rg" -ForegroundColor Green
        Add-StepStatus -Name "Create Resource Group ($rg)" -Status "Success" -Details "Already existed"
    }

    # Strict RG readiness gate
    Write-Host "  [GATE] Validating resource group readiness before proceeding..." -ForegroundColor Cyan
    $rgReady = Wait-ForResourceGroupReady -ResourceGroup $rg -TimeoutMinutes 5 -IntervalSeconds 60
    if (-not $rgReady) {
        Write-Host "  [CRITICAL] Resource group not ready after 10 minutes: $rg" -ForegroundColor Red
        Write-Host "  [EXIT] Cannot proceed - aborting" -ForegroundColor Red
        Add-StepStatus -Name "Create Resource Group ($rg)" -Status "Failed" -Details "Readiness gate failed"
        exit 1
    }
    Write-Host "  [GATE PASSED] Resource group ready - proceeding" -ForegroundColor Green

    # App Service Plan
    Write-Host "  [STEP] Creating App Service Plan..." -ForegroundColor Cyan
    $planExists = az appservice plan list --resource-group $rg --query "[?name=='$plan']" -o tsv
    if (-not $planExists) {
        Write-Host "  Creating plan: $plan ($sku)..." -ForegroundColor Yellow
        $planResult = Invoke-AzCommandWithRetry -Command { az appservice plan create -g $rg -n $plan --sku $sku --location $Location }
        if (-not $planResult.Success) {
            Write-Host "  Plan creation FAILED after retries: $($planResult.Error)" -ForegroundColor Red
            Add-StepStatus -Name "Create App Service Plan ($plan, $sku)" -Status "Failed" -Details "$($planResult.Error)"
            continue
        }
        Write-Host "  Plan creation initiated: $plan ($sku)" -ForegroundColor Cyan
        Write-Host "  [WAIT] Waiting 2 minutes for App Service Plan to be fully ready..." -ForegroundColor Yellow
        $waitSeconds = 120
        $checkInterval = 30
        $elapsed = 0
        Write-Host "  [PROGRESS] [" -NoNewline -ForegroundColor Cyan
        while ($elapsed -lt $waitSeconds) {
            Start-Sleep -Seconds $checkInterval
            $elapsed += $checkInterval
            Write-Host "#" -NoNewline -ForegroundColor Green
        }
        Write-Host "]" -ForegroundColor Cyan
        Add-StepStatus -Name "Create App Service Plan ($plan, $sku)" -Status "Success" -Details "Created"
    }
    else { Write-Host "  Plan exists: $plan" -ForegroundColor Green; Add-StepStatus -Name "Create App Service Plan ($plan, $sku)" -Status "Success" -Details "Already existed" }

    # API Web App
    $apiExists = $null
    $apiCreateCmd = "az webapp create -g $rg -p $plan -n $apiApp --runtime 'dotnet:8'"
    try { $apiExists = az webapp show -g $rg -n $apiApp --query "name" -o tsv 2>$null; if ($LASTEXITCODE -ne 0) { $apiExists = $null } } catch { $apiExists = $null }
    if ($apiExists -eq $apiApp) { Write-Host "  API WebApp already exists: $apiApp" -ForegroundColor Green; Add-StepStatus -Name "Create API Web App ($apiApp)" -Status "Success" -Details "Already existed" }
    else {
        Write-Host "  Starting API webapp creation: $apiApp..." -ForegroundColor Yellow
        Write-Host "  [COMMAND] $apiCreateCmd" -ForegroundColor Magenta
        $apiResult = New-WebAppWithSuperRetry -ResourceGroup $rg -PlanName $plan -AppName $apiApp
        if ($apiResult.Success) { Write-Host "  [OK] API created: $apiApp" -ForegroundColor Green; Add-StepStatus -Name "Create API Web App ($apiApp)" -Status "Success" -Details "Created" } else { Write-Host "  [FAIL] Could not create API: $($apiResult.Error)" -ForegroundColor Red; Add-StepStatus -Name "Create API Web App ($apiApp)" -Status "Failed" -Details "$($apiResult.Error)" }
    }

    # UI Web App
    $uiExists = $null
    $uiCreateCmd = "az webapp create -g $rg -p $plan -n $uiApp --runtime 'dotnet:8'"
    try { $uiExists = az webapp show -g $rg -n $uiApp --query "name" -o tsv 2>$null; if ($LASTEXITCODE -ne 0) { $uiExists = $null } } catch { $uiExists = $null }
    if ($uiExists -eq $uiApp) { Write-Host "  UI WebApp already exists: $uiApp" -ForegroundColor Green; Add-StepStatus -Name "Create UI Web App ($uiApp)" -Status "Success" -Details "Already existed" }
    else {
        Write-Host "  Starting UI webapp creation: $uiApp..." -ForegroundColor Yellow
        Write-Host "  [COMMAND] $uiCreateCmd" -ForegroundColor Magenta
        $uiResult = New-WebAppWithSuperRetry -ResourceGroup $rg -PlanName $plan -AppName $uiApp
        if ($uiResult.Success) { Write-Host "  [OK] UI created: $uiApp" -ForegroundColor Green; Add-StepStatus -Name "Create UI Web App ($uiApp)" -Status "Success" -Details "Created" } else { Write-Host "  [FAIL] Could not create UI: $($uiResult.Error)" -ForegroundColor Red; Add-StepStatus -Name "Create UI Web App ($uiApp)" -Status "Failed" -Details "$($uiResult.Error)" }
    }

    # Application Insights
    $aiName = "ai-$BaseName-$env"
    $aiExists = $null
    try { $aiExists = az monitor app-insights component show -a $aiName -g $rg --query "name" -o tsv 2>$null; if ($LASTEXITCODE -ne 0) { $aiExists = $null } } catch { $aiExists = $null }
    $aiJob = $null
    if (-not $aiExists) {
        Write-Host "  Starting Application Insights creation: $aiName..." -ForegroundColor Yellow
        $aiJob = Start-Job -ScriptBlock { param($rg, $aiName, $Location); try { $result = az monitor app-insights component create -a $aiName -g $rg -l $Location --application-type web 2>&1; if ($LASTEXITCODE -eq 0) { return @{ Success = $true; Output = $result; Error = $null; ResourceName = $aiName } }; return @{ Success = $false; Output = $null; Error = $result; ResourceName = $aiName } } catch { return @{ Success = $false; Output = $null; Error = $_.Exception.Message; ResourceName = $aiName } } } -ArgumentList $rg, $aiName, $Location
    } else { Write-Host "  Application Insights already exists: $aiName" -ForegroundColor Green; Add-StepStatus -Name "Create Application Insights ($aiName)" -Status "Success" -Details "Already existed" }

    # Wait for parallel jobs to complete (if any)
    Write-Host "`n  [PARALLEL] Waiting for creation jobs to complete..." -ForegroundColor Cyan
    $jobs = @()
    if ($aiJob) { $jobs += $aiJob }

    if ($jobs.Count -gt 0) {
        $jobs | Wait-Job | Out-Null

        if ($aiJob) {
            $aiResult = Receive-Job -Job $aiJob -Keep; Remove-Job -Job $aiJob
            if ($aiResult.Success) {
                Write-Host "  [OK] Application Insights created: $aiName" -ForegroundColor Green
                Add-StepStatus -Name "Create Application Insights ($aiName)" -Status "Success" -Details "Created"
            }
            else {
                Write-Host "  [ERROR] Application Insights creation job failed. Full error output:" -ForegroundColor Red
                Write-Host $aiResult.Error -ForegroundColor Red
                throw "Application Insights creation failed - see error above"
            }
        }
        elseif ($aiExists) { Write-Host "  Application Insights exists: $aiName" -ForegroundColor Green }
    }

    # Unified readiness wait - ensures plan + apps reach ready status
    # Plan timeout reduced to 2 minutes as it's usually ready quickly or remains in transitioning state
    Write-Host "`n  [WAIT] Performing unified readiness checks (Plan: 2 min max, Apps: 10 min max)..." -ForegroundColor Cyan
    $planTimeoutSeconds = 2 * 60  # Reduced from 10 minutes to 2 minutes
    $appTimeoutSeconds = 10 * 60
    $intervalSeconds = 30
    $elapsed = 0
    $planReady = $false; $apiReady = $false; $uiReady = $false
    $planTimeoutMessageShown = $false
    $apiUrl = "https://$apiApp.azurewebsites.net"; $uiUrl = "https://$uiApp.azurewebsites.net"
    Write-Host "  [TARGET] Plan: $plan (checking for up to 2 min)" -ForegroundColor Gray
    Write-Host "  [TARGET] API : $apiApp (checking for up to 10 min)" -ForegroundColor Gray
    Write-Host "  [TARGET] UI  : $uiApp (checking for up to 10 min)" -ForegroundColor Gray
    Write-Host "  [PROGRESS] [" -NoNewline -ForegroundColor Cyan
    $progressChars = [math]::Ceiling($appTimeoutSeconds / $intervalSeconds)
    $progressPrinted = 0

    while ($elapsed -lt $appTimeoutSeconds -and (-not $apiReady -or -not $uiReady)) {
        Start-Sleep -Seconds $intervalSeconds
        $elapsed += $intervalSeconds
        $progressPrinted++
        if ($progressPrinted -le $progressChars) { Write-Host "#" -NoNewline -ForegroundColor Green }

        # Plan readiness: provisioningState Succeeded + status Ready (check for 2 minutes only)
        if (-not $planReady -and $elapsed -le $planTimeoutSeconds) {
            $planInfo = $null
            try {
                $planInfo = az appservice plan show -g $rg -n $plan --query '{prov:provisioningState,status:status}' -o json 2>$null | ConvertFrom-Json
                if ($LASTEXITCODE -ne 0) { $planInfo = $null }
            }
            catch { $planInfo = $null }
            if ($planInfo -and $planInfo.prov -eq 'Succeeded' -and $planInfo.status -eq 'Ready') {
                $planReady = $true
                Write-Host "`n  [OK] Plan ready (provisioningState=Succeeded, status=Ready) after $([math]::Round($elapsed/60,1)) min" -ForegroundColor Green
                Write-Host "  [PROGRESS] [" -NoNewline -ForegroundColor Cyan; for ($i = 0; $i -lt $progressPrinted; $i++) { Write-Host "#" -NoNewline -ForegroundColor Green }
            }
        } elseif (-not $planReady -and $elapsed -gt $planTimeoutSeconds -and -not $planTimeoutMessageShown) {
            # Plan check timed out after 2 minutes - show message once
            Write-Host "`n  [INFO] Plan readiness check timed out after 2 min - continuing to check apps" -ForegroundColor Yellow
            Write-Host "  [NOTE] Plan may still be provisioning in background, but apps can be checked independently" -ForegroundColor Gray
            Write-Host "  [PROGRESS] [" -NoNewline -ForegroundColor Cyan; for ($i = 0; $i -lt $progressPrinted; $i++) { Write-Host "#" -NoNewline -ForegroundColor Green }
            $planTimeoutMessageShown = $true
        }

        # API readiness
        if (-not $apiReady) {
            $apiExistsNow = $null
            try {
                $apiExistsNow = az webapp show -g $rg -n $apiApp --query '{state:state,host:defaultHostName}' -o json 2>$null | ConvertFrom-Json
                if ($LASTEXITCODE -ne 0) { $apiExistsNow = $null }
            }
            catch { $apiExistsNow = $null }
            if ($apiExistsNow) {
                $httpOk = $false
                try {
                    $resp = Invoke-WebRequest -Uri $apiUrl -Method Get -TimeoutSec 8 -ErrorAction SilentlyContinue
                    if ($resp -and ($resp.StatusCode -eq 200 -or $resp.StatusCode -eq 404)) { $httpOk = $true }
                }
                catch { }
                if ($apiExistsNow.state -eq 'Running' -and $httpOk) {
                    $apiReady = $true
                    Write-Host "`n  [OK] API ready (state=Running + HTTP responding) after $([math]::Round($elapsed/60,1)) min" -ForegroundColor Green
                    Write-Host "  [PROGRESS] [" -NoNewline -ForegroundColor Cyan; for ($i = 0; $i -lt $progressPrinted; $i++) { Write-Host "#" -NoNewline -ForegroundColor Green }
                }
            }
        }

        # UI readiness
        if (-not $uiReady) {
            $uiExistsNow = $null
            try {
                $uiExistsNow = az webapp show -g $rg -n $uiApp --query '{state:state,host:defaultHostName}' -o json 2>$null | ConvertFrom-Json
                if ($LASTEXITCODE -ne 0) { $uiExistsNow = $null }
            }
            catch { $uiExistsNow = $null }
            if ($uiExistsNow) {
                $httpOk = $false
                try {
                    $resp = Invoke-WebRequest -Uri $uiUrl -Method Get -TimeoutSec 8 -ErrorAction SilentlyContinue
                    if ($resp -and ($resp.StatusCode -eq 200 -or $resp.StatusCode -eq 404)) { $httpOk = $true }
                }
                catch { }
                if ($uiExistsNow.state -eq 'Running' -and $httpOk) {
                    $uiReady = $true
                    Write-Host "`n  [OK] UI ready (state=Running + HTTP responding) after $([math]::Round($elapsed/60,1)) min" -ForegroundColor Green
                    Write-Host "  [PROGRESS] [" -NoNewline -ForegroundColor Cyan; for ($i = 0; $i -lt $progressPrinted; $i++) { Write-Host "#" -NoNewline -ForegroundColor Green }
                    # Once both apps are ready, we can exit early (don't need to wait for plan)
                    if ($apiReady -and $uiReady) {
                        Write-Host "`n  [SUCCESS] Both web apps are ready - exiting readiness check early" -ForegroundColor Green
                        break
                    }
                }
            }
        }
    }
    Write-Host "]" -ForegroundColor Cyan

    # Check if we timed out
    if ($elapsed -ge $appTimeoutSeconds) {
        Write-Host "`n  [TIMEOUT] App readiness wait reached 10-minute limit" -ForegroundColor Yellow
        Write-Host "  Waiting for: $(if (-not $apiReady) { 'API ' })$(if (-not $uiReady) { 'UI ' })" -ForegroundColor Yellow
        Write-Host "  Current status: Plan=$planReady API=$apiReady UI=$uiReady" -ForegroundColor Yellow
        Write-Host "  Resources may still be provisioning - check Azure Portal" -ForegroundColor Yellow
    }
    else {
        Write-Host "`n  [SUCCESS] All required resources reached readiness in $([math]::Round($elapsed/60,1)) min" -ForegroundColor Green
        Write-Host "  Final status: Plan=$planReady API=$apiReady UI=$uiReady" -ForegroundColor Gray
    }

    # Verify resource details
    Write-Host "`n  [VERIFY] Running comprehensive resource verification..." -ForegroundColor Cyan
    $allResourcesReady = $true
        
    # Verify App Service Plan status
    $planStatus = az appservice plan show -g $rg -n $plan --query '{Name:name, Status:status, State:provisioningState, Sku:sku.name}' -o json 2>$null | ConvertFrom-Json
    if ($planStatus -and $planStatus.Status -eq "Ready" -and $planStatus.State -eq "Succeeded") {
        Write-Host "  [OK] App Service Plan: $plan is Ready (SKU: $($planStatus.Sku))" -ForegroundColor Green
    }
    else {
        Write-Host "  [FAIL] App Service Plan: $plan is not ready" -ForegroundColor Red
        $allResourcesReady = $false
    }
        
    # Verify Application Insights
    $aiCheck = az monitor app-insights component show -a $aiName -g $rg --query '{Name:name, ProvisioningState:provisioningState}' -o json 2>$null | ConvertFrom-Json
    if ($aiCheck -and $aiCheck.ProvisioningState -eq "Succeeded") {
        Write-Host "  [OK] Application Insights: $aiName is provisioned" -ForegroundColor Green
    }
    else {
        Write-Host "  [WARN] Application Insights: $aiName status unknown or not provisioned" -ForegroundColor Yellow
    }
        
    # Final verification for API
    $apiCheckFinal = az webapp show -g $rg -n $apiApp --query "name" -o tsv 2>$null
    if ($apiCheckFinal -eq $apiApp) {
        Write-Host "  [OK] API WebApp verified: $apiApp" -ForegroundColor Cyan
            
        # Verify app state
        $apiState = az webapp show -g $rg -n $apiApp --query '{State:state, HostNames:defaultHostName}' -o json 2>$null | ConvertFrom-Json
        if ($apiState.State -eq "Running") {
            Write-Host "    [OK] State: Running at https://$($apiState.HostNames)" -ForegroundColor Green
        }
        else {
            Write-Host "    [WARN] State: $($apiState.State)" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  [WARN] API WebApp not found: $apiApp" -ForegroundColor Yellow
    }
        
    # Final verification for UI
    $uiCheckFinal = az webapp show -g $rg -n $uiApp --query "name" -o tsv 2>$null
    if ($uiCheckFinal -eq $uiApp) {
        Write-Host "  [OK] UI WebApp verified: $uiApp" -ForegroundColor Cyan
            
        # Verify app state
        $uiState = az webapp show -g $rg -n $uiApp --query '{State:state, HostNames:defaultHostName}' -o json 2>$null | ConvertFrom-Json
        if ($uiState.State -eq "Running") {
            Write-Host "    [OK] State: Running at https://$($uiState.HostNames)" -ForegroundColor Green
        }
        else {
            Write-Host "    [WARN] State: $($uiState.State)" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  [WARN] UI WebApp not found: $uiApp" -ForegroundColor Yellow
    }

    # Configure App Insights connection strings (if AI exists & webapps exist)
    try {
        Write-Host "`n  [CONFIG] Checking App Insights availability..." -ForegroundColor Cyan
        $aiCheck = az monitor app-insights component show -a $aiName -g $rg 2>$null
        if ($aiCheck) {
            Write-Host "    [OK] App Insights found: $aiName" -ForegroundColor Green
            $connString = az monitor app-insights component show -a $aiName -g $rg --query "connectionString" -o tsv 2>$null
            if ($connString) {
                Write-Host "  [CONFIG] Configuring App Insights connection strings..." -ForegroundColor Cyan
                Write-Host "    [INFO] Note: This may take 30-60 seconds as it triggers app restart" -ForegroundColor Yellow
                
                $apiVerified = az webapp show -g $rg -n $apiApp --query "name" -o tsv 2>$null
                if ($apiVerified -eq $apiApp) {
                    Write-Host "    [PROCESSING] Configuring API app settings..." -ForegroundColor Gray
                    $job = Start-Job -ScriptBlock {
                        param($rg, $apiApp, $connString)
                        az webapp config appsettings set -g $rg -n $apiApp --settings "APPLICATIONINSIGHTS_CONNECTION_STRING=$connString" 2>$null
                    } -ArgumentList $rg, $apiApp, $connString
                    
                    $timeout = 90
                    $completed = Wait-Job -Job $job -Timeout $timeout
                    if ($completed) {
                        $result = Receive-Job -Job $job
                        Remove-Job -Job $job
                        Write-Host "    [OK] App Insights configured for API: $apiApp" -ForegroundColor Green
                    } else {
                        Stop-Job -Job $job
                        Remove-Job -Job $job
                        Write-Host "    [WARN] App Insights configuration for API timed out after ${timeout}s - will retry later" -ForegroundColor Yellow
                    }
                }
                
                $uiVerified = az webapp show -g $rg -n $uiApp --query "name" -o tsv 2>$null
                if ($uiVerified -eq $uiApp) {
                    Write-Host "    [PROCESSING] Configuring UI app settings..." -ForegroundColor Gray
                    $job = Start-Job -ScriptBlock {
                        param($rg, $uiApp, $connString)
                        az webapp config appsettings set -g $rg -n $uiApp --settings "APPLICATIONINSIGHTS_CONNECTION_STRING=$connString" 2>$null
                    } -ArgumentList $rg, $uiApp, $connString
                    
                    $timeout = 90
                    $completed = Wait-Job -Job $job -Timeout $timeout
                    if ($completed) {
                        $result = Receive-Job -Job $job
                        Remove-Job -Job $job
                        Write-Host "    [OK] App Insights configured for UI: $uiApp" -ForegroundColor Green
                    } else {
                        Stop-Job -Job $job
                        Remove-Job -Job $job
                        Write-Host "    [WARN] App Insights configuration for UI timed out after ${timeout}s - will retry later" -ForegroundColor Yellow
                    }
                }
            } else {
                Write-Host "    [WARN] Could not retrieve App Insights connection string" -ForegroundColor Yellow
            }
        } else {
            Write-Host "    [WARN] App Insights not found: $aiName" -ForegroundColor Yellow
        }
    } catch {
        Write-Log "Failed to configure App Insights connection string: $($_.Exception.Message)" "WARN" "Yellow"
    }

    # Runtime check & attempt config to .NET 8 if needed (for both API & UI)
    try {
        if ($apiCheckFinal -eq $apiApp) {
            $runtime = az webapp config show -g $rg -n $apiApp --query "netFrameworkVersion" -o tsv 2>$null
            if ($runtime -ne "v8.0") {
                Write-Host "  [WARN] API runtime: $runtime (expected v8.0), configuring .NET 8..." -ForegroundColor Yellow
                az webapp config set -g $rg -n $apiApp --net-framework-version "v8.0" 2>$null | Out-Null
                Start-Sleep -Seconds 3
                $runtimeCheck = az webapp config show -g $rg -n $apiApp --query "netFrameworkVersion" -o tsv 2>$null
                if ($runtimeCheck -eq "v8.0") { Write-Host "    [OK] API runtime configured to .NET 8" -ForegroundColor Green } else { Write-Host "    [FAIL] API runtime configuration failed; verify manually" -ForegroundColor Red }
            } else { Write-Host "    [OK] API runtime: .NET 8" -ForegroundColor Green }
        }
        if ($uiCheckFinal -eq $uiApp) {
            $runtime = az webapp config show -g $rg -n $uiApp --query "netFrameworkVersion" -o tsv 2>$null
            if ($runtime -ne "v8.0") {
                Write-Host "  [WARN] UI runtime: $runtime (expected v8.0), configuring .NET 8..." -ForegroundColor Yellow
                az webapp config set -g $rg -n $uiApp --net-framework-version "v8.0" 2>$null | Out-Null
                Start-Sleep -Seconds 3
                $runtimeCheck = az webapp config show -g $rg -n $uiApp --query "netFrameworkVersion" -o tsv 2>$null
                if ($runtimeCheck -eq "v8.0") { Write-Host "    [OK] UI runtime configured to .NET 8" -ForegroundColor Green } else { Write-Host "    [FAIL] UI runtime configuration failed; verify manually" -ForegroundColor Red }
            } else { Write-Host "    [OK] UI runtime: .NET 8" -ForegroundColor Green }
        }
    } catch {
        Write-Log "Runtime config check failed: $($_.Exception.Message)" "WARN" "Yellow"
    }

    $created += [PSCustomObject]@{ Environment=$env; ResourceGroup=$rg; Plan=$plan; ApiApp=$apiApp; UiApp=$uiApp; Sku=$sku; AppInsights=$aiName }
}

# OIDC Setup & RBAC
Write-Host "`n[OIDC Setup] Configuring GitHub Actions OIDC..." -ForegroundColor Cyan
$oidcJob | Wait-Job | Out-Null
$oidcResult = Receive-Job -Job $oidcJob
Remove-Job -Job $oidcJob

if ($oidcResult.Success) {
    Add-StepStatus -Name "Setup OIDC (GitHub-Actions-OIDC)" -Status "Success" -Details "AppId=$($oidcResult.AppId)"
    Write-Host "  App (Client) ID: $($oidcResult.AppId)" -ForegroundColor Cyan
    Write-Host "  SP Object ID: $($oidcResult.SpObjectId)" -ForegroundColor Gray
    # Configure OIDC branches
    $existingCreds = az ad app federated-credential list --id $oidcResult.AppObjectId 2>$null | ConvertFrom-Json
    if (-not $existingCreds) { $existingCreds = @() }
    $branches = @('main','staging','dev')
    foreach ($branch in $branches) {
        $credName = "github-$branch-oidc"
        $exists = $existingCreds | Where-Object { $_.name -eq $credName }
        if (-not $exists) {
            $subject = "repo:${GitHubOwner}/${GitHubRepo}:ref:refs/heads/$branch"
            $credentialJson = @{ name = $credName; issuer = "https://token.actions.githubusercontent.com"; subject = $subject; audiences = @("api://AzureADTokenExchange") } | ConvertTo-Json
            $tempFile = [System.IO.Path]::GetTempFileName()
            $credentialJson | Out-File -FilePath $tempFile -Encoding UTF8
            az ad app federated-credential create --id $oidcResult.AppObjectId --parameters $tempFile 2>$null | Out-Null
            Remove-Item $tempFile -ErrorAction SilentlyContinue
            Write-Host "    [$credName] Created (branch: $branch)" -ForegroundColor Green
        } else { Write-Host "    [$credName] Already exists (branch: $branch)" -ForegroundColor Gray }
    }

    # Assign Contributor role to resource groups
    Write-Host "`n  [RBAC] Assigning Contributor role to resource groups..." -ForegroundColor Yellow
    $rgList = $created | Select-Object -ExpandProperty ResourceGroup -Unique
    foreach ($rg in $rgList) {
        $scope = "/subscriptions/$($oidcResult.SubscriptionId)/resourceGroups/$rg"
        $existingAssignment = az role assignment list --assignee $oidcResult.SpObjectId --role "Contributor" --scope $scope 2>$null | ConvertFrom-Json
        if (-not $existingAssignment -or $existingAssignment.Count -eq 0) {
            az role assignment create --assignee $oidcResult.SpObjectId --role "Contributor" --scope $scope 2>$null | Out-Null
            Write-Host "    [$rg] Contributor role assigned" -ForegroundColor Green
        } else { Write-Host "    [$rg] Contributor role already assigned" -ForegroundColor Gray }
    }

    # GitHub secrets display
    Write-Host "`n  [GitHub Secrets] Add these to repository secrets:" -ForegroundColor Cyan
    Write-Host "    https://github.com/$GitHubOwner/$GitHubRepo/settings/secrets/actions" -ForegroundColor Gray
    Write-Host "\n    AZUREAPPSERVICE_CLIENTID:        $($oidcResult.AppId)" -ForegroundColor White
    Write-Host "    AZUREAPPSERVICE_TENANTID:        $($oidcResult.TenantId)" -ForegroundColor White
    Write-Host "    AZUREAPPSERVICE_SUBSCRIPTIONID:  $($oidcResult.SubscriptionId)" -ForegroundColor White
    $secretsOutput = @"

=== GITHUB REPOSITORY SECRETS ===

AZUREAPPSERVICE_CLIENTID:        $($oidcResult.AppId)
AZUREAPPSERVICE_TENANTID:        $($oidcResult.TenantId)
AZUREAPPSERVICE_SUBSCRIPTIONID:  $($oidcResult.SubscriptionId)

=================================
"@
    $secretsOutput | Set-Clipboard -ErrorAction SilentlyContinue
    Write-Host "  [OK] Secrets copied to clipboard!" -ForegroundColor Green
    # Automatic GitHub secrets configuration (if helper script is present)
    Write-Host "`n  [AUTOMATION] Configuring GitHub secrets automatically..." -ForegroundColor Cyan
    $configScriptPath = Join-Path $PSScriptRoot "configure-github-secrets.ps1"
    if (Test-Path $configScriptPath) {
        try {
            & $configScriptPath -Repository "$GitHubOwner/$GitHubRepo" -Force -ErrorAction Stop
            Write-Host "  [OK] GitHub secrets configured automatically!" -ForegroundColor Green
            Add-StepStatus -Name "Auto-configure GitHub Secrets" -Status "Success" -Details "Repository=$GitHubOwner/$GitHubRepo"
        } catch {
            Write-Host "  [WARN] Automatic secret configuration failed: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "  [ACTION] Configure manually or run: ./configure-github-secrets.ps1" -ForegroundColor Yellow
            Add-StepStatus -Name "Auto-configure GitHub Secrets" -Status "Failed" -Details "$($_.Exception.Message)"
        }
    } else {
        Write-Host "  [INFO] Automatic configuration script not found - configure manually" -ForegroundColor Yellow
    }
} else {
    if ($oidcResult.PermissionWarning) {
        Add-StepStatus -Name "Setup OIDC (GitHub-Actions-OIDC)" -Status "Success" -Details "Skipped (insufficient permissions)"
        Write-Host "  [INFO] OIDC setup skipped due to permissions - app may already exist" -ForegroundColor Cyan
        Write-Host "  Note: $($oidcResult.PermissionWarning)" -ForegroundColor Gray
    } else {
        Add-StepStatus -Name "Setup OIDC (GitHub-Actions-OIDC)" -Status "Failed" -Details "$($oidcResult.Error)"
        Write-Host "  [WARN] OIDC setup encountered errors: $($oidcResult.Error)" -ForegroundColor Yellow
    }
}

# Post-deployment self-tests
Write-Log "Starting Post-Deployment Self-Test..." "INFO" "Cyan"
$apiUrl = "https://$apiApp.azurewebsites.net"
$uiUrl = "https://$uiApp.azurewebsites.net"
$apiHealthy = Test-WebEndpoint -Url $apiUrl -Name "API ($apiApp)"
$uiHealthy = Test-WebEndpoint -Url $uiUrl -Name "UI ($uiApp)"
if ($apiHealthy -and $uiHealthy) { Add-StepStatus -Name "Self-Test" -Status "Success" -Details "API+UI healthy"; Write-Log "Post-Deployment Self-Test PASSED" "INFO" "Green" }
else { Add-StepStatus -Name "Self-Test" -Status "Failed" -Details "APIHealthy=$apiHealthy UIHealthy=$uiHealthy"; Write-Log "Post-Deployment Self-Test FAILED" "WARN" "Yellow" }

Write-Host "`n[Summary] Provisioning results:" -ForegroundColor Yellow
$created | Format-Table -AutoSize

$scriptEndTime = Get-Date
Write-Host "\n[INFO] Bootstrap completed at: $scriptEndTime" -ForegroundColor Cyan
Write-Host "[INFO] Total duration: $([math]::Round(($scriptEndTime - $scriptStartTime).TotalMinutes,2)) minutes" -ForegroundColor Cyan

Write-Host "\n[Step Summary]" -ForegroundColor Yellow
Write-Log "Writing Step Summary to log file..." "INFO" "Cyan"
$index = 1
foreach ($s in $global:StepStatus) {
    $detailsText = if ($s.Details) { " ($($s.Details))" } else { "" }
    if ($s.Status -eq 'Success') { Write-Host ("  {0}. {1} - Success{2}" -f $index, $s.Name, $detailsText) -ForegroundColor Green }
    elseif ($s.Status -eq 'Failed') { Write-Host ("  {0}. {1} - Failed{2}" -f $index, $s.Name, $detailsText) -ForegroundColor Red }
    else { Write-Host ("  {0}. {1} - {2}{3}" -f $index, $s.Name, $s.Status, $detailsText) -ForegroundColor Yellow }
    $index++
}

Write-Host "\nNext Steps:" -ForegroundColor Yellow
if ($oidcResult.Success) {
    Write-Host "  1. Add the repository secrets copied above to GitHub (if not already)." -ForegroundColor White
    Write-Host "  2. Push to branches to trigger deployments." -ForegroundColor White
}

# Write detailed StepStatus to CSV and finalize log
try { $csvPath = Join-Path $logDir ("step-summary-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".csv"); $global:StepStatus | Export-Csv -Path $csvPath -NoTypeInformation -Force; Write-Log "Step summary exported to $csvPath" "INFO" "Cyan" } catch { Write-Log "Failed to export step summary CSV: $($_.Exception.Message)" "WARN" "Yellow" }

Write-Log "=== Bootstrap completed ===" "INFO" "Cyan"
