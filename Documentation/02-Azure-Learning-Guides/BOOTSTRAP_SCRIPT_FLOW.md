# bootstrap-enterprise-infra.ps1 - Complete Optimized Flow

**Script Version**: Optimized (November 2025)  
**Purpose**: Automated Azure infrastructure provisioning with parallel execution and integrated OIDC setup  
**Author**: DevOps Team  
**Audience**: Junior developers, operations teams, reviewers

---

## 📋 Table of Contents

1. [Quick Overview](#quick-overview)
2. [Prerequisites](#prerequisites)
3. [Execution Command](#execution-command)
4. [Complete Step-by-Step Flow](#complete-step-by-step-flow)
5. [Detailed Phase Breakdown](#detailed-phase-breakdown)
6. [Verification Checklist](#verification-checklist)
7. [Troubleshooting Guide](#troubleshooting-guide)

---

## Quick Overview

### What This Script Does

This script provisions a complete Azure infrastructure environment with **zero manual intervention** required for OIDC setup. It creates:

- ✅ Resource Groups (per environment: dev, stg, prod)
- ✅ App Service Plans (with SKU mapping per environment)
- ✅ API WebApps (.NET 8 runtime)
- ✅ UI WebApps (.NET 8 runtime)
- ✅ Application Insights (monitoring)
- ✅ GitHub Actions OIDC App Registration
- ✅ Service Principal with Contributor role
- ✅ Federated Credentials (main, staging, dev branches)
- ✅ Application Insights connection strings

### Execution Time

- **Best Case**: 5-6 minutes (when all parallel jobs succeed)
- **Worst Case**: 20-21 minutes (when jobs fail and full wait period is needed)

### Key Optimizations

- 🚀 **Parallel Execution**: Multiple resources created simultaneously
- 🔄 **Retry Logic**: 3 attempts with 10-second delays for transient errors
- ⏱️ **Intelligent Wait**: 20-minute consolidated wait with 30-second interval checks
- ✅ **Pre-existence Checks**: Safe re-runs without false failures
- 🎯 **Auto-configuration**: Automatic .NET 8 runtime setup
- 📋 **Clipboard Integration**: GitHub secrets auto-copied

---

## Prerequisites

### Required Tools

```powershell
# Verify Azure CLI is installed
az version

# Expected output:
# {
#   "azure-cli": "2.x.x",
#   "azure-cli-core": "2.x.x",
#   ...
# }
```

### Required Permissions

- Azure subscription with **Owner** or **Contributor + User Access Administrator** roles
- Permission to create App Registrations in Azure AD/Entra ID
- Permission to create Service Principals

### Login & Subscription

```powershell
# Login to Azure
az login

# List subscriptions
az account list --output table

# Select subscription
az account set --subscription "<SUBSCRIPTION_ID>"

# Verify current subscription
az account show --query "{Name:name, ID:id, TenantID:tenantId}" --output table
```

---

## Execution Command

### Basic Syntax

```powershell
./Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1 `
  -BaseName orderprocessing `
  -Location centralindia `
  -Environments dev
```

### Full Syntax with All Parameters

```powershell
./Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1 `
  -SubscriptionId "<SUBSCRIPTION_ID>" `
  -BaseName orderprocessing `
  -Location centralindia `
  -Environments dev,stg,prod `
  -ApiSuffix api-xyapp `
  -UiSuffix ui-xyapp `
  -DevSku F1 `
  -StgSku B1 `
  -ProdSku P1v3
```

### Parameter Descriptions

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `SubscriptionId` | No | Current subscription | Azure subscription ID |
| `BaseName` | No | `orderprocessing` | Base name for all resources |
| `Location` | No | `eastus` | Azure region |
| `Environments` | No | `dev,stg,prod` | Comma-separated list of environments |
| `ApiSuffix` | No | `api-xyapp` | Suffix for API webapp names |
| `UiSuffix` | No | `ui-xyapp` | Suffix for UI webapp names |
| `DevSku` | No | `F1` | App Service Plan SKU for dev |
| `StgSku` | No | `B1` | App Service Plan SKU for staging |
| `ProdSku` | No | `P1v3` | App Service Plan SKU for production |

---

## Complete Step-by-Step Flow

### Phase 0: Initialization (Lines 140-149)

```
[0/7] Selecting subscription...
  Using Subscription: {subscription-name} ({subscription-id})
```

**What Happens**:
1. Sets Azure subscription (if `-SubscriptionId` provided)
2. Retrieves current subscription details via `az account show`
3. Parses environment list from `-Environments` parameter
4. Validates at least one environment is specified
5. Initializes empty tracking array `$created = @()`

**Output Variables**:
- `$sub` = Subscription object (name, id, tenantId)
- `$envList` = Array of environments (e.g., `['dev', 'stg', 'prod']`)
- `$created` = Tracking array for provisioned resources

---

### Phase 1: Parallel OIDC Job Start (Lines 150-201)

```
[PARALLEL] Starting GitHub Actions OIDC App Registration...
```

**What Happens**:
1. **Starts PowerShell Background Job** (non-blocking)
2. Inside the job:
   - Checks if App Registration `GitHub-Actions-OIDC` exists
   - Creates App Registration if missing
   - Checks if Service Principal exists for the App ID
   - Creates Service Principal if missing
   - Returns: `AppId`, `AppObjectId`, `SpObjectId`, `TenantId`, `SubscriptionId`, status flags

**Key Commands in Job**:
```powershell
az ad app list --display-name "GitHub-Actions-OIDC"
az ad app create --display-name "GitHub-Actions-OIDC"
az ad sp list --filter "appId eq '<APP_ID>'"
az ad sp create --id <APP_ID>
```

**Output Variables**:
- `$oidcJob` = Background job reference (continues running while script proceeds)

**⏱️ Timeline**: Starts immediately, runs in parallel with all phases below

---

### Phase 2: Environment Loop Processing

The script loops through each environment (dev, stg, prod). All steps below repeat for **each environment**.

---

#### Step 2.1: Resource Group Creation (Lines 214-220)

```
[env:dev] Processing environment resources
  RG created: rg-orderprocessing-dev
```

**What Happens**:
1. Constructs resource group name: `rg-{BaseName}-{env}`
2. Checks if resource group exists: `az group exists -n rg-orderprocessing-dev`
3. If **NOT exists**: Creates with tags
   - Command: `az group create -n rg-orderprocessing-dev -l centralindia --tags env=dev app=orderprocessing`
4. If **exists**: Skips creation, logs "RG exists"

**Timeline**: ~1-2 seconds (synchronous)

**Output Variables**:
- `$rg` = Resource group name (e.g., `rg-orderprocessing-dev`)

---

#### Step 2.2: App Service Plan Creation (Lines 222-233)

```
  Creating plan: asp-orderprocessing-dev (F1)...
  Plan creation initiated: asp-orderprocessing-dev (F1)
  [INFO] Plan will be verified during resource provisioning wait
```

**What Happens**:
1. Constructs plan name: `asp-{BaseName}-{env}`
2. Determines SKU based on environment:
   - `dev` → F1 (Free)
   - `stg` → B1 (Basic)
   - `prod` → P1v3 (Premium)
3. Checks if plan exists: `az appservice plan list --resource-group rg-orderprocessing-dev --query "[?name=='asp-orderprocessing-dev']"`
4. If **NOT exists**:
   - Creates plan with **retry logic** (3 attempts, 10-second delays)
   - Command: `az appservice plan create -g rg-orderprocessing-dev -n asp-orderprocessing-dev --sku F1 --location centralindia`
   - **NO immediate verification** (removed 5-second wait optimization)
5. If **exists**: Skips creation

**Retry Logic**:
```powershell
Attempt 1: az appservice plan create...
  → If exit code = 0: Success
  → If exit code ≠ 0: Wait 10 seconds, retry
Attempt 2: az appservice plan create...
  → If exit code = 0: Success
  → If exit code ≠ 0: Wait 10 seconds, retry
Attempt 3: az appservice plan create...
  → If exit code = 0: Success
  → If exit code ≠ 0: FAIL, continue to next environment
```

**Timeline**: ~2-5 seconds (synchronous with retries)

**Output Variables**:
- `$plan` = Plan name (e.g., `asp-orderprocessing-dev`)
- `$sku` = SKU (e.g., `F1`)

---

#### Step 2.3: API WebApp - Parallel Job (Lines 235-268)

```
  Starting API webapp creation: orderprocessing-api-xyapp-dev...
```

**What Happens**:
1. Constructs API app name: `{BaseName}-{ApiSuffix}-{env}`
2. Checks if webapp exists: `az webapp show -g rg-orderprocessing-dev -n orderprocessing-api-xyapp-dev`
3. If **NOT exists**:
   - **Starts PowerShell Background Job** (non-blocking)
   - Inside the job (retry logic with 3 attempts, 10-second delays):
     ```powershell
     az webapp create `
       -g rg-orderprocessing-dev `
       -n orderprocessing-api-xyapp-dev `
       --plan asp-orderprocessing-dev `
       --runtime "dotnet:8"
     ```
   - Returns: `{Success, Output, Error, ResourceName}`
4. If **exists**: Skips creation, logs "already exists"

**Timeline**: Starts immediately, runs in background (~2-4 minutes typically)

**Output Variables**:
- `$apiApp` = API webapp name (e.g., `orderprocessing-api-xyapp-dev`)
- `$apiJob` = Background job reference (or `$null` if pre-existing)

---

#### Step 2.4: UI WebApp - Parallel Job (Lines 270-303)

```
  Starting UI webapp creation: orderprocessing-ui-xyapp-dev...
```

**What Happens**:
1. Constructs UI app name: `{BaseName}-{UiSuffix}-{env}`
2. Checks if webapp exists: `az webapp show -g rg-orderprocessing-dev -n orderprocessing-ui-xyapp-dev`
3. If **NOT exists**:
   - **Starts PowerShell Background Job** (non-blocking)
   - Inside the job (retry logic with 3 attempts, 10-second delays):
     ```powershell
     az webapp create `
       -g rg-orderprocessing-dev `
       -n orderprocessing-ui-xyapp-dev `
       --plan asp-orderprocessing-dev `
       --runtime "dotnet:8"
     ```
   - Returns: `{Success, Output, Error, ResourceName}`
4. If **exists**: Skips creation, logs "already exists"

**Timeline**: Starts immediately, runs in background (~2-4 minutes typically)

**Output Variables**:
- `$uiApp` = UI webapp name (e.g., `orderprocessing-ui-xyapp-dev`)
- `$uiJob` = Background job reference (or `$null` if pre-existing)

---

#### Step 2.5: Application Insights - Parallel Job (Lines 305-325)

```
  Starting Application Insights creation: ai-orderprocessing-dev...
```

**What Happens**:
1. Constructs App Insights name: `ai-{BaseName}-{env}`
2. Checks if App Insights exists: `az monitor app-insights component show -a ai-orderprocessing-dev -g rg-orderprocessing-dev`
3. If **NOT exists**:
   - **Starts PowerShell Background Job** (non-blocking)
   - Inside the job:
     ```powershell
     az monitor app-insights component create `
       -a ai-orderprocessing-dev `
       -g rg-orderprocessing-dev `
       -l centralindia `
       --application-type web
     ```
   - Returns: `{Success, Output, Error, ResourceName}`
4. If **exists**: Skips creation, logs "already exists"

**Timeline**: Starts immediately, runs in background (~1-2 minutes typically)

**Output Variables**:
- `$aiName` = App Insights name (e.g., `ai-orderprocessing-dev`)
- `$aiJob` = Background job reference (or `$null` if pre-existing)

---

#### Step 2.6: Wait for All Jobs (Lines 327-339)

```
  [PARALLEL] Waiting for creation jobs to complete...
```

**What Happens**:
1. Collects all active job references: `$jobs = @($apiJob, $uiJob, $aiJob)` (excludes `$null`)
2. **Blocks execution** until ALL jobs complete: `$jobs | Wait-Job | Out-Null`
3. This is where parallel execution pays off - all 3 resources created simultaneously

**Timeline**: Waits for slowest job (~3-5 minutes if all succeed, ~30 seconds if all fail)

---

#### Step 2.7: Process Job Results (Lines 340-389)

```
  [OK] Application Insights created: ai-orderprocessing-dev
  [OK] API job completed successfully
  [WARN] UI creation job encountered errors
```

**What Happens**:

**2.7a: Process Application Insights Job**
1. Receives job output: `$aiResult = Receive-Job -Job $aiJob`
2. Removes job from queue: `Remove-Job -Job $aiJob`
3. Checks `$aiResult.Success`:
   - **True**: Logs success message
   - **False**: Logs warning with error details

**2.7b: Process API Job**
1. Receives job output: `$apiResult = Receive-Job -Job $apiJob`
2. Removes job from queue: `Remove-Job -Job $apiJob`
3. Checks `$apiResult.Success`:
   - **True**: Logs success, sets `$apiJobFailed = $false`
   - **False**: Logs warning, sets `$apiJobFailed = $true`

**2.7c: Process UI Job**
1. Receives job output: `$uiResult = Receive-Job -Job $uiJob`
2. Removes job from queue: `Remove-Job -Job $uiJob`
3. Checks `$uiResult.Success`:
   - **True**: Logs success, sets `$uiJobFailed = $false`
   - **False**: Logs warning, sets `$uiJobFailed = $true`

**Timeline**: ~1-2 seconds

**Output Variables**:
- `$apiJobFailed` = Boolean flag
- `$uiJobFailed` = Boolean flag

---

#### Step 2.8: Conditional 20-Minute Wait (Lines 391-488)

**ONLY EXECUTES IF**: `$apiJobFailed -eq $true` OR `$uiJobFailed -eq $true`

```
  [WAIT] One or more webapp jobs failed, initiating 20-minute provisioning wait for all resources...
  [INFO] Monitoring App Service Plan, API, and UI webapps during wait period
  [PLAN] asp-orderprocessing-dev
  [URL] API: https://orderprocessing-api-xyapp-dev.azurewebsites.net
  [URL] UI: https://orderprocessing-ui-xyapp-dev.azurewebsites.net
  [PROGRESS] [#######.................] 7/40 checks (3.5 minutes elapsed)
  [OK] App Service Plan verified via CLI after 2.5 minutes
  [OK] API webapp verified via CLI after 4.0 minutes
  [OK] UI website responding (HTTP 200) after 5.5 minutes
  [PROGRESS] [####################] 
```

**What Happens**:

**Initialization**:
- `$waitSeconds = 1200` (20 minutes)
- `$checkInterval = 30` (check every 30 seconds)
- `$elapsed = 0`
- Flags: `$planVerified`, `$apiVerified`, `$uiVerified` = `$false`

**Loop Execution** (repeats up to 40 times or until all verified):

1. **Sleep**: `Start-Sleep -Seconds 30`
2. **Increment**: `$elapsed += 30`
3. **Progress Bar**: Display `#` character

**Every 30 seconds, perform parallel checks**:

**Check 1: App Service Plan**
```powershell
if (-not $planVerified) {
    $planCheckResult = az appservice plan show -g rg-orderprocessing-dev -n asp-orderprocessing-dev --query "name" -o tsv 2>$null
    if ($planCheckResult -eq 'asp-orderprocessing-dev') {
        $planVerified = $true
        # Log success with elapsed time
    }
}
```

**Check 2: API WebApp** (if job failed)
```powershell
if (-not $apiVerified -and $apiJobFailed) {
    # CLI Check
    $apiCheck = az webapp show -g rg-orderprocessing-dev -n orderprocessing-api-xyapp-dev --query "name" -o tsv 2>$null
    if ($apiCheck -eq 'orderprocessing-api-xyapp-dev') {
        $apiVerified = $true
    } else {
        # HTTP Check
        try {
            $webCheck = Invoke-WebRequest -Uri "https://orderprocessing-api-xyapp-dev.azurewebsites.net" -Method Get -TimeoutSec 5
            if ($webCheck.StatusCode -eq 200) {
                $apiVerified = $true
            }
        } catch { }
    }
}
```

**Check 3: UI WebApp** (if job failed)
```powershell
if (-not $uiVerified -and $uiJobFailed) {
    # CLI Check
    $uiCheck = az webapp show -g rg-orderprocessing-dev -n orderprocessing-ui-xyapp-dev --query "name" -o tsv 2>$null
    if ($uiCheck -eq 'orderprocessing-ui-xyapp-dev') {
        $uiVerified = $true
    } else {
        # HTTP Check
        try {
            $webCheck = Invoke-WebRequest -Uri "https://orderprocessing-ui-xyapp-dev.azurewebsites.net" -Method Get -TimeoutSec 5
            if ($webCheck.StatusCode -eq 200) {
                $uiVerified = $true
            }
        } catch { }
    }
}
```

**Early Exit Condition**:
- Loop exits if `$planVerified -and $apiVerified -and $uiVerified` = `$true`
- Can finish in 2-3 minutes if resources provision quickly
- Maximum wait: 20 minutes

**Timeline**: 0 seconds (skipped if jobs succeeded) to 20 minutes (full wait)

---

#### Step 2.9: Comprehensive Verification (Lines 490-623)

```
  [VERIFY] Running comprehensive resource verification...
```

**What Happens**:

This section **ALWAYS runs** regardless of whether the 20-minute wait executed.

**2.9a: Verify App Service Plan Status** (Lines 497-506)
```powershell
$planStatus = az appservice plan show -g rg-orderprocessing-dev -n asp-orderprocessing-dev --query "{Name:name, Status:status, State:provisioningState, Sku:sku.name}" -o json | ConvertFrom-Json

if ($planStatus.Status -eq "Ready" -or $planStatus.State -eq "Succeeded") {
    # [OK] App Service Plan: asp-orderprocessing-dev is Ready (SKU: F1)
} else {
    # [FAIL] App Service Plan: asp-orderprocessing-dev is not ready
    $allResourcesReady = $false
}
```

**2.9b: Verify Application Insights State** (Lines 508-521)
```powershell
$aiState = az monitor app-insights component show -a ai-orderprocessing-dev -g rg-orderprocessing-dev --query "{Name:name, State:provisioningState}" -o json | ConvertFrom-Json

if ($aiState.State -eq "Succeeded") {
    # [OK] Application Insights: ai-orderprocessing-dev (State: Succeeded)
} else {
    # [WARN] Application Insights: ai-orderprocessing-dev not fully provisioned (State: ...)
}
```

**2.9c: API WebApp Final Verification** (Lines 523-565)
```powershell
# Check existence
$apiCheckFinal = az webapp show -g rg-orderprocessing-dev -n orderprocessing-api-xyapp-dev --query "name" -o tsv 2>$null

if ($apiCheckFinal -eq 'orderprocessing-api-xyapp-dev') {
    # Differentiate created vs pre-existing
    if ($apiJob) {
        # [OK] API WebApp created and verified: orderprocessing-api-xyapp-dev
    } else {
        # [OK] API WebApp verified (pre-existing): orderprocessing-api-xyapp-dev
    }
    
    # Verify runtime configuration
    $runtime = az webapp config show -g rg-orderprocessing-dev -n orderprocessing-api-xyapp-dev --query "netFrameworkVersion" -o tsv 2>$null
    
    if ($runtime -eq "v8.0") {
        # [OK] Runtime: .NET 8
    } else {
        # [WARN] Runtime: {current} (expected v8.0), configuring .NET 8...
        
        # Attempt auto-configuration
        az webapp config set -g rg-orderprocessing-dev -n orderprocessing-api-xyapp-dev --net-framework-version "v8.0" 2>$null
        Start-Sleep -Seconds 3
        
        # Re-verify
        $runtimeCheck = az webapp config show -g rg-orderprocessing-dev -n orderprocessing-api-xyapp-dev --query "netFrameworkVersion" -o tsv 2>$null
        
        if ($runtimeCheck -eq "v8.0") {
            # [OK] Runtime configured to .NET 8
        } else {
            # [FAIL] Runtime configuration failed. Manual configuration required via Azure Portal
            # [ACTION] Portal: Settings -> Configuration -> General settings -> Stack: .NET 8 (LTS)
            $allResourcesReady = $false
        }
    }
    
    # Verify app state
    $apiState = az webapp show -g rg-orderprocessing-dev -n orderprocessing-api-xyapp-dev --query "{State:state, HostNames:defaultHostName}" -o json | ConvertFrom-Json
    
    if ($apiState.State -eq "Running") {
        # [OK] State: Running at https://orderprocessing-api-xyapp-dev.azurewebsites.net
    } else {
        # [WARN] State: {current state}
    }
    
} elseif ($apiJob) {
    # [FAIL] API WebApp creation FAILED after provisioning wait
    # [CHECK] Azure Portal: https://portal.azure.com
    $allResourcesReady = $false
}
```

**2.9d: UI WebApp Final Verification** (Lines 567-609)
```powershell
# Identical process to API WebApp verification
# - Check existence
# - Verify runtime (.NET 8)
# - Auto-configure if needed
# - Verify state (Running)
# - Log appropriate messages
```

**2.9e: Configure Application Insights Connection Strings** (Lines 611-623)
```powershell
# Get App Insights connection string
$aiConnectionString = az monitor app-insights component show -a ai-orderprocessing-dev -g rg-orderprocessing-dev --query "connectionString" -o tsv 2>$null

if ($aiConnectionString) {
    # Configure for API webapp
    az webapp config appsettings set -g rg-orderprocessing-dev -n orderprocessing-api-xyapp-dev --settings "APPLICATIONINSIGHTS_CONNECTION_STRING=$aiConnectionString" 2>$null | Out-Null
    # [OK] App Insights connection configured for API
    
    # Configure for UI webapp
    az webapp config appsettings set -g rg-orderprocessing-dev -n orderprocessing-ui-xyapp-dev --settings "APPLICATIONINSIGHTS_CONNECTION_STRING=$aiConnectionString" 2>$null | Out-Null
    # [OK] App Insights connection configured for UI
    
    # Final status
    if ($allResourcesReady) {
        # [OK] All resources provisioned and verified successfully
    } else {
        # [WARN] Some resources require attention - see messages above
    }
}
```

**Timeline**: ~10-15 seconds

**Output Variables**:
- `$allResourcesReady` = Boolean indicating complete success

---

#### Step 2.10: Track Environment (Line 626)

```powershell
$created += [PSCustomObject]@{ 
    Environment = 'dev'
    ResourceGroup = 'rg-orderprocessing-dev'
    Plan = 'asp-orderprocessing-dev'
    ApiApp = 'orderprocessing-api-xyapp-dev'
    UiApp = 'orderprocessing-ui-xyapp-dev'
    Sku = 'F1'
    AppInsights = 'ai-orderprocessing-dev'
}
```

**What Happens**:
- Adds current environment details to tracking array
- Used later for summary table and RBAC assignments

---

### Phase 3: OIDC Configuration (Lines 629-713)

**EXECUTES AFTER**: All environment loops complete

```
[OIDC Setup] Configuring GitHub Actions OIDC...
  [OK] App Registration found (pre-existing): GitHub-Actions-OIDC
  [OK] Service Principal found (pre-existing)
  App (Client) ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  SP Object ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

**What Happens**:

**3.1: Wait for OIDC Background Job** (Lines 637-639)
```powershell
$oidcJob | Wait-Job | Out-Null
$oidcResult = Receive-Job -Job $oidcJob
Remove-Job -Job $oidcJob
```
- Waits for background job to complete (usually instant - already finished during environment processing)
- Retrieves results
- Cleans up job

**3.2: Log App Registration Status** (Lines 641-653)
```powershell
if ($oidcResult.Success) {
    if ($oidcResult.AppCreated) {
        # [OK] App Registration created: GitHub-Actions-OIDC
    } else {
        # [OK] App Registration found (pre-existing): GitHub-Actions-OIDC
    }
    
    if ($oidcResult.SpCreated) {
        # [OK] Service Principal created
    } else {
        # [OK] Service Principal found (pre-existing)
    }
    
    # Display IDs
    # App (Client) ID: {AppId}
    # SP Object ID: {SpObjectId}
}
```

**3.3: Configure Federated Credentials** (Lines 656-684)
```powershell
# List existing credentials
$existingCreds = az ad app federated-credential list --id {AppObjectId} 2>$null | ConvertFrom-Json

$branches = @('main', 'staging', 'dev')
$githubOwner = 'getpavanthakur'
$repository = 'TestAppXY_OrderProcessingSystem'

foreach ($branch in $branches) {
    $credName = "github-$branch-oidc"  # e.g., "github-main-oidc"
    $subject = "repo:$githubOwner/$repository:ref:refs/heads/$branch"
    
    # Check if credential already exists
    $exists = $existingCreds | Where-Object { $_.name -eq $credName }
    
    if ($exists) {
        # [github-main-oidc] Already exists (branch: main)
        continue
    }
    
    # Create JSON credential file
    $credentialJson = @{
        name = $credName
        issuer = "https://token.actions.githubusercontent.com"
        subject = $subject
        audiences = @("api://AzureADTokenExchange")
    } | ConvertTo-Json
    
    $tempFile = [System.IO.Path]::GetTempFileName()
    $credentialJson | Out-File -FilePath $tempFile -Encoding UTF8
    
    # Create federated credential
    az ad app federated-credential create --id {AppObjectId} --parameters $tempFile 2>$null | Out-Null
    
    Remove-Item $tempFile -ErrorAction SilentlyContinue
    
    # [github-main-oidc] Created (branch: main)
}
```

**Created Credentials**:
- `github-main-oidc` → Subject: `repo:getpavanthakur/TestAppXY_OrderProcessingSystem:ref:refs/heads/main`
- `github-staging-oidc` → Subject: `repo:getpavanthakur/TestAppXY_OrderProcessingSystem:ref:refs/heads/staging`
- `github-dev-oidc` → Subject: `repo:getpavanthakur/TestAppXY_OrderProcessingSystem:ref:refs/heads/dev`

**Branch-to-Environment Mapping**:

| Git Branch | Federated Credential | Subject Pattern | Deploys To |
|-----------|---------------------|-----------------|------------|
| `main` | `github-main-oidc` | `ref:refs/heads/main` | Production resources (future) |
| `staging` | `github-staging-oidc` | `ref:refs/heads/staging` | `rg-orderprocessing-staging`<br>`orderprocessing-api-xyapp-staging`<br>`orderprocessing-ui-xyapp-staging` |
| `dev` | `github-dev-oidc` | `ref:refs/heads/dev` | `rg-orderprocessing-dev`<br>`orderprocessing-api-xyapp-dev`<br>`orderprocessing-ui-xyapp-dev` |

**How Branch-Based OIDC Works**:
1. Developer pushes code to `dev` branch
2. GitHub Actions workflow triggers
3. Workflow requests OIDC token with subject: `repo:getpavanthakur/TestAppXY_OrderProcessingSystem:ref:refs/heads/dev`
4. Azure validates token against `github-dev-oidc` federated credential
5. Azure grants access to deploy to dev resource group
6. Deployment proceeds to dev WebApps automatically

**Why One Set of Secrets Works for All Branches**:
- Repository secrets (`AZUREAPPSERVICE_CLIENTID`, `TENANTID`, `SUBSCRIPTIONID`) are **environment-agnostic**
- The **branch name in the OIDC token subject** determines which federated credential matches
- Same App Registration, different federated credentials = different resource access per branch

**3.4: Assign RBAC Roles** (Lines 686-701)
```powershell
# Get list of resource groups from tracking array
$rgList = $created | Select-Object -ExpandProperty ResourceGroup -Unique
# Result: ['rg-orderprocessing-dev', 'rg-orderprocessing-stg', 'rg-orderprocessing-prod']

foreach ($rg in $rgList) {
    $scope = "/subscriptions/{SubscriptionId}/resourceGroups/$rg"
    
    # Check if role assignment already exists
    $existingAssignment = az role assignment list --assignee {SpObjectId} --role "Contributor" --scope $scope 2>$null | ConvertFrom-Json
    
    if (-not $existingAssignment -or $existingAssignment.Count -eq 0) {
        # Create role assignment
        az role assignment create --assignee {SpObjectId} --role "Contributor" --scope $scope 2>$null | Out-Null
        
        # [rg-orderprocessing-dev] Contributor role assigned
    } else {
        # [rg-orderprocessing-dev] Contributor role already assigned
    }
}
```

**3.5: Display GitHub Secrets** (Lines 703-713)
```
  [GitHub Secrets] Add these to repository secrets:
    https://github.com/getpavanthakur/TestAppXY_OrderProcessingSystem/settings/secrets/actions

    AZUREAPPSERVICE_CLIENTID:        xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    AZUREAPPSERVICE_TENANTID:        xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    AZUREAPPSERVICE_SUBSCRIPTIONID:  xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

  [OK] Secrets copied to clipboard!
```

**What Happens**:
1. Displays GitHub repository secrets URL
2. Shows three required secrets with actual values
3. Creates formatted text block
4. Copies to clipboard: `Set-Clipboard`
5. User can directly paste into GitHub

**Timeline**: ~5-10 seconds

---

### Phase 4: Summary & Next Steps (Lines 715-734)

```
[Summary] Provisioning results:

Environment  ResourceGroup          Plan                    ApiApp                            UiApp                           Sku   AppInsights
-----------  -------------          ----                    ------                            ------                          ---   -----------
dev          rg-orderprocessing-dev asp-orderprocessing-dev orderprocessing-api-xyapp-dev     orderprocessing-ui-xyapp-dev    F1    ai-orderprocessing-dev
stg          rg-orderprocessing-stg asp-orderprocessing-stg orderprocessing-api-xyapp-stg     orderprocessing-ui-xyapp-stg    B1    ai-orderprocessing-stg
prod         rg-orderprocessing-prod asp-orderprocessing-prod orderprocessing-api-xyapp-prod  orderprocessing-ui-xyapp-prod   P1v3  ai-orderprocessing-prod

Next Steps:
  1. [DONE] GitHub Actions OIDC configured with federated credentials for main, staging, dev
  2. [DONE] Git branches created: dev, staging, main (pushed to origin)
  3. Add the secrets above to GitHub repository secrets (copied to clipboard)
  4. Push code to dev branch to trigger first deployment
  5. After validation, merge dev → staging → main
  6. [DONE] Application Insights connection strings configured automatically

**Branch Workflow Reminder**:
- `dev` branch → Deploys to `orderprocessing-api-xyapp-dev` & `orderprocessing-ui-xyapp-dev`
- `staging` branch → Deploys to `orderprocessing-api-xyapp-staging` & `orderprocessing-ui-xyapp-staging`  
- `main` branch → (Future production deployment)
```

**What Happens**:
1. Formats `$created` array as table
2. Displays provisioning summary
3. Shows next steps with completion status
4. Indicates what's automated vs. manual steps

---

## Detailed Phase Breakdown

### Parallel Execution Model

```
Time →
─────────────────────────────────────────────────────────────────
0:00    START
        │
        ├─ [Job 1] OIDC App Registration ────────────────────┐
        │                                                      │
        ├─ RG Create (sync) ──┐                              │
        ├─ Plan Create (sync) ┘                              │
        │                                                      │
        ├─ [Job 2] API WebApp ──────────────┐                │
        ├─ [Job 3] UI WebApp ───────────────┤                │
        ├─ [Job 4] App Insights ────────────┘                │
        │                                    │                │
3-5min  ├─ Wait for Jobs 2,3,4 ─────────────┘                │
        │                                                      │
        ├─ Process job results                               │
        │                                                      │
        ├─ [OPTIONAL] 20-min wait if failures                │
        │                                                      │
        ├─ Comprehensive verification                        │
        │                                                      │
        ├─ Wait for Job 1 (usually instant) ─────────────────┘
        │                                                      
        ├─ Configure federated credentials                   
        ├─ Assign RBAC                                       
        ├─ Display secrets                                   
        │                                                      
5-6min  END (best case)
─────────────────────────────────────────────────────────────────
```

### Error Handling Strategy

**Level 1: Retry Logic** (Individual Commands)
- 3 attempts per command
- 10-second delay between attempts
- Captures exit codes and error messages
- Example: `az webapp create` retries on network errors

**Level 2: Job Failure Handling** (Background Jobs)
- Jobs return success/failure status
- Script continues with other jobs on individual failure
- Failed jobs trigger 20-minute wait period

**Level 3: Consolidated Wait** (20-Minute Verification)
- Only triggers if jobs fail
- Polls resources every 30 seconds
- Early exit on success
- Provides HTTP fallback if CLI fails

**Level 4: Graceful Degradation** (Final Verification)
- Auto-configuration attempts for runtime issues
- Clear manual instructions if auto-config fails
- Continues with other resources on individual failures
- Summary indicates which resources need attention

### Wait Strategy Optimization

**Before Optimization**:
- App Service Plan: Wait 5 seconds + verify immediately
- API WebApp: Sequential creation + 3-minute wait
- UI WebApp: Sequential creation + 3-minute wait
- App Insights: Sequential creation + 1-minute wait
- OIDC: Manual 5-minute setup
- **Total**: 12+ minutes

**After Optimization**:
- App Service Plan: No immediate wait (verified later if needed)
- API + UI + App Insights: Parallel creation (fastest wins)
- OIDC: Parallel background job (zero additional time)
- Conditional 20-minute wait: Only if failures occur
- **Total Best Case**: 5-6 minutes
- **Total Worst Case**: 20-21 minutes (same as before but with better visibility)

---

## Verification Checklist

Use this checklist to verify successful script execution:

### During Execution

- [ ] Script starts without PowerShell errors
- [ ] Subscription is correctly identified
- [ ] OIDC job starts (see "PARALLEL" message)
- [ ] Resource Groups created/verified
- [ ] App Service Plans created/verified
- [ ] API/UI/App Insights jobs start
- [ ] Jobs complete (check for "OK" or "WARN" messages)
- [ ] If 20-minute wait triggers:
  - [ ] Progress bar displays
  - [ ] Resources verified during wait
  - [ ] Early exit if possible
- [ ] Comprehensive verification runs
- [ ] Runtime auto-configuration succeeds (or shows manual steps)
- [ ] OIDC configuration completes
- [ ] Federated credentials created for main, staging, dev
- [ ] RBAC roles assigned to all resource groups
- [ ] GitHub secrets displayed and copied to clipboard

### Post-Execution Verification

#### Azure Portal Checks

**Resource Groups**:
```powershell
az group list --query "[?contains(name, 'orderprocessing')].{Name:name, Location:location, State:properties.provisioningState}" --output table
```
Expected: All environments exist with "Succeeded" state

**App Service Plans**:
```powershell
az appservice plan list --query "[?contains(name, 'orderprocessing')].{Name:name, ResourceGroup:resourceGroup, SKU:sku.name, State:status}" --output table
```
Expected: All plans exist with correct SKU and "Ready" status

**API WebApps**:
```powershell
az webapp list --query "[?contains(name, 'api-xyapp')].{Name:name, State:state, Runtime:siteConfig.netFrameworkVersion, URL:defaultHostName}" --output table
```
Expected: All API apps exist, State="Running", Runtime="v8.0"

**UI WebApps**:
```powershell
az webapp list --query "[?contains(name, 'ui-xyapp')].{Name:name, State:state, Runtime:siteConfig.netFrameworkVersion, URL:defaultHostName}" --output table
```
Expected: All UI apps exist, State="Running", Runtime="v8.0"

**Application Insights**:
```powershell
az monitor app-insights component list --query "[?contains(name, 'orderprocessing')].{Name:name, ResourceGroup:resourceGroup, State:provisioningState}" --output table
```
Expected: All App Insights exist with "Succeeded" state

#### OIDC Verification

**App Registration**:
```powershell
az ad app list --display-name "GitHub-Actions-OIDC" --query "[].{Name:displayName, AppId:appId, ObjectId:id}" --output table
```
Expected: One App Registration exists

**Service Principal**:
```powershell
$appId = az ad app list --display-name "GitHub-Actions-OIDC" --query "[0].appId" -o tsv
az ad sp list --filter "appId eq '$appId'" --query "[].{DisplayName:displayName, ObjectId:id}" --output table
```
Expected: Service Principal exists

**Federated Credentials**:
```powershell
./Resources/Azure-Deployment/check-app-registration.ps1
```
Expected output:
```
--- Federated Credentials ---
  ✓ github-main-oidc (branch: main)
  ✓ github-staging-oidc (branch: staging)
  ✓ github-dev-oidc (branch: dev)
```

**RBAC Assignments**:
```powershell
$spObjectId = az ad sp list --display-name "GitHub-Actions-OIDC" --query "[0].id" -o tsv
az role assignment list --assignee $spObjectId --query "[].{Scope:scope, Role:roleDefinitionName}" --output table
```
Expected: Contributor role on all resource groups

#### Application Verification

**API Endpoints** (dev example):
```powershell
Invoke-WebRequest -Uri "https://orderprocessing-api-xyapp-dev.azurewebsites.net" -Method Get
```
Expected: HTTP 200 or application-specific response

**UI Endpoints** (dev example):
```powershell
Invoke-WebRequest -Uri "https://orderprocessing-ui-xyapp-dev.azurewebsites.net" -Method Get
```
Expected: HTTP 200 or application-specific response

**App Insights Connection**:
```powershell
az webapp config appsettings list -g rg-orderprocessing-dev -n orderprocessing-api-xyapp-dev --query "[?name=='APPLICATIONINSIGHTS_CONNECTION_STRING'].{Name:name, Value:value}" --output table
```
Expected: Connection string configured

### GitHub Repository Checks

**Add Secrets**:
1. Navigate to: `https://github.com/getpavanthakur/TestAppXY_OrderProcessingSystem/settings/secrets/actions`
2. Add three repository secrets:
   - `AZUREAPPSERVICE_CLIENTID`
   - `AZUREAPPSERVICE_TENANTID`
   - `AZUREAPPSERVICE_SUBSCRIPTIONID`
3. Paste values from clipboard (already copied by script)

**Verify Secrets**:
- [ ] All three secrets appear in repository secrets list
- [ ] No typos in secret names (case-sensitive)
- [ ] Values are GUIDs (36 characters with hyphens)

---

## Troubleshooting Guide

### Common Issues

#### Issue 1: "Attempt 1 failed (exit code: 1), retrying in 10 seconds"

**Cause**: Transient Azure CLI error (network, timeout, rate limiting)

**Action**: 
- ✅ **Normal behavior** - script will retry automatically
- Wait for attempts 2 and 3
- Only investigate if all 3 attempts fail

**Resolution**: Usually resolves on retry 2 or 3

---

#### Issue 2: "App Service Plan creation FAILED after retries"

**Cause**: 
- Quota limit reached
- SKU not available in region
- Permission issue

**Action**:
```powershell
# Check quota
az vm list-usage --location centralindia --query "[?name.value=='cores'].{Name:name.localizedValue, Current:currentValue, Limit:limit}" --output table

# Try different SKU
./bootstrap-enterprise-infra.ps1 -BaseName orderprocessing -Location centralindia -Environments dev -DevSku B1

# Check permissions
az role assignment list --assignee $(az ad signed-in-user show --query id -o tsv) --query "[].{Role:roleDefinitionName, Scope:scope}" --output table
```

**Resolution**: Adjust SKU or request quota increase

---

#### Issue 3: "20-minute wait triggered but resources still not verified"

**Cause**:
- Resources provisioning slowly
- Region experiencing issues
- Resource configuration error

**Action**:
```powershell
# Check Azure Portal manually
# Navigate to: https://portal.azure.com
# Filter by resource group: rg-orderprocessing-dev

# Check specific resource status
az webapp show -g rg-orderprocessing-dev -n orderprocessing-api-xyapp-dev --query "{Name:name, State:state, RuntimeVersion:siteConfig.netFrameworkVersion}" --output table

# Check activity log
az monitor activity-log list --resource-group rg-orderprocessing-dev --start-time 2025-11-17T00:00:00Z --query "[?level=='Error'].{Time:eventTimestamp, Status:status.value, Message:properties.statusMessage}" --output table
```

**Resolution**: 
- Wait additional time
- Check Azure Service Health
- Re-run script (idempotent - safe to retry)

---

#### Issue 4: "Runtime configuration failed. Manual configuration required"

**Cause**: Auto-configuration command failed or not supported

**Action**:
1. Open Azure Portal: https://portal.azure.com
2. Navigate to App Service (e.g., orderprocessing-api-xyapp-dev)
3. Settings → Configuration → General settings
4. Stack: Select ".NET"
5. .NET version: Select ".NET 8 (LTS)"
6. Click "Save"

**Resolution**: Manual Portal configuration

---

#### Issue 5: "OIDC setup encountered errors"

**Cause**:
- Insufficient permissions for App Registration creation
- Azure AD/Entra ID access denied
- Background job failure

**Action**:
```powershell
# Check current permissions
az ad signed-in-user show --query "{Name:displayName, UserPrincipalName:userPrincipalName, ObjectId:id}" --output table

# Check role assignments
az role assignment list --assignee $(az ad signed-in-user show --query id -o tsv) --all --query "[?contains(roleDefinitionName, 'Admin')].{Role:roleDefinitionName, Scope:scope}" --output table

# Manual OIDC setup
./Resources/Azure-Deployment/setup-github-oidc.ps1 `
  -ResourceGroupNames "rg-orderprocessing-dev,rg-orderprocessing-stg,rg-orderprocessing-prod" `
  -Branches "main,staging,dev" `
  -RoleName "Contributor"
```

**Resolution**: 
- Request "Application Administrator" role in Azure AD
- Use manual OIDC setup script
- Contact Azure administrator

---

#### Issue 6: "AADSTS700213: No matching federated identity record found" during GitHub Actions deployment

**Cause**: Malformed federated credential subject - missing repository name between owner and branch reference

**Symptom**: GitHub Actions workflow fails at "Login to Azure" step with error:
```
Error: AADSTS700213: No matching federated identity record found for presented assertion 
subject 'repo:getpavanthakur/TestAppXY_OrderProcessingSystem:ref:refs/heads/dev'
```

**Action**:
```powershell
# 1. List current federated credentials to check format
$appId = "dcb3394d-cc23-422d-b525-9ecf872949b7"  # Your App ID
az ad app federated-credential list --id $appId --query "[].{Name:name, Subject:subject}" -o table

# 2. Check for malformed subjects (missing repo name):
# ❌ BAD:  repo:getpavanthakur//heads/dev
# ✅ GOOD: repo:getpavanthakur/TestAppXY_OrderProcessingSystem:ref:refs/heads/dev

# 3. Delete malformed credentials
az ad app federated-credential delete --id $appId --federated-credential-id github-dev-oidc
az ad app federated-credential delete --id $appId --federated-credential-id github-staging-oidc

# 4. Recreate with correct format
$credentialJson = @{
    name = "github-dev-oidc"
    issuer = "https://token.actions.githubusercontent.com"
    subject = "repo:getpavanthakur/TestAppXY_OrderProcessingSystem:ref:refs/heads/dev"
    audiences = @("api://AzureADTokenExchange")
} | ConvertTo-Json

$tempFile = [System.IO.Path]::GetTempFileName()
$credentialJson | Out-File -FilePath $tempFile -Encoding UTF8
az ad app federated-credential create --id $appId --parameters $tempFile
Remove-Item $tempFile
```

**Resolution**: 
- Recreate federated credentials with correct subject format
- Subject pattern: `repo:{owner}/{repository}:ref:refs/heads/{branch}`
- Verify all three branches (dev, staging, main) have correct format

---

#### Issue 7: "GitHub secrets not copied to clipboard"

**Cause**: Clipboard access denied or not available

**Action**:
- Secrets are displayed in console output
- Manually copy values from terminal
- Look for section: `[GitHub Secrets] Add these to repository secrets:`

**Resolution**: Manual copy from console output

---

#### Issue 8: "Resources already exist" but script reports failures

**Cause**: Pre-existence checks working correctly (not an error)

**Action**:
- Review console output for actual errors
- Pre-existing resources logged as `[OK] {Resource} verified (pre-existing)`
- Only investigate resources marked as `[FAIL]` or `[WARN]`

**Resolution**: Verify comprehensive verification section shows all resources as ready

---

### Debug Mode

To get more detailed output:

```powershell
# Enable verbose output
$VerbosePreference = "Continue"

# Run script
./Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1 -BaseName orderprocessing -Location centralindia -Environments dev -Verbose

# Check last command exit code
$LASTEXITCODE

# Check Azure CLI debug
$env:AZURE_CLI_DEBUG = "1"
az webapp list -g rg-orderprocessing-dev
```

### Getting Help

**Internal Resources**:
- Review `AZURE_DEPLOYMENT_GUIDE.md` for detailed setup instructions
- Run `./Resources/Azure-Deployment/check-app-registration.ps1` for OIDC verification
- Check `Documentation/02-Azure-Learning-Guides/` for additional guides

**Azure Resources**:
- Azure Portal: https://portal.azure.com
- Azure CLI documentation: https://docs.microsoft.com/cli/azure/
- Azure Service Health: https://status.azure.com/

**Script Logs**:
- PowerShell transcript (if enabled)
- Azure Activity Log (Portal → Monitor → Activity log)
- Resource-specific logs (App Service → Monitoring → Log stream)

---

## Summary

This document provides a complete, sequenced walkthrough of the `bootstrap-enterprise-infra.ps1` script optimized for:

✅ **Junior Developer Onboarding**: Step-by-step explanations with line number references  
✅ **Code Review**: Detailed flow analysis for validation and audit  
✅ **Troubleshooting**: Common issues and resolutions  
✅ **Verification**: Comprehensive checklists for post-execution validation  
✅ **Understanding**: Timeline breakdowns and execution models  

**Key Takeaways**:
1. Script uses parallel execution for 3-4x performance improvement
2. Retry logic handles transient errors automatically
3. Pre-existence checks enable safe re-runs
4. OIDC setup fully integrated - no manual steps
5. 20-minute wait only triggers on failures
6. Comprehensive verification ensures .NET 8 runtime
7. All GitHub secrets auto-copied to clipboard

For additional details, refer to:
- `AZURE_DEPLOYMENT_GUIDE.md` - Complete deployment strategy
- `bootstrap-enterprise-infra.ps1` - Source code with inline comments
- `check-app-registration.ps1` - OIDC verification utility
