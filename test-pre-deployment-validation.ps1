<#
.SYNOPSIS
    Test Pre-Deployment Validation Workflow locally
.DESCRIPTION
    Simulates the GitHub Actions validate-deployment.yml workflow by running:
    1. Azure CLI authentication check
    2. Bicep What-If Analysis
    3. OIDC Credential Verification (optional)
    4. SharedSettings Consistency Validation
.PARAMETER Environment
    Target environment (dev|staging|prod). Default: dev
.PARAMETER RunWhatIf
    Execute Bicep what-if analysis. Default: true
.PARAMETER VerifyOIDC
    Verify OIDC federated credentials. Default: false
.PARAMETER CheckConfig
    Validate sharedsettings consistency. Default: true
.PARAMETER ResourceGroupPrefix
    Resource group prefix. Default: xyorderprocessing
.EXAMPLE
    .\test-pre-deployment-validation.ps1 -Environment dev
.EXAMPLE
    .\test-pre-deployment-validation.ps1 -Environment dev -VerifyOIDC
#>
[CmdletBinding()]
param(
    [ValidateSet('dev','staging','prod')]
    [string]$Environment = 'dev',
    
    [bool]$RunWhatIf = $true,
    
    [bool]$VerifyOIDC = $false,
    
    [bool]$CheckConfig = $true,
    
    [string]$ResourceGroupPrefix = 'xyorderprocessing'
)

$ErrorActionPreference = 'Continue'
$script:TestResults = @()
$script:OverallSuccess = $true

function Write-TestHeader {
    param([string]$Title)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Success,
        [string]$Message,
        [int]$ExitCode = 0
    )
    
    $status = if ($Success) { "PASS" } else { "FAIL" }
    $color = if ($Success) { "Green" } else { "Red" }
    
    Write-Host "[$status] $TestName" -ForegroundColor $color
    if ($Message) {
        Write-Host "      $Message" -ForegroundColor Gray
    }
    
    $script:TestResults += [PSCustomObject]@{
        Test = $TestName
        Status = $status
        ExitCode = $ExitCode
        Message = $Message
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    
    if (-not $Success) {
        $script:OverallSuccess = $false
    }
}

function Test-AzureLogin {
    Write-TestHeader "Pre-Flight: Azure CLI Authentication"
    
    try {
        $account = az account show 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($account) {
            Write-TestResult -TestName "Azure CLI Login" -Success $true -Message "Logged in as $($account.user.name) to subscription $($account.name)"
            return $true
        } else {
            Write-TestResult -TestName "Azure CLI Login" -Success $false -Message "Not logged in. Run 'az login' first."
            return $false
        }
    } catch {
        Write-TestResult -TestName "Azure CLI Login" -Success $false -Message $_.Exception.Message
        return $false
    }
}

function Test-BicepWhatIf {
    Write-TestHeader "Test 1: Bicep What-If Analysis"
    
    $scriptPath = Join-Path $PSScriptRoot "Resources\Azure-Deployment\validate-parameters-whatif.ps1"
    
    if (-not (Test-Path $scriptPath)) {
        Write-TestResult -TestName "Bicep What-If" -Success $false -Message "Script not found: $scriptPath"
        return
    }
    
    Write-Host "Executing what-if analysis for environment: $Environment" -ForegroundColor Yellow
    Write-Host "Command: $scriptPath -Environment $Environment -ResourceGroupPrefix $ResourceGroupPrefix`n" -ForegroundColor Gray
    
    try {
        & $scriptPath -Environment $Environment -ResourceGroupPrefix $ResourceGroupPrefix
        $exitCode = $LASTEXITCODE
        
        $success = ($exitCode -eq 0)
        $message = switch ($exitCode) {
            0 { "No high-risk changes detected" }
            2 { "High-risk changes detected (deletes/modifications)" }
            default { "Unexpected exit code: $exitCode" }
        }
        
        Write-TestResult -TestName "Bicep What-If Analysis" -Success $success -Message $message -ExitCode $exitCode
    } catch {
        Write-TestResult -TestName "Bicep What-If Analysis" -Success $false -Message $_.Exception.Message
    }
}

function Test-OIDCCredentials {
    Write-TestHeader "Test 2: OIDC Credential Verification"
    
    $scriptPath = Join-Path $PSScriptRoot "Resources\Azure-Deployment\verify-oidc-credentials.ps1"
    
    if (-not (Test-Path $scriptPath)) {
        Write-TestResult -TestName "OIDC Verification" -Success $false -Message "Script not found: $scriptPath"
        return
    }
    
    Write-Host "Looking up GitHub-Actions-OIDC application..." -ForegroundColor Yellow
    
    try {
        $appId = az ad app list --display-name "GitHub-Actions-OIDC" --query "[0].id" -o tsv 2>$null
        
        if (-not $appId) {
            Write-TestResult -TestName "OIDC Verification" -Success $false -Message "GitHub-Actions-OIDC app not found. Run setup-github-oidc.ps1 first."
            return
        }
        
        Write-Host "App Object ID: $appId" -ForegroundColor Gray
        Write-Host "Command: $scriptPath -AppObjectId $appId`n" -ForegroundColor Gray
        
        & $scriptPath -AppObjectId $appId
        $exitCode = $LASTEXITCODE
        
        $success = ($exitCode -eq 0)
        $message = switch ($exitCode) {
            0 { "All expected federated credentials present" }
            2 { "Missing credentials for one or more environments" }
            default { "Unexpected exit code: $exitCode" }
        }
        
        Write-TestResult -TestName "OIDC Credential Verification" -Success $success -Message $message -ExitCode $exitCode
    } catch {
        Write-TestResult -TestName "OIDC Verification" -Success $false -Message $_.Exception.Message
    }
}

function Test-SharedSettingsConsistency {
    Write-TestHeader "Test 3: SharedSettings Configuration Validation"
    
    $scriptPath = Join-Path $PSScriptRoot "Resources\Azure-Deployment\validate-sharedsettings-diff.ps1"
    
    if (-not (Test-Path $scriptPath)) {
        Write-TestResult -TestName "Config Validation" -Success $false -Message "Script not found: $scriptPath"
        return
    }
    
    Write-Host "Validating sharedsettings consistency across environments..." -ForegroundColor Yellow
    Write-Host "Command: $scriptPath`n" -ForegroundColor Gray
    
    try {
        & $scriptPath
        $exitCode = $LASTEXITCODE
        
        $success = ($exitCode -eq 0)
        $message = switch ($exitCode) {
            0 { "All sharedsettings files aligned" }
            2 { "Configuration drift detected" }
            default { "Unexpected exit code: $exitCode" }
        }
        
        Write-TestResult -TestName "SharedSettings Consistency" -Success $success -Message $message -ExitCode $exitCode
    } catch {
        Write-TestResult -TestName "Config Validation" -Success $false -Message $_.Exception.Message
    }
}

function Show-TestSummary {
    Write-TestHeader "Test Summary"
    
    $script:TestResults | Format-Table Test, Status, ExitCode, Message -AutoSize
    
    $passed = ($script:TestResults | Where-Object { $_.Status -eq 'PASS' }).Count
    $failed = ($script:TestResults | Where-Object { $_.Status -eq 'FAIL' }).Count
    $total = $script:TestResults.Count
    
    Write-Host "`nResults: $passed/$total passed, $failed failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Yellow' })
    
    if ($script:OverallSuccess) {
        Write-Host "`n✓ Pre-Deployment Validation: PASSED" -ForegroundColor Green
        Write-Host "  Ready for deployment to $Environment environment" -ForegroundColor Green
    } else {
        Write-Host "`n✗ Pre-Deployment Validation: FAILED" -ForegroundColor Red
        Write-Host "  Review failures above before proceeding with deployment" -ForegroundColor Red
    }
    
    # Save results to file
    $logFile = Join-Path $PSScriptRoot "logs\pre-deployment-validation-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    $logDir = Split-Path $logFile -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    $script:TestResults | Export-Csv -Path $logFile -NoTypeInformation
    Write-Host "`nDetailed results saved to: $logFile" -ForegroundColor Cyan
}

# Main Execution
Write-Host "=====================================================" -ForegroundColor Magenta
Write-Host " PRE-DEPLOYMENT VALIDATION WORKFLOW TEST" -ForegroundColor Magenta
Write-Host "=====================================================" -ForegroundColor Magenta
Write-Host "Environment: $Environment" -ForegroundColor White
Write-Host "What-If: $RunWhatIf | OIDC: $VerifyOIDC | Config: $CheckConfig" -ForegroundColor White
Write-Host "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White

# Pre-flight check
if (-not (Test-AzureLogin)) {
    Write-Host "`nAborting: Azure CLI authentication required" -ForegroundColor Red
    exit 1
}

# Run validation tests
if ($RunWhatIf) {
    Test-BicepWhatIf
}

if ($VerifyOIDC) {
    Test-OIDCCredentials
}

if ($CheckConfig) {
    Test-SharedSettingsConsistency
}

# Show summary
Show-TestSummary

# Exit with appropriate code
exit $(if ($script:OverallSuccess) { 0 } else { 1 })
