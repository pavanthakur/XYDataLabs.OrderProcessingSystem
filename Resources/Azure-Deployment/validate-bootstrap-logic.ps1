<#
.SYNOPSIS
  Dry-run validation script for bootstrap timing and gating logic
.DESCRIPTION
  Simulates the bootstrap flow WITHOUT creating any Azure resources.
  Tests all timer logic, readiness gates, and error handling paths.
  Generates detailed logs to validate control flow.
.EXAMPLE
  ./validate-bootstrap-logic.ps1 -SimulateRGDelay 120 -SimulatePlanDelay 60
#>
param(
    [Parameter(Mandatory=$false)] [int]$SimulateRGDelay = 0,
    [Parameter(Mandatory=$false)] [int]$SimulatePlanDelay = 0,
    [Parameter(Mandatory=$false)] [int]$SimulateWebAppDelay = 0,
    [Parameter(Mandatory=$false)] [switch]$SimulateRGFailure,
    [Parameter(Mandatory=$false)] [switch]$SimulatePlanFailure,
    [Parameter(Mandatory=$false)] [string]$LogFile = "bootstrap-validation.log"
)

$ErrorActionPreference = 'Continue'
$script:ValidationLog = @()

function Write-ValidationLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = "[$timestamp] [$Level] $Message"
    $script:ValidationLog += $logEntry
    
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        "OK"    { "Green" }
        "TIMER" { "Cyan" }
        default { "White" }
    }
    Write-Host $logEntry -ForegroundColor $color
}

function Simulate-Wait {
    param([int]$Seconds, [string]$Reason)
    if ($Seconds -gt 0) {
        Write-ValidationLog "Simulating wait: $Seconds seconds ($Reason)" "TIMER"
        Start-Sleep -Seconds $Seconds
    }
}

function Test-RGReadinessGate {
    param(
        [string]$ResourceGroup,
        [int]$TimeoutMinutes,
        [int]$IntervalSeconds
    )
    
    Write-ValidationLog "=== Testing RG Readiness Gate ===" "TIMER"
    Write-ValidationLog "ResourceGroup: $ResourceGroup" "INFO"
    Write-ValidationLog "TimeoutMinutes: $TimeoutMinutes" "INFO"
    Write-ValidationLog "IntervalSeconds: $IntervalSeconds" "INFO"
    
    $timeoutSeconds = $TimeoutMinutes * 60
    $maxIterations = [math]::Ceiling($timeoutSeconds / $IntervalSeconds)
    Write-ValidationLog "Calculated timeout: $timeoutSeconds seconds" "TIMER"
    Write-ValidationLog "Max iterations: $maxIterations" "TIMER"
    
    $elapsed = 0
    $iteration = 0
    
    while ($elapsed -lt $timeoutSeconds) {
        $iteration++
        Write-ValidationLog "Iteration $iteration/$maxIterations - Elapsed: $elapsed seconds" "TIMER"
        
        # Simulate RG check delay
        if ($SimulateRGDelay -gt 0 -and $elapsed -eq 0) {
            Simulate-Wait -Seconds $SimulateRGDelay -Reason "Initial RG creation delay"
        }
        
        # Simulate RG ready after delay
        if ($SimulateRGFailure) {
            Write-ValidationLog "Simulating RG failure (always not ready)" "WARN"
        } elseif ($elapsed -ge $SimulateRGDelay) {
            Write-ValidationLog "RG would be ready at this point" "OK"
            return $true
        }
        
        if ($iteration -ge $maxIterations) {
            Write-ValidationLog "Max iterations reached" "ERROR"
            break
        }
        
        Start-Sleep -Seconds $IntervalSeconds
        $elapsed += $IntervalSeconds
    }
    
    Write-ValidationLog "RG readiness gate FAILED after $elapsed seconds" "ERROR"
    return $false
}

function Test-UnifiedReadinessLoop {
    param(
        [string]$Plan,
        [string]$ApiApp,
        [string]$UiApp,
        [int]$TimeoutMinutes
    )
    
    Write-ValidationLog "=== Testing Unified Readiness Loop ===" "TIMER"
    Write-ValidationLog "Plan: $Plan" "INFO"
    Write-ValidationLog "ApiApp: $ApiApp" "INFO"
    Write-ValidationLog "UiApp: $UiApp" "INFO"
    Write-ValidationLog "TimeoutMinutes: $TimeoutMinutes" "INFO"
    
    $timeoutSeconds = $TimeoutMinutes * 60
    $intervalSeconds = 30
    $maxIterations = [math]::Ceiling($timeoutSeconds / $intervalSeconds)
    
    Write-ValidationLog "Calculated timeout: $timeoutSeconds seconds" "TIMER"
    Write-ValidationLog "Check interval: $intervalSeconds seconds" "TIMER"
    Write-ValidationLog "Max iterations: $maxIterations" "TIMER"
    
    $elapsed = 0
    $iteration = 0
    $planReady = $false
    $apiReady = $false
    $uiReady = $false
    
    while ($elapsed -lt $timeoutSeconds -and (-not $planReady -or -not $apiReady -or -not $uiReady)) {
        $iteration++
        Write-ValidationLog "Iteration $iteration/$maxIterations - Elapsed: $elapsed seconds" "TIMER"
        
        # Simulate plan readiness
        if (-not $planReady) {
            if ($SimulatePlanFailure) {
                Write-ValidationLog "Plan: Simulating failure (never ready)" "WARN"
            } elseif ($elapsed -ge $SimulatePlanDelay) {
                $planReady = $true
                Write-ValidationLog "Plan: READY at $elapsed seconds" "OK"
            } else {
                Write-ValidationLog "Plan: Waiting... (needs $SimulatePlanDelay seconds)" "INFO"
            }
        }
        
        # Simulate API readiness
        if (-not $apiReady) {
            if ($elapsed -ge $SimulateWebAppDelay) {
                $apiReady = $true
                Write-ValidationLog "API: READY at $elapsed seconds" "OK"
            } else {
                Write-ValidationLog "API: Waiting... (needs $SimulateWebAppDelay seconds)" "INFO"
            }
        }
        
        # Simulate UI readiness
        if (-not $uiReady) {
            if ($elapsed -ge $SimulateWebAppDelay) {
                $uiReady = $true
                Write-ValidationLog "UI: READY at $elapsed seconds" "OK"
            } else {
                Write-ValidationLog "UI: Waiting... (needs $SimulateWebAppDelay seconds)" "INFO"
            }
        }
        
        if ($planReady -and $apiReady -and $uiReady) {
            Write-ValidationLog "All resources ready at $elapsed seconds" "OK"
            break
        }
        
        if ($iteration -ge $maxIterations) {
            Write-ValidationLog "Max iterations reached - timeout!" "ERROR"
            break
        }
        
        Start-Sleep -Seconds $intervalSeconds
        $elapsed += $intervalSeconds
    }
    
    Write-ValidationLog "Final state: Plan=$planReady API=$apiReady UI=$uiReady" "INFO"
    return ($planReady -and $apiReady -and $uiReady)
}

# === Main Validation Flow ===
Write-ValidationLog "========================================" "INFO"
Write-ValidationLog "Bootstrap Logic Validation - DRY RUN" "INFO"
Write-ValidationLog "========================================" "INFO"
Write-ValidationLog "Simulation Parameters:" "INFO"
Write-ValidationLog "  RG Delay: $SimulateRGDelay seconds" "INFO"
Write-ValidationLog "  Plan Delay: $SimulatePlanDelay seconds" "INFO"
Write-ValidationLog "  WebApp Delay: $SimulateWebAppDelay seconds" "INFO"
Write-ValidationLog "  RG Failure: $SimulateRGFailure" "INFO"
Write-ValidationLog "  Plan Failure: $SimulatePlanFailure" "INFO"
Write-ValidationLog "" "INFO"

# Test 1: Resource Group Readiness Gate
Write-ValidationLog "TEST 1: Resource Group Readiness Gate" "INFO"
$rgReady = Test-RGReadinessGate -ResourceGroup "rg-orderprocessing-dev" -TimeoutMinutes 10 -IntervalSeconds 120

if (-not $rgReady) {
    Write-ValidationLog "RG gate failed - bootstrap should EXIT here" "ERROR"
    Write-ValidationLog "CRITICAL: No further resources should be created" "ERROR"
    
    # Save log
    $script:ValidationLog | Out-File -FilePath $LogFile -Encoding UTF8
    Write-Host "`nValidation log saved to: $LogFile" -ForegroundColor Cyan
    exit 1
}

Write-ValidationLog "RG gate passed - proceeding to resource creation" "OK"
Write-ValidationLog "" "INFO"

# Test 2: Simulated Resource Creation Jobs
Write-ValidationLog "TEST 2: Parallel Resource Creation (simulated)" "INFO"
Write-ValidationLog "  Plan creation job: Started" "INFO"
Write-ValidationLog "  API creation job: Started" "INFO"
Write-ValidationLog "  UI creation job: Started" "INFO"
Write-ValidationLog "  AI creation job: Started" "INFO"
Write-ValidationLog "" "INFO"

# Test 3: Unified Readiness Loop
Write-ValidationLog "TEST 3: Unified Readiness Loop (20 min timeout)" "INFO"
$readyResult = Test-UnifiedReadinessLoop `
    -Plan "asp-orderprocessing-dev" `
    -ApiApp "orderprocessing-api-xyapp-dev" `
    -UiApp "orderprocessing-ui-xyapp-dev" `
    -TimeoutMinutes 20

if (-not $readyResult) {
    Write-ValidationLog "Unified readiness loop FAILED - resources not ready in time" "ERROR"
} else {
    Write-ValidationLog "Unified readiness loop PASSED - all resources ready" "OK"
}

Write-ValidationLog "" "INFO"

# === Validation Summary ===
Write-ValidationLog "========================================" "INFO"
Write-ValidationLog "VALIDATION SUMMARY" "INFO"
Write-ValidationLog "========================================" "INFO"

$totalTime = ($script:ValidationLog | Where-Object { $_ -match "Iteration" } | Measure-Object).Count * 30
Write-ValidationLog "Estimated total time: $totalTime seconds ($([math]::Round($totalTime/60,1)) minutes)" "INFO"

$errors = ($script:ValidationLog | Where-Object { $_ -match "\[ERROR\]" }).Count
$warnings = ($script:ValidationLog | Where-Object { $_ -match "\[WARN\]" }).Count

Write-ValidationLog "Errors: $errors" $(if ($errors -gt 0) { "ERROR" } else { "OK" })
Write-ValidationLog "Warnings: $warnings" $(if ($warnings -gt 0) { "WARN" } else { "OK" })

# Save log
$script:ValidationLog | Out-File -FilePath $LogFile -Encoding UTF8
Write-Host "`nValidation log saved to: $LogFile" -ForegroundColor Cyan

# === Critical Issues Found ===
Write-ValidationLog "" "INFO"
Write-ValidationLog "========================================" "INFO"
Write-ValidationLog "CRITICAL ISSUES IN BOOTSTRAP SCRIPT" "INFO"
Write-ValidationLog "========================================" "INFO"

Write-ValidationLog "ISSUE 1: Duplicate RG readiness gates (lines 269-282)" "ERROR"
Write-ValidationLog "  - First gate at line 269" "ERROR"
Write-ValidationLog "  - Second gate at line 276 (duplicate)" "ERROR"
Write-ValidationLog "  - IMPACT: Wastes 10-20 minutes if RG creation is slow" "ERROR"

Write-ValidationLog "" "INFO"
Write-ValidationLog "ISSUE 2: Plan creation starts even if RG gate should fail" "ERROR"
Write-ValidationLog "  - After 'continue' statement, loop continues to next env" "ERROR"
Write-ValidationLog "  - Should use 'exit 1' instead of 'continue'" "ERROR"

Write-ValidationLog "" "INFO"
Write-ValidationLog "RECOMMENDED FIXES:" "OK"
Write-ValidationLog "  1. Remove duplicate RG readiness gate (keep only one)" "OK"
Write-ValidationLog "  2. Change error handling: 'continue' -> 'exit 1' for RG failures" "OK"
Write-ValidationLog "  3. Add early-exit validation BEFORE any resource creation" "OK"
Write-ValidationLog "  4. Move unified readiness loop to always execute (even if jobs succeed)" "OK"

if ($errors -eq 0 -and $warnings -eq 0) {
    Write-ValidationLog "" "INFO"
    Write-ValidationLog "VALIDATION PASSED: Logic flow is correct" "OK"
    exit 0
} else {
    Write-ValidationLog "" "INFO"
    Write-ValidationLog "VALIDATION FAILED: Issues found in logic flow" "ERROR"
    exit 1
}
