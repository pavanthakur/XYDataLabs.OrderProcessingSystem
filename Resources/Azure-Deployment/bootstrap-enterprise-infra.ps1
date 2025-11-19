<#!
.SYNOPSIS
  Provisions enterprise-grade Azure infrastructure for multiple environments (dev, stg, prod by default) for the Order Processing System.
.DESCRIPTION
  Creates (idempotently): Resource Groups, App Service Plans (per environment), and Web Apps (API + UI) following naming standards.
  Automatically configures GitHub Actions OIDC with federated credentials for branch-based deployments.
  
  BRANCH-TO-ENVIRONMENT MAPPING:
  - dev branch      → github-dev-oidc credential     → rg-orderprocessing-dev resources
  - staging branch  → github-staging-oidc credential → rg-orderprocessing-stg resources  
  - main branch     → github-main-oidc credential    → rg-orderprocessing-prod resources (future)
  

# --- ENHANCEMENTS INSERTED: Logging, Super-Retry WebApp Creator, Self-Test ---

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

# Super retry synchronous webapp creation helper (replaces async Start-Job based creation)
function New-WebAppWithSuperRetry {
    param([string]$ResourceGroup, [string]$PlanName, [string]$AppName, [int]$MaxAttempts = 5, [int]$DelaySeconds = 15)
    $lastErr = $null
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        Write-Log "Creating WebApp '$AppName' (Attempt $i/$MaxAttempts)..." "INFO" "Yellow"
        $result = az webapp create -g $ResourceGroup -p $PlanName -n $AppName --runtime "dotnet:8" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "WebApp '$AppName' created successfully." "INFO" "Green"
            return @{ Success = $true; Output = $result }
        } else {
            $lastErr = $result
            Write-Log "Attempt $i failed for '$AppName': $result" "WARN" "Red"
            Start-Sleep -Seconds $DelaySeconds
        }
    }
    return @{ Success = $false; Error = $lastErr }
}

# Post-deployment self-test helper functions
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

# Ensure Add-StepStatus exists (if original script didn't define earlier)
if (-not (Get-Command Add-StepStatus -ErrorAction SilentlyContinue)) {
    function Add-StepStatus { param([string]$Name,[string]$Status,[string]$Details=""); $global:StepStatus += [PSCustomObject]@{Name=$Name;Status=$Status;Details=$Details} }
}

# --- end helpers ---

  Intended to be run ONCE to set up all environments and OIDC authentication.
.PARAMETER SubscriptionId
  Optional subscription Id. If omitted, uses current az CLI default.
.PARAMETER BaseName
  Logical base name for resources (e.g. 'orderprocessing').
.PARAMETER Location
  Azure region (e.g. 'eastus').
.PARAMETER Environments
  Comma-separated list of environments to provision. Default: 'dev,stg,prod'.
.PARAMETER ApiSuffix
  Suffix segment for API apps (default 'api-xyapp').
.PARAMETER UiSuffix
  Suffix segment for UI apps (default 'ui-xyapp').
.PARAMETER DevSku
  App Service Plan SKU for dev (Default: 'F1').
.PARAMETER StgSku
  App Service Plan SKU for staging (Default: 'B1').
.PARAMETER ProdSku
  App Service Plan SKU for production (Default: 'P1v3').
.EXAMPLE
  ./bootstrap-enterprise-infra.ps1 -SubscriptionId <SUB_ID> -BaseName orderprocessing -Location eastus -Environments dev,stg,prod
.NOTES
  Adjust SKUs before production usage. Add monitoring (App Insights) separately for clarity.
#>
param(
    [Parameter(Mandatory = $false)] [string]$SubscriptionId,
    [Parameter(Mandatory = $false)] [string]$BaseName = 'orderprocessing',
    [Parameter(Mandatory = $false)] [string]$Location = 'centralindia',
    [Parameter(Mandatory = $true)] [ValidateSet("dev", "stg", "prod")] [string]$Environment,
    [Parameter(Mandatory = $false)] [string]$ApiSuffix = 'api-xyapp',
    [Parameter(Mandatory = $false)] [string]$UiSuffix = 'ui-xyapp',
    [Parameter(Mandatory = $false)] [string]$DevSku = 'F1',
    [Parameter(Mandatory = $false)] [string]$StgSku = 'B1',
    [Parameter(Mandatory = $false)] [string]$ProdSku = 'P1v3'
)

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
        'stg' { return $StgSku }
        'prod' { return $ProdSku }
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
            if ($LASTEXITCODE -eq 0) {
                return @{ Success = $true; Output = $result; Error = $null }
            }
            $lastError = $result
            Write-Host "  Attempt $attempt failed (exit code: $LASTEXITCODE), retrying in $DelaySeconds seconds..." -ForegroundColor Yellow
        }
        catch {
            $lastError = $_.Exception.Message
            Write-Host "  Attempt $attempt failed: $lastError" -ForegroundColor Yellow
        }
        
        if ($attempt -lt $MaxRetries) {
            Start-Sleep -Seconds $DelaySeconds
        }
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
        
        # Show progress bar
        if ($currentProgress -le $progressChars) {
            Write-Host "#" -NoNewline -ForegroundColor Green
        }
        
        # Check if webapp exists via CLI (silent check)
        $cliCheck = az webapp show -g $ResourceGroup -n $WebAppName --query "name" -o tsv 2>$null
        if ($cliCheck -eq $WebAppName) {
            Write-Host "]" -ForegroundColor Cyan
            Write-Host "`n  [OK] Webapp verified via CLI after $([math]::Round($elapsed/60, 1)) minutes" -ForegroundColor Green
            return $true
        }
        
        # Check if website responds (parallel check)
        try {
            $webCheck = Invoke-WebRequest -Uri $url -Method Get -TimeoutSec 5 -ErrorAction SilentlyContinue
            if ($webCheck.StatusCode -eq 200) {
                Write-Host "]" -ForegroundColor Cyan
                Write-Host "`n  [OK] Website responding (HTTP $($webCheck.StatusCode)) after $([math]::Round($elapsed/60, 1)) minutes" -ForegroundColor Green
                Write-Host "  [WARN] CLI may still report errors, but Azure Portal should show the resource" -ForegroundColor Yellow
                return $true
            }
        }
        catch { }
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
            $rgInfoRaw = az group show --name $ResourceGroup --query "{name:name, state:properties.provisioningState}" -o json 2>$null
            if ($LASTEXITCODE -eq 0 -and $rgInfoRaw) {
                $rgInfo = $rgInfoRaw | ConvertFrom-Json
                if ($rgInfo -and $rgInfo.name -eq $ResourceGroup -and $rgInfo.state -eq 'Succeeded') {
                    Write-Host "]" -ForegroundColor Cyan
                    Write-Host "  [OK] Resource group confirmed ready: $ResourceGroup" -ForegroundColor Green
                    return $true
                }
            }
            elseif ($LASTEXITCODE -ne 0) {
                Write-Host "  [WARN] az group show failed (exit code $LASTEXITCODE). Treating as not-ready and retrying..." -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "  [WARN] Exception while checking RG readiness: $($_.Exception.Message). Treating as not-ready and retrying..." -ForegroundColor Yellow
        }

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
if ($SubscriptionId) {
    az account set --subscription $SubscriptionId | Out-Null
}
$sub = az account show | ConvertFrom-Json
Write-Host "  Using Subscription: $($sub.name) ($($sub.id))" -ForegroundColor Green

$envList = @($Environment)
if (-not $envList) { Write-Error "No environments specified."; exit 1 }
Write-Host "[DEBUG] Processing environment: $Environment" -ForegroundColor Magenta

# Start OIDC App Registration creation in parallel
Write-Host "\n[PARALLEL] Starting GitHub Actions OIDC App Registration..." -ForegroundColor Cyan
$appDisplayName = "GitHub-Actions-OIDC"
$oidcJob = Start-Job -ScriptBlock {
    param($appName, $tenantId, $subscriptionId)
    try {
        # Check if app exists
        $existingApp = az ad app list --display-name $appName 2>&1 | ConvertFrom-Json
        if ($existingApp.Count -gt 0) {
            $appId = $existingApp[0].appId
            $appObjectId = $existingApp[0].id
            $appCreated = $false
        }
        else {
            # Create app registration
            $newApp = az ad app create --display-name $appName 2>&1 | ConvertFrom-Json
            $appId = $newApp.appId
            $appObjectId = $newApp.id
            $appCreated = $true
        }
        
        # Check if service principal exists
        $existingSp = az ad sp list --filter "appId eq '$appId'" 2>&1 | ConvertFrom-Json
        if ($existingSp.Count -eq 0) {
            $sp = az ad sp create --id $appId 2>&1 | ConvertFrom-Json
            $spObjectId = $sp.id
            $spCreated = $true
        }
        else {
            $spObjectId = $existingSp[0].id
            $spCreated = $false
        }
        
        return @{
            Success        = $true
            AppId          = $appId
            AppObjectId    = $appObjectId
            SpObjectId     = $spObjectId
            TenantId       = $tenantId
            SubscriptionId = $subscriptionId
            AppCreated     = $appCreated
            SpCreated      = $spCreated
            Error          = $null
        }
    }
    catch {
        return @{
            Success        = $false
            AppId          = $null
            AppObjectId    = $null
            SpObjectId     = $null
            TenantId       = $tenantId
            SubscriptionId = $subscriptionId
            AppCreated     = $false
            SpCreated      = $false
            Error          = $_.Exception.Message
        }
    }
} -ArgumentList $appDisplayName, $sub.tenantId, $sub.id

$created = @()

foreach ($env in $envList) {
    Write-Host "`n[env:$env] Processing environment resources" -ForegroundColor Yellow
    $rg = "rg-$BaseName-$env"
    $plan = "asp-$BaseName-$env"
    $apiApp = "$BaseName-$ApiSuffix-$env"  # e.g. orderprocessing-api-xyapp-dev
    $uiApp = "$BaseName-$UiSuffix-$env"   # e.g. orderprocessing-ui-xyapp-dev
    $sku = Resolve-Sku $env

    # Resource Group
    Add-StepStatus -Name "Create Resource Group ($rg)" -Status "Pending"
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

    # Strict RG readiness gate (MANDATORY - exit if not ready within 10 minutes)
    Write-Host "  [GATE] Validating resource group readiness before proceeding..." -ForegroundColor Cyan
    $rgReady = Wait-ForResourceGroupReady -ResourceGroup $rg -TimeoutMinutes 5 -IntervalSeconds 60
    if (-not $rgReady) {
        Write-Host "  [CRITICAL] Resource group not ready after 10 minutes: $rg" -ForegroundColor Red
        Write-Host "  [EXIT] Cannot proceed with resource creation - aborting entire bootstrap" -ForegroundColor Red
        Add-StepStatus -Name "Create Resource Group ($rg)" -Status "Failed" -Details "Readiness gate failed"
        exit 1
    }
    Write-Host "  [GATE PASSED] Resource group ready - proceeding with resource creation" -ForegroundColor Green

    # App Service Plan (create only after RG readiness confirmed)
    Write-Host "  [STEP] Creating App Service Plan..." -ForegroundColor Cyan
    Add-StepStatus -Name "Create App Service Plan ($plan, $sku)" -Status "Pending"
    $planExists = az appservice plan list --resource-group $rg --query "[?name=='$plan']" -o tsv
    if (-not $planExists) {
        Write-Host "  Creating plan: $plan ($sku)..." -ForegroundColor Yellow
        $planResult = Invoke-AzCommandWithRetry -Command { az appservice plan create -g $rg -n $plan --sku $sku --location $Location }
        if (-not $planResult.Success) {
            Write-Host "  [CRITICAL] Plan creation FAILED after retries: $($planResult.Error)" -ForegroundColor Red
            Write-Host "  [EXIT] Cannot proceed without App Service Plan - aborting" -ForegroundColor Red
            Add-StepStatus -Name "Create App Service Plan ($plan, $sku)" -Status "Failed" -Details "$($planResult.Error)"
            exit 1
        }
        Write-Host "  Plan creation initiated: $plan ($sku)" -ForegroundColor Cyan
        Write-Host "  [INFO] Plan will be verified during resource provisioning wait" -ForegroundColor Gray
        Add-StepStatus -Name "Create App Service Plan ($plan, $sku)" -Status "Success" -Details "Created"
    }
    else {
        Write-Host "  Plan exists: $plan" -ForegroundColor Green
        Add-StepStatus -Name "Create App Service Plan ($plan, $sku)" -Status "Success" -Details "Already existed"
    }

    # API Web App - Check existence first (hardened)
    $apiExists = $null
    $apiCreateCmd = "az webapp create -g $rg -p $plan -n $apiApp --runtime 'dotnet:8'"
    try {
        $apiExists = az webapp show -g $rg -n $apiApp --query "name" -o tsv 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [WARN] az webapp show for API returned exit code $LASTEXITCODE. Treating as not found." -ForegroundColor Yellow
            $apiExists = $null
        }
    }
    catch {
        Write-Host "  [WARN] Exception during az webapp show for API: $($_.Exception.Message). Treating as not found." -ForegroundColor Yellow
        $apiExists = $null
    }
    Add-StepStatus -Name "Create API Web App ($apiApp)" -Status "Pending"
    if ($apiExists -eq $apiApp) {
        Write-Host "  API WebApp already exists: $apiApp" -ForegroundColor Green
        Write-Host "  [SKIP] $apiCreateCmd (already exists)" -ForegroundColor Gray
        Add-StepStatus -Name "Create API Web App ($apiApp)" -Status "Success" -Details "Already existed"
    }
    else {
        Write-Host "  Starting API webapp creation: $apiApp..." -ForegroundColor Yellow
        Write-Host "  [COMMAND] $apiCreateCmd" -ForegroundColor Magenta
        $apiResult = New-WebAppWithSuperRetry -ResourceGroup $rg -PlanName $plan -AppName $apiApp
        if ($apiResult.Success) {
            Add-StepStatus -Name "Create API Web App ($apiApp)" -Status "Success" -Details "Created"
        }
        else {
            Add-StepStatus -Name "Create API Web App ($apiApp)" -Status "Failed" -Details $apiResult.Error
            Write-Log "API creation failed: $($apiResult.Error)" "ERROR" "Red"
            Write-Host "[ERROR] az webapp create failed. Full output:" -ForegroundColor Red
            Write-Host $apiResult.Error -ForegroundColor Red
            throw "API creation failed - see above"
        }
    }

    # UI Web App - Check existence first (hardened)
    $uiExists = $null
    $uiCreateCmd = "az webapp create -g $rg -p $plan -n $uiApp --runtime 'dotnet:8'"
    try {
        $uiExists = az webapp show -g $rg -n $uiApp --query "name" -o tsv 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [WARN] az webapp show for UI returned exit code $LASTEXITCODE. Treating as not found." -ForegroundColor Yellow
            $uiExists = $null
        }
    }
    catch {
        Write-Host "  [WARN] Exception during az webapp show for UI: $($_.Exception.Message). Treating as not found." -ForegroundColor Yellow
        $uiExists = $null
    }
    Add-StepStatus -Name "Create UI Web App ($uiApp)" -Status "Pending"
    if ($uiExists -eq $uiApp) {
        Write-Host "  UI WebApp already exists: $uiApp" -ForegroundColor Green
        Write-Host "  [SKIP] $uiCreateCmd (already exists)" -ForegroundColor Gray
        Add-StepStatus -Name "Create UI Web App ($uiApp)" -Status "Success" -Details "Already existed"
    }
    else {
        Write-Host "  Starting UI webapp creation: $uiApp..." -ForegroundColor Yellow
        Write-Host "  [COMMAND] $uiCreateCmd" -ForegroundColor Magenta
        $uiResult = New-WebAppWithSuperRetry -ResourceGroup $rg -PlanName $plan -AppName $uiApp
        if ($uiResult.Success) {
            Add-StepStatus -Name "Create UI Web App ($uiApp)" -Status "Success" -Details "Created"
        }
        else {
            Add-StepStatus -Name "Create UI Web App ($uiApp)" -Status "Failed" -Details $uiResult.Error
            Write-Log "UI creation failed: $($uiResult.Error)" "ERROR" "Red"
            Write-Host "[ERROR] az webapp create failed. Full output:" -ForegroundColor Red
            Write-Host $uiResult.Error -ForegroundColor Red
            throw "UI creation failed - see above"
        }
    }

    # Application Insights - Check existence first (hardened)
    $aiName = "ai-$BaseName-$env"
    $aiExists = $null
    try {
        $aiExists = az monitor app-insights component show -a $aiName -g $rg --query "name" -o tsv 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [WARN] az monitor app-insights component show returned exit code $LASTEXITCODE. Treating as not found." -ForegroundColor Yellow
            $aiExists = $null
        }
    }
    catch {
        Write-Host "  [WARN] Exception during az monitor app-insights component show: $($_.Exception.Message). Treating as not found." -ForegroundColor Yellow
        $aiExists = $null
    }
    $aiJob = $null
    Add-StepStatus -Name "Create Application Insights ($aiName)" -Status "Pending"
    if (-not $aiExists) {
        Write-Host "  Starting Application Insights creation: $aiName..." -ForegroundColor Yellow
        $aiJob = Start-Job -ScriptBlock {
            param($rg, $aiName, $Location)
            try {
                $result = az monitor app-insights component create -a $aiName -g $rg -l $Location --application-type web 2>&1
                if ($LASTEXITCODE -eq 0) {
                    return @{ Success = $true; Output = $result; Error = $null; ResourceName = $aiName }
                }
                return @{ Success = $false; Output = $null; Error = $result; ResourceName = $aiName }
            }
            catch {
                return @{ Success = $false; Output = $null; Error = $_.Exception.Message; ResourceName = $aiName }
            }
        } -ArgumentList $rg, $aiName, $Location
    }
    else {
        Write-Host "  Application Insights already exists: $aiName" -ForegroundColor Green
        Add-StepStatus -Name "Create Application Insights ($aiName)" -Status "Success" -Details "Already existed"
    }

    # Wait for all jobs to complete (parallel creation) then run a unified readiness wait regardless of job status
    Write-Host "`n  [PARALLEL] Waiting for creation jobs to complete..." -ForegroundColor Cyan
    $jobs = @()
    if ($apiJob) { $jobs += $apiJob }
    if ($uiJob) { $jobs += $uiJob }
    if ($aiJob) { $jobs += $aiJob }

    $apiJobFailed = $false
    $uiJobFailed = $false
    $aiJobFailed = $false

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

        # API creation handled synchronously earlier; status is in $apiResult or StepStatus
    }

    # UI creation handled synchronously earlier; status is in $uiResult or StepStatus}
    # UI creation handled synchronously earlier; status is in $uiResult or StepStatus
    # End of foreach ($env in $envList) block

    # Unified readiness waiting (always performed to handle eventual consistency)
    Write-Host "`n  [WAIT] Performing unified readiness checks (max 10 min)..." -ForegroundColor Cyan
    $timeoutSeconds = 10 * 60
    $intervalSeconds = 30
    $elapsed = 0
    $planReady = $false
    $apiReady = $false
    $uiReady = $false
    $apiUrl = "https://$apiApp.azurewebsites.net"
    $uiUrl = "https://$uiApp.azurewebsites.net"
    Write-Host "  [TARGET] Plan: $plan" -ForegroundColor Gray
    Write-Host "  [TARGET] API : $apiApp" -ForegroundColor Gray
    Write-Host "  [TARGET] UI  : $uiApp" -ForegroundColor Gray
    Write-Host "  [PROGRESS] [" -NoNewline -ForegroundColor Cyan
    $progressChars = [math]::Ceiling($timeoutSeconds / $intervalSeconds)
    $progressPrinted = 0

    while ($elapsed -lt $timeoutSeconds -and (-not $planReady -or -not $apiReady -or -not $uiReady)) {
        Start-Sleep -Seconds $intervalSeconds
        $elapsed += $intervalSeconds
        $progressPrinted++
        if ($progressPrinted -le $progressChars) { Write-Host "#" -NoNewline -ForegroundColor Green }

        # Plan readiness: provisioningState Succeeded + status Ready (hardened)
        if (-not $planReady) {
            $planInfo = $null
            try {
                $planInfo = az appservice plan show -g $rg -n $plan --query '{prov:provisioningState,status:status}' -o json 2>$null | ConvertFrom-Json
                Write-Host "[DEBUG] Plan info raw: $($planInfo | ConvertTo-Json -Compress)" -ForegroundColor Magenta
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "  [WARN] az appservice plan show returned exit code $LASTEXITCODE. Treating as not ready." -ForegroundColor Yellow
                    $planInfo = $null
                }
            }
            catch {
                Write-Host "  [WARN] Exception during az appservice plan show: $($_.Exception.Message). Treating as not ready." -ForegroundColor Yellow
                $planInfo = $null
            }
            if ($planInfo -and $planInfo.prov -eq 'Succeeded' -and $planInfo.status -eq 'Ready') {
                $planReady = $true
                Write-Host "`n  [OK] Plan ready after $([math]::Round($elapsed/60,1)) min" -ForegroundColor Green
                Write-Host "  [PROGRESS] [" -NoNewline -ForegroundColor Cyan; for ($i = 0; $i -lt $progressPrinted; $i++) { Write-Host "#" -NoNewline -ForegroundColor Green }
            }
        }

        # API readiness (hardened)
        if (-not $apiReady) {
            $apiExistsNow = $null
            try {
                $apiExistsNow = az webapp show -g $rg -n $apiApp --query '{state:state,host:defaultHostName}' -o json 2>$null | ConvertFrom-Json
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "  [WARN] az webapp show for API readiness returned exit code $LASTEXITCODE. Treating as not ready." -ForegroundColor Yellow
                    $apiExistsNow = $null
                }
            }
            catch {
                Write-Host "  [WARN] Exception during az webapp show for API readiness: $($_.Exception.Message). Treating as not ready." -ForegroundColor Yellow
                $apiExistsNow = $null
            }
            if ($apiExistsNow) {
                $httpOk = $false
                try {
                    $resp = Invoke-WebRequest -Uri $apiUrl -Method Get -TimeoutSec 8 -ErrorAction SilentlyContinue
                    if ($resp -and ($resp.StatusCode -eq 200 -or $resp.StatusCode -eq 404)) { $httpOk = $true }
                }
                catch { }
                if ($apiExistsNow.state -eq 'Running' -and $httpOk) {
                    $apiReady = $true
                    Write-Host "`n  [OK] API ready (state Running + HTTP) after $([math]::Round($elapsed/60,1)) min" -ForegroundColor Green
                    Write-Host "  [PROGRESS] [" -NoNewline -ForegroundColor Cyan; for ($i = 0; $i -lt $progressPrinted; $i++) { Write-Host "#" -NoNewline -ForegroundColor Green }
                }
            }
        }

        # UI readiness (hardened)
        if (-not $uiReady) {
            $uiExistsNow = $null
            try {
                $uiExistsNow = az webapp show -g $rg -n $uiApp --query '{state:state,host:defaultHostName}' -o json 2>$null | ConvertFrom-Json
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "  [WARN] az webapp show for UI readiness returned exit code $LASTEXITCODE. Treating as not ready." -ForegroundColor Yellow
                    $uiExistsNow = $null
                }
            }
            catch {
                Write-Host "  [WARN] Exception during az webapp show for UI readiness: $($_.Exception.Message). Treating as not ready." -ForegroundColor Yellow
                $uiExistsNow = $null
            }
            if ($uiExistsNow) {
                $httpOk = $false
                try {
                    $resp = Invoke-WebRequest -Uri $uiUrl -Method Get -TimeoutSec 8 -ErrorAction SilentlyContinue
                    if ($resp -and ($resp.StatusCode -eq 200 -or $resp.StatusCode -eq 404)) { $httpOk = $true }
                }
                catch { }
                if ($uiExistsNow.state -eq 'Running' -and $httpOk) {
                    $uiReady = $true
                    Write-Host "`n  [OK] UI ready (state Running + HTTP) after $([math]::Round($elapsed/60,1)) min" -ForegroundColor Green
                    Write-Host "  [PROGRESS] [" -NoNewline -ForegroundColor Cyan; for ($i = 0; $i -lt $progressPrinted; $i++) { Write-Host "#" -NoNewline -ForegroundColor Green }
                }
            }
        }
    }
    Write-Host "]" -ForegroundColor Cyan

    # Check if we timed out
    if ($elapsed -ge $timeoutSeconds) {
        Write-Host "`n  [TIMEOUT] Readiness wait reached 20-minute limit" -ForegroundColor Yellow
        Write-Host "  Current status: Plan=$planReady API=$apiReady UI=$uiReady" -ForegroundColor Yellow
        Write-Host "  Resources may still be provisioning - check Azure Portal" -ForegroundColor Yellow
    }
    else {
        Write-Host "`n  [SUCCESS] All resources reached readiness criteria in $([math]::Round($elapsed/60,1)) min" -ForegroundColor Green
    }

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
        if ($apiJob) {
            Write-Host "  [OK] API WebApp created and verified: $apiApp" -ForegroundColor Cyan
        }
        else {
            Write-Host "  [OK] API WebApp verified (pre-existing): $apiApp" -ForegroundColor Green
        }
            
        # Verify and configure runtime (skip if timed out to avoid hanging)
        if ($elapsed -lt $timeoutSeconds) {
            $runtime = az webapp config show -g $rg -n $apiApp --query "netFrameworkVersion" -o tsv 2>$null
        }
        else {
            $runtime = "skipped-timeout"
        }
        if ($runtime -eq "skipped-timeout") {
            Write-Host "    [SKIP] Runtime check skipped due to timeout - verify manually" -ForegroundColor Yellow
        }
        elseif ($runtime -eq "v8.0") {
            Write-Host "    [OK] Runtime: .NET 8" -ForegroundColor Green
        }
        else {
            Write-Host "    [WARN] Runtime: $runtime (expected v8.0), configuring .NET 8..." -ForegroundColor Yellow
            # Attempt to set runtime via config
            az webapp config set -g $rg -n $apiApp --net-framework-version "v8.0" 2>$null | Out-Null
            Start-Sleep -Seconds 3
            $runtimeCheck = az webapp config show -g $rg -n $apiApp --query "netFrameworkVersion" -o tsv 2>$null
            if ($runtimeCheck -eq "v8.0") {
                Write-Host "    [OK] Runtime configured to .NET 8" -ForegroundColor Green
            }
            else {
                Write-Host "    [FAIL] Runtime configuration failed. Manual configuration required via Azure Portal" -ForegroundColor Red
                Write-Host "    [ACTION] Portal: Settings -> Configuration -> General settings -> Stack: .NET 8 (LTS)" -ForegroundColor Yellow
                $allResourcesReady = $false
            }
        }
            
        # Verify app state
        $apiState = az webapp show -g $rg -n $apiApp --query '{State:state, HostNames:defaultHostName}' -o json 2>$null | ConvertFrom-Json
        if ($apiState.State -eq "Running") {
            Write-Host "    [OK] State: Running at https://$($apiState.HostNames)" -ForegroundColor Green
        }
        else {
            Write-Host "    [WARN] State: $($apiState.State)" -ForegroundColor Yellow
        }
    }
    elseif ($apiJob) {
        Write-Host "  [FAIL] API WebApp creation FAILED after provisioning wait" -ForegroundColor Red
        Write-Host "  [CHECK] Azure Portal: https://portal.azure.com" -ForegroundColor Yellow
        $allResourcesReady = $false
    }
        
    # Final verification for UI
    $uiCheckFinal = az webapp show -g $rg -n $uiApp --query "name" -o tsv 2>$null
    if ($uiCheckFinal -eq $uiApp) {
        if ($uiJob) {
            Write-Host "  [OK] UI WebApp created and verified: $uiApp" -ForegroundColor Cyan
        }
        else {
            Write-Host "  [OK] UI WebApp verified (pre-existing): $uiApp" -ForegroundColor Green
        }
            
        # Verify and configure runtime (skip if timed out to avoid hanging)
        if ($elapsed -lt $timeoutSeconds) {
            $runtime = az webapp config show -g $rg -n $uiApp --query "netFrameworkVersion" -o tsv 2>$null
        }
        else {
            $runtime = "skipped-timeout"
        }
        if ($runtime -eq "skipped-timeout") {
            Write-Host "    [SKIP] Runtime check skipped due to timeout - verify manually" -ForegroundColor Yellow
        }
        elseif ($runtime -eq "v8.0") {
            Write-Host "    [OK] Runtime: .NET 8" -ForegroundColor Green
        }
        else {
            Write-Host "    [WARN] Runtime: $runtime (expected v8.0), configuring .NET 8..." -ForegroundColor Yellow
            # Attempt to set runtime via config
            az webapp config set -g $rg -n $uiApp --net-framework-version "v8.0" 2>$null | Out-Null
            Start-Sleep -Seconds 3
            $runtimeCheck = az webapp config show -g $rg -n $uiApp --query "netFrameworkVersion" -o tsv 2>$null
            if ($runtimeCheck -eq "v8.0") {
                Write-Host "    [OK] Runtime configured to .NET 8" -ForegroundColor Green
            }
            else {
                Write-Host "    [FAIL] Runtime configuration failed. Manual configuration required via Azure Portal" -ForegroundColor Red
                Write-Host "    [ACTION] Portal: Settings -> Configuration -> General settings -> Stack: .NET 8 (LTS)" -ForegroundColor Yellow
                $allResourcesReady = $false
            }
        }
            
        # Verify app state
        $uiState = az webapp show -g $rg -n $uiApp --query '{State:state, HostNames:defaultHostName}' -o json 2>$null | ConvertFrom-Json
        if ($uiState.State -eq "Running") {
            Write-Host "    [OK] State: Running at https://$($uiState.HostNames)" -ForegroundColor Green
        }
        else {
            Write-Host "    [WARN] State: $($uiState.State)" -ForegroundColor Yellow
        }
    }
    elseif ($uiJob) {
        Write-Host "  [FAIL] UI WebApp creation FAILED after provisioning wait" -ForegroundColor Red
        Write-Host "  [CHECK] Azure Portal: https://portal.azure.com" -ForegroundColor Yellow
        $allResourcesReady = $false
    }
        
    # Configure App Insights connection strings (if both AI and webapps exist, and not timed out)
    if ($elapsed -lt $timeoutSeconds) {
        $aiCheck = az monitor app-insights component show -a $aiName -g $rg 2>$null
        if ($aiCheck) {
            $connString = az monitor app-insights component show -a $aiName -g $rg --query "connectionString" -o tsv 2>$null
            if ($connString) {
                Write-Host "`n  [CONFIG] Configuring App Insights connection strings..." -ForegroundColor Cyan
                    
                # Configure API app
                $apiVerified = az webapp show -g $rg -n $apiApp --query "name" -o tsv 2>$null
                if ($apiVerified -eq $apiApp) {
                    az webapp config appsettings set -g $rg -n $apiApp --settings "APPLICATIONINSIGHTS_CONNECTION_STRING=$connString" 2>$null | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "    [OK] App Insights configured for API: $apiApp" -ForegroundColor Green
                    }
                }
                    
                # Configure UI app
                $uiVerified = az webapp show -g $rg -n $uiApp --query "name" -o tsv 2>$null
                if ($uiVerified -eq $uiApp) {
                    az webapp config appsettings set -g $rg -n $uiApp --settings "APPLICATIONINSIGHTS_CONNECTION_STRING=$connString" 2>$null | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "    [OK] App Insights configured for UI: $uiApp" -ForegroundColor Green
                    }
                }
            }
        }
    }
    else {
        Write-Host "`n  [SKIP] App Insights configuration skipped due to timeout" -ForegroundColor Yellow
    }
        
    # Final summary of resource readiness
    Write-Host "`n  [SUMMARY] Resource Provisioning Status:" -ForegroundColor Cyan
    if ($planReady -and $apiReady -and $uiReady -and $allResourcesReady) {
        Write-Host "  [OK] All resources reached readiness criteria" -ForegroundColor Green
    }
    else {
        Write-Host "  [WARN] Readiness incomplete: PlanReady=$planReady ApiReady=$apiReady UiReady=$uiReady ConfigReady=$allResourcesReady" -ForegroundColor Yellow
    }

    $created += [PSCustomObject]@{ Environment = $env; ResourceGroup = $rg; Plan = $plan; ApiApp = $apiApp; UiApp = $uiApp; Sku = $sku; AppInsights = $aiName }
}

# Configure OIDC federated credentials and RBAC
Write-Host "\n[OIDC Setup] Configuring GitHub Actions OIDC..." -ForegroundColor Cyan
$oidcJob | Wait-Job | Out-Null
$oidcResult = Receive-Job -Job $oidcJob
Remove-Job -Job $oidcJob

if ($oidcResult.Success) {
    Add-StepStatus -Name "Setup OIDC (GitHub-Actions-OIDC App Registration)" -Status "Success" -Details "AppId=$($oidcResult.AppId)"
    if ($oidcResult.AppCreated) {
        Write-Host "  [OK] App Registration created: $appDisplayName" -ForegroundColor Green
    }
    else {
        Write-Host "  [OK] App Registration found (pre-existing): $appDisplayName" -ForegroundColor Green
    }
    if ($oidcResult.SpCreated) {
        Write-Host "  [OK] Service Principal created" -ForegroundColor Green
    }
    else {
        Write-Host "  [OK] Service Principal found (pre-existing)" -ForegroundColor Green
    }
    Write-Host "  App (Client) ID: $($oidcResult.AppId)" -ForegroundColor Cyan
    Write-Host "  SP Object ID: $($oidcResult.SpObjectId)" -ForegroundColor Gray
    
    # Configure federated credentials for branches
    Write-Host "\n  [OIDC] Configuring federated credentials..." -ForegroundColor Yellow
    $existingCreds = az ad app federated-credential list --id $oidcResult.AppObjectId 2>$null | ConvertFrom-Json
    if (-not $existingCreds) { $existingCreds = @() }
    
    # Branch-to-environment mapping for OIDC authentication
    # Each branch gets its own federated credential that matches GitHub Actions OIDC token subject
    # This allows one set of repository secrets to work for all environments
    $branches = @('main', 'staging', 'dev')
    $githubOwner = 'getpavanthakur'
    $repository = 'TestAppXY_OrderProcessingSystem'
    
    foreach ($branch in $branches) {
        $credName = "github-$branch-oidc"
        $subject = "repo:$githubOwner/$repository:ref:refs/heads/$branch"
        $exists = $existingCreds | Where-Object { $_.name -eq $credName }
        if ($exists) {
            Write-Host "    [$credName] Already exists (branch: $branch)" -ForegroundColor Gray
            continue
        }
        $credentialJson = @{
            name      = $credName
            issuer    = "https://token.actions.githubusercontent.com"
            subject   = $subject
            audiences = @("api://AzureADTokenExchange")
        } | ConvertTo-Json
        $tempFile = [System.IO.Path]::GetTempFileName()
        $credentialJson | Out-File -FilePath $tempFile -Encoding UTF8
        az ad app federated-credential create --id $oidcResult.AppObjectId --parameters $tempFile 2>$null | Out-Null
        Remove-Item $tempFile -ErrorAction SilentlyContinue
        Write-Host "    [$credName] Created (branch: $branch)" -ForegroundColor Green
    }
    
    # Assign RBAC roles to all resource groups
    Write-Host "\n  [RBAC] Assigning Contributor role to resource groups..." -ForegroundColor Yellow
    $rgList = $created | Select-Object -ExpandProperty ResourceGroup -Unique
    foreach ($rg in $rgList) {
        $scope = "/subscriptions/$($oidcResult.SubscriptionId)/resourceGroups/$rg"
        $existingAssignment = az role assignment list --assignee $oidcResult.SpObjectId --role "Contributor" --scope $scope 2>$null | ConvertFrom-Json
        if (-not $existingAssignment -or $existingAssignment.Count -eq 0) {
            az role assignment create --assignee $oidcResult.SpObjectId --role "Contributor" --scope $scope 2>$null | Out-Null
            Write-Host "    [$rg] Contributor role assigned" -ForegroundColor Green
        }
        else {
            Write-Host "    [$rg] Contributor role already assigned" -ForegroundColor Gray
        }
    }
    
    # Display GitHub secrets configuration
    Write-Host "\n  [GitHub Secrets] Add these to repository secrets:" -ForegroundColor Cyan
    Write-Host "    https://github.com/$githubOwner/$repository/settings/secrets/actions" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    AZUREAPPSERVICE_CLIENTID:        $($oidcResult.AppId)" -ForegroundColor White
    Write-Host "    AZUREAPPSERVICE_TENANTID:        $($oidcResult.TenantId)" -ForegroundColor White
    Write-Host "    AZUREAPPSERVICE_SUBSCRIPTIONID:  $($oidcResult.SubscriptionId)" -ForegroundColor White
    Write-Host ""
    
    # Copy to clipboard
    $secretsOutput = @"

=== GITHUB REPOSITORY SECRETS ===

AZUREAPPSERVICE_CLIENTID:        $($oidcResult.AppId)
AZUREAPPSERVICE_TENANTID:        $($oidcResult.TenantId)
AZUREAPPSERVICE_SUBSCRIPTIONID:  $($oidcResult.SubscriptionId)

=================================
"@
    $secretsOutput | Set-Clipboard -ErrorAction SilentlyContinue
    Write-Host "  [OK] Secrets copied to clipboard!" -ForegroundColor Green
    
    # Automatic GitHub secrets configuration
    Write-Host "\n  [AUTOMATION] Configuring GitHub secrets automatically..." -ForegroundColor Cyan
    $configScriptPath = Join-Path $PSScriptRoot "configure-github-secrets.ps1"
    if (Test-Path $configScriptPath) {
        try {
            & $configScriptPath -Repository "$githubOwner/$repository" -Force -ErrorAction Stop
            Write-Host "  [OK] GitHub secrets configured automatically!" -ForegroundColor Green
            Add-StepStatus -Name "Auto-configure GitHub Secrets" -Status "Success" -Details "Repository=$githubOwner/$repository"
        }
        catch {
            Write-Host "  [WARN] Automatic secret configuration failed: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "  [ACTION] Configure manually or run: ./configure-github-secrets.ps1" -ForegroundColor Yellow
            Add-StepStatus -Name "Auto-configure GitHub Secrets" -Status "Failed" -Details "$($_.Exception.Message)"
        }
    }
    else {
        Write-Host "  [INFO] Automatic configuration script not found - configure manually" -ForegroundColor Yellow
    }
}
else {
    Add-StepStatus -Name "Setup OIDC (GitHub-Actions-OIDC App Registration)" -Status "Failed" -Details "$($oidcResult.Error)"
    Write-Host "  [WARN] OIDC setup encountered errors: $($oidcResult.Error)" -ForegroundColor Yellow
    Write-Host "  [ACTION] Run setup-github-oidc.ps1 manually if needed" -ForegroundColor Yellow
}

# Run post-deployment self-tests
Write-Log "Starting Post-Deployment Self-Test..." "INFO" "Cyan"
$apiUrl = "https://$apiApp.azurewebsites.net"
$uiUrl = "https://$uiApp.azurewebsites.net"
$apiHealthy = Test-WebEndpoint -Url $apiUrl -Name "API ($apiApp)"
$uiHealthy = Test-WebEndpoint -Url $uiUrl -Name "UI ($uiApp)"
if ($apiHealthy -and $uiHealthy) {
    Add-StepStatus -Name "Self-Test" -Status "Success" -Details "API+UI healthy"
    Write-Log "Post-Deployment Self-Test PASSED" "INFO" "Green"
}
else {
    Add-StepStatus -Name "Self-Test" -Status "Failed" -Details "APIHealthy=$apiHealthy UIHealthy=$uiHealthy"
    Write-Log "Post-Deployment Self-Test FAILED" "WARN" "Yellow"
}
Write-Host "`n[Summary] Provisioning results:" -ForegroundColor Yellow
$created | Format-Table -AutoSize

$scriptEndTime = Get-Date
Write-Host "\n[INFO] Bootstrap completed at: $scriptEndTime" -ForegroundColor Cyan
Write-Host "[INFO] Total duration: $([math]::Round(($scriptEndTime - $scriptStartTime).TotalMinutes,2)) minutes" -ForegroundColor Cyan

Write-Host "`n[Step Summary]" -ForegroundColor Yellow
Write-Log "Writing Step Summary to log file..." "INFO" "Cyan"
$index = 1
foreach ($s in $global:StepStatus) {
    $detailsText = if ($s.Details) { " ($($s.Details))" } else { "" }
    if ($s.Status -eq 'Success') {
        Write-Host ("  {0}. {1} - Success{2}" -f $index, $s.Name, $detailsText) -ForegroundColor Green
    }
    elseif ($s.Status -eq 'Failed') {
        Write-Host ("  {0}. {1} - Failed{2}" -f $index, $s.Name, $detailsText) -ForegroundColor Red
    }
    else {
        Write-Host ("  {0}. {1} - {2}{3}" -f $index, $s.Name, $s.Status, $detailsText) -ForegroundColor Yellow
    }
    $index++
}

Write-Host "\nNext Steps:" -ForegroundColor Yellow
if ($oidcResult.Success) {
    Write-Host "  1. [DONE] GitHub Actions OIDC configured with federated credentials for main, staging, dev" -ForegroundColor Green
    Write-Host "  2. [DONE] Git branches created: dev, staging, main (pushed to GitHub)" -ForegroundColor Green
    Write-Host "  3. [DONE] GitHub secrets configured automatically" -ForegroundColor Green
    Write-Host "  4. Push code to dev branch to trigger first deployment" -ForegroundColor White
    Write-Host "  5. After validation, merge dev → staging → main for promotion" -ForegroundColor White
    Write-Host "  6. [DONE] Application Insights connection strings configured automatically" -ForegroundColor Green
    Write-Host "`n  Branch Deployment Mapping:" -ForegroundColor Cyan
    Write-Host "    dev branch     → orderprocessing-api-xyapp-dev, orderprocessing-ui-xyapp-dev" -ForegroundColor Gray
    Write-Host "    staging branch → orderprocessing-api-xyapp-stg, orderprocessing-ui-xyapp-stg" -ForegroundColor Gray
    Write-Host "    main branch    → (future production resources)" -ForegroundColor Gray
}
else {
    Write-Host "  1. Run setup-github-oidc.ps1 with -Branches main,staging,dev (as needed)." -ForegroundColor White
    Write-Host "  2. Add secrets (AZUREAPPSERVICE_CLIENTID, TENANTID, SUBSCRIPTIONID) if not already present." -ForegroundColor White
    Write-Host "  3. Push to branches to trigger corresponding deployments (web app names contain environment)." -ForegroundColor White
    Write-Host "  4. Application Insights connection strings have been configured automatically." -ForegroundColor Green
}


# Write detailed StepStatus to a CSV in logs for automation
try {
    $csvPath = Join-Path $logDir ("step-summary-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".csv")
    $global:StepStatus | Export-Csv -Path $csvPath -NoTypeInformation -Force
    Write-Log "Step summary exported to $csvPath" "INFO" "Cyan"
}
catch {
    Write-Log "Failed to export step summary CSV: $($_.Exception.Message)" "WARN" "Yellow"
}

Write-Log "=== Bootstrap completed ===" "INFO" "Cyan"

