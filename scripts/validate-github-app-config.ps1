#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Validates GitHub App configuration for XYDataLabs Order Processing System

.DESCRIPTION
    This script validates that the GitHub App is properly configured with all required:
    - Permissions (Actions, Administration, Contents, Environments, Metadata, Pull Requests, Secrets, Workflows)
    - Installation on the repository
    - Secrets (APP_ID, APP_PRIVATE_KEY)
    - Ability to generate installation tokens
    
    Use this script to diagnose issues with GitHub App authentication.

.PARAMETER Repository
    GitHub repository in format owner/repo

.PARAMETER AppId
    GitHub App ID (optional, will use APP_ID environment variable if not provided)

.PARAMETER Detailed
    Show detailed validation output

.EXAMPLE
    .\validate-github-app-config.ps1 -Repository pavanthakur/XYDataLabs.OrderProcessingSystem

.EXAMPLE
    .\validate-github-app-config.ps1 -Detailed
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$Repository = "pavanthakur/XYDataLabs.OrderProcessingSystem",
    
    [Parameter(Mandatory=$false)]
    [string]$AppId = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$Detailed
)

$ErrorActionPreference = 'Continue'  # Continue on errors to provide complete validation report

$colors = @{
    Header = "Cyan"
    Success = "Green"
    Warning = "Yellow"
    Error = "Red"
    Info = "Gray"
}

function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor $colors.Header
    Write-Host "║  $($Message.PadRight(60))  ║" -ForegroundColor $colors.Header
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor $colors.Header
    Write-Host ""
}

function Test-Check {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Message = "",
        [string]$SuccessMessage = "",
        [string]$FailureMessage = ""
    )
    
    if ($Passed) {
        Write-Host "  ✅ $Name" -ForegroundColor $colors.Success
        if ($SuccessMessage -and $Detailed) {
            Write-Host "     $SuccessMessage" -ForegroundColor $colors.Info
        }
        return $true
    } else {
        Write-Host "  ❌ $Name" -ForegroundColor $colors.Error
        if ($FailureMessage) {
            Write-Host "     $FailureMessage" -ForegroundColor $colors.Warning
        }
        return $false
    }
}

Write-Header "GitHub App Configuration Validator"

Write-Host "Repository: $Repository" -ForegroundColor $colors.Info
Write-Host "Timestamp:  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor $colors.Info
Write-Host ""

$owner, $repo = $Repository -split '/', 2
$validationResults = @{
    Total = 0
    Passed = 0
    Failed = 0
}

# Check 1: GitHub CLI
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $colors.Info
Write-Host "Prerequisites" -ForegroundColor $colors.Header
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $colors.Info
Write-Host ""

$validationResults.Total++
$ghInstalled = Get-Command gh -ErrorAction SilentlyContinue
if (Test-Check -Name "GitHub CLI (gh) installed" -Passed ($null -ne $ghInstalled) -FailureMessage "Install from: https://cli.github.com/") {
    $validationResults.Passed++
} else {
    $validationResults.Failed++
}

# Check 2: Authentication
if ($ghInstalled) {
    $validationResults.Total++
    try {
        # Try JSON format first for better reliability
        $authStatus = gh auth status 2>&1
        $isAuthed = $authStatus -match "Logged in to github.com"
        if (Test-Check -Name "GitHub CLI authenticated" -Passed $isAuthed -FailureMessage "Run: gh auth login") {
            $validationResults.Passed++
        } else {
            $validationResults.Failed++
        }
    } catch {
        Test-Check -Name "GitHub CLI authenticated" -Passed $false -FailureMessage "Run: gh auth login"
        $validationResults.Failed++
    }
}

# Check 3: Repository Secrets
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $colors.Info
Write-Host "Repository Secrets" -ForegroundColor $colors.Header
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $colors.Info
Write-Host ""

if ($ghInstalled) {
    try {
        $secrets = gh secret list --repo $Repository 2>&1
        
        $validationResults.Total++
        $hasAppId = $secrets -match "APP_ID"
        if (Test-Check -Name "APP_ID secret exists" -Passed $hasAppId -FailureMessage "Add APP_ID to repository secrets") {
            $validationResults.Passed++
            
            # Try to extract and use APP_ID if not provided
            if (-not $AppId -and $env:APP_ID) {
                $AppId = $env:APP_ID
            }
        } else {
            $validationResults.Failed++
        }
        
        $validationResults.Total++
        $hasPrivateKey = $secrets -match "APP_PRIVATE_KEY"
        if (Test-Check -Name "APP_PRIVATE_KEY secret exists" -Passed $hasPrivateKey -FailureMessage "Add APP_PRIVATE_KEY to repository secrets") {
            $validationResults.Passed++
        } else {
            $validationResults.Failed++
        }
        
    } catch {
        Write-Host "  ⚠️  Could not list secrets: $($_.Exception.Message)" -ForegroundColor $colors.Warning
        Write-Host "     Ensure you have admin access to the repository" -ForegroundColor $colors.Info
    }
}

# Check 4: Environment Secrets
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $colors.Info
Write-Host "Environment Secrets (Azure OIDC)" -ForegroundColor $colors.Header
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $colors.Info
Write-Host ""

$environments = @("dev", "staging", "prod")
$requiredEnvSecrets = @("AZUREAPPSERVICE_CLIENTID", "AZUREAPPSERVICE_TENANTID", "AZUREAPPSERVICE_SUBSCRIPTIONID")

foreach ($env in $environments) {
    Write-Host "Environment: $env" -ForegroundColor $colors.Header
    
    foreach ($secretName in $requiredEnvSecrets) {
        $validationResults.Total++
        try {
            # Check if environment secret exists
            $envSecrets = gh secret list --env $env --repo $Repository 2>&1
            $hasSecret = $envSecrets -match $secretName
            
            if (Test-Check -Name "  $secretName" -Passed $hasSecret -FailureMessage "Configure via bootstrap workflow") {
                $validationResults.Passed++
            } else {
                $validationResults.Failed++
            }
        } catch {
            if ($Detailed) {
                Write-Host "     ⚠️  Could not check: $($_.Exception.Message)" -ForegroundColor $colors.Warning
            }
            $validationResults.Failed++
        }
    }
    Write-Host ""
}

# Check 5: GitHub App Installation
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $colors.Info
Write-Host "GitHub App Installation" -ForegroundColor $colors.Header
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $colors.Info
Write-Host ""

if ($AppId) {
    $validationResults.Total++
    try {
        # Try to get app details
        $appInfo = gh api "/app" --header "Accept: application/vnd.github+json" 2>&1
        $appData = $appInfo | ConvertFrom-Json
        
        if (Test-Check -Name "App accessible via API" -Passed ($null -ne $appData) -SuccessMessage "App Name: $($appData.name)") {
            $validationResults.Passed++
            
            if ($Detailed -and $appData) {
                Write-Host "     App ID: $($appData.id)" -ForegroundColor $colors.Info
                Write-Host "     Owner: $($appData.owner.login)" -ForegroundColor $colors.Info
            }
        } else {
            $validationResults.Failed++
        }
    } catch {
        Test-Check -Name "App accessible via API" -Passed $false -FailureMessage "Verify APP_ID is correct"
        $validationResults.Failed++
        if ($Detailed) {
            Write-Host "     Error: $($_.Exception.Message)" -ForegroundColor $colors.Warning
        }
    }
    
    $validationResults.Total++
    try {
        # Check installations
        $installations = gh api "/app/installations" --header "Accept: application/vnd.github+json" 2>&1 | ConvertFrom-Json
        $repoInstalled = $false
        
        foreach ($install in $installations) {
            if ($install.account.login -eq $owner) {
                $repoInstalled = $true
                break
            }
        }
        
        if (Test-Check -Name "App installed on repository" -Passed $repoInstalled -FailureMessage "Install app at: https://github.com/settings/installations") {
            $validationResults.Passed++
        } else {
            $validationResults.Failed++
        }
    } catch {
        Test-Check -Name "App installed on repository" -Passed $false -FailureMessage "Verify app is installed"
        $validationResults.Failed++
        if ($Detailed) {
            Write-Host "     Error: $($_.Exception.Message)" -ForegroundColor $colors.Warning
        }
    }
} else {
    Write-Host "  ⚠️  APP_ID not provided - skipping app-specific checks" -ForegroundColor $colors.Warning
    Write-Host "     Provide via -AppId parameter or APP_ID environment variable" -ForegroundColor $colors.Info
}

# Check 6: Required Permissions
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $colors.Info
Write-Host "Manual Verification Required" -ForegroundColor $colors.Header
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $colors.Info
Write-Host ""

Write-Host "Please manually verify these permissions at:" -ForegroundColor $colors.Info
Write-Host "  https://github.com/settings/apps" -ForegroundColor Cyan
Write-Host ""
Write-Host "Required permissions:" -ForegroundColor $colors.Header
Write-Host "  ✓ Actions: Read and write" -ForegroundColor $colors.Info
Write-Host "  ✓ Administration: Read and write" -ForegroundColor $colors.Info
Write-Host "  ✓ Contents: Read" -ForegroundColor $colors.Info
Write-Host "  ✓ Environments: Read and write (CRITICAL - for environment secrets)" -ForegroundColor $colors.Info
Write-Host "  ✓ Metadata: Read (mandatory)" -ForegroundColor $colors.Info
Write-Host "  ✓ Pull requests: Read and write" -ForegroundColor $colors.Info
Write-Host "  ✓ Secrets: Read and write (CRITICAL)" -ForegroundColor $colors.Info
Write-Host "  ✓ Workflows: Read and write" -ForegroundColor $colors.Info
Write-Host ""

# Summary
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $colors.Info
Write-Host "Validation Summary" -ForegroundColor $colors.Header
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $colors.Info
Write-Host ""

Write-Host "Total Checks: $($validationResults.Total)" -ForegroundColor $colors.Info
Write-Host "Passed:       $($validationResults.Passed)" -ForegroundColor $(if ($validationResults.Passed -eq $validationResults.Total) { $colors.Success } else { $colors.Info })
Write-Host "Failed:       $($validationResults.Failed)" -ForegroundColor $(if ($validationResults.Failed -gt 0) { $colors.Error } else { $colors.Success })
Write-Host ""

if ($validationResults.Failed -eq 0) {
    Write-Host "✅ All automated checks passed!" -ForegroundColor $colors.Success
    Write-Host "   Don't forget to manually verify permissions." -ForegroundColor $colors.Info
    exit 0
} else {
    Write-Host "❌ Some checks failed" -ForegroundColor $colors.Error
    Write-Host "   Review the failures above and take corrective action" -ForegroundColor $colors.Warning
    Write-Host ""
    Write-Host "Common fixes:" -ForegroundColor $colors.Header
    Write-Host "  1. Install GitHub CLI: https://cli.github.com/" -ForegroundColor $colors.Info
    Write-Host "  2. Authenticate: gh auth login" -ForegroundColor $colors.Info
    Write-Host "  3. Add secrets: https://github.com/$Repository/settings/secrets/actions" -ForegroundColor $colors.Info
    Write-Host "  4. Install app: https://github.com/settings/installations" -ForegroundColor $colors.Info
    Write-Host "  5. Run bootstrap workflow with 'Configure Secrets' enabled" -ForegroundColor $colors.Info
    exit 1
}
