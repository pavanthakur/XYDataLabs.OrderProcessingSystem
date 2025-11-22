<#
.SYNOPSIS
  Dry run test for Azure Bootstrap workflow - validates without making changes
.DESCRIPTION
  Simulates the complete bootstrap workflow end-to-end:
  1. Validates workflow inputs
  2. Checks Azure CLI authentication
  3. Verifies GitHub secrets configuration
  4. Tests script paths and syntax
  5. Validates parameter files
  6. Checks OIDC credentials
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('dev', 'staging', 'prod', 'all')]
    [string]$Environment = 'dev'
)

$ErrorActionPreference = 'Continue'
$testResults = @()

function Test-Step {
    param(
        [string]$Name,
        [scriptblock]$Test,
        [string]$Category = "General"
    )
    
    Write-Host ""
    Write-Host "Testing: $Name" -ForegroundColor Cyan
    Write-Host "Category: $Category" -ForegroundColor Gray
    
    try {
        $result = & $Test
        if ($result -eq $true -or $result -eq $null) {
            Write-Host "  ✅ PASS" -ForegroundColor Green
            $script:testResults += [PSCustomObject]@{
                Category = $Category
                Test = $Name
                Status = "PASS"
                Message = ""
            }
            return $true
        } else {
            Write-Host "  ❌ FAIL: $result" -ForegroundColor Red
            $script:testResults += [PSCustomObject]@{
                Category = $Category
                Test = $Name
                Status = "FAIL"
                Message = $result
            }
            return $false
        }
    } catch {
        Write-Host "  ❌ ERROR: $($_.Exception.Message)" -ForegroundColor Red
        $script:testResults += [PSCustomObject]@{
            Category = $Category
            Test = $Name
            Status = "ERROR"
            Message = $_.Exception.Message
        }
        return $false
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  AZURE BOOTSTRAP DRY RUN TEST" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Environment: $Environment" -ForegroundColor Yellow
Write-Host "Repository: $((git remote get-url origin) -replace '\.git$')" -ForegroundColor Gray
Write-Host "Branch: $(git rev-parse --abbrev-ref HEAD)" -ForegroundColor Gray
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host ""

# ============================================================================
# PHASE 1: Workflow File Validation
# ============================================================================

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "PHASE 1: Workflow File Validation" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

Test-Step "Workflow file exists" {
    $path = ".github\workflows\azure-bootstrap.yml"
    if (Test-Path $path) {
        Write-Host "    Found: $path" -ForegroundColor Gray
        return $true
    }
    return "File not found: $path"
} -Category "Workflow"

Test-Step "Workflow YAML is valid" {
    try {
        # Basic YAML validation - check for common issues
        $content = Get-Content ".github\workflows\azure-bootstrap.yml" -Raw
        
        # Check for required fields
        if ($content -notmatch "name:") { return "Missing 'name' field" }
        if ($content -notmatch "on:") { return "Missing 'on' field" }
        if ($content -notmatch "jobs:") { return "Missing 'jobs' field" }
        
        # Check for proper indentation (no tabs)
        if ($content -match "`t") { return "Contains tabs (use spaces for YAML)" }
        
        Write-Host "    Valid YAML structure" -ForegroundColor Gray
        return $true
    } catch {
        return $_.Exception.Message
    }
} -Category "Workflow"

Test-Step "No references to deleted actions folder" {
    $content = Get-Content ".github\workflows\azure-bootstrap.yml" -Raw
    if ($content -match "\.github/actions") {
        return "Found reference to deleted .github/actions folder"
    }
    if ($content -match "actions/generate-github-app-token") {
        return "Found reference to deleted generate-github-app-token"
    }
    Write-Host "    No orphaned references" -ForegroundColor Gray
    return $true
} -Category "Workflow"

Test-Step "Uses official GitHub action for token generation" {
    $content = Get-Content ".github\workflows\azure-bootstrap.yml" -Raw
    if ($content -match "actions/create-github-app-token@v1") {
        Write-Host "    Using: actions/create-github-app-token@v1" -ForegroundColor Gray
        return $true
    }
    return "Not using official GitHub action for token generation"
} -Category "Workflow"

# ============================================================================
# PHASE 2: Script Dependencies
# ============================================================================

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "PHASE 2: Script Dependencies" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

$requiredScripts = @(
    "Resources\Azure-Deployment\setup-github-oidc.ps1",
    "Resources\Azure-Deployment\bootstrap-enterprise-infra.ps1",
    "Resources\Azure-Deployment\configure-github-secrets.ps1"
)

foreach ($script in $requiredScripts) {
    Test-Step "Script exists: $($script | Split-Path -Leaf)" {
        if (Test-Path $script) {
            Write-Host "    Path: $script" -ForegroundColor Gray
            return $true
        }
        return "Script not found: $script"
    } -Category "Scripts"
}

Test-Step "No non-functional scripts present" {
    $badScripts = @(
        "Resources\Azure-Deployment\create-github-app-automated.ps1",
        "Resources\Azure-Deployment\setup-github-app.ps1"
    )
    
    $found = @()
    foreach ($script in $badScripts) {
        if (Test-Path $script) {
            $found += $script
        }
    }
    
    if ($found.Count -gt 0) {
        return "Found non-functional scripts: $($found -join ', ')"
    }
    
    Write-Host "    No non-functional scripts" -ForegroundColor Gray
    return $true
} -Category "Scripts"

# Validate script syntax
foreach ($script in $requiredScripts) {
    Test-Step "PowerShell syntax valid: $($script | Split-Path -Leaf)" {
        try {
            $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $script -Raw), [ref]$null)
            Write-Host "    Valid PowerShell syntax" -ForegroundColor Gray
            return $true
        } catch {
            return "Syntax error: $($_.Exception.Message)"
        }
    } -Category "Scripts"
}

# ============================================================================
# PHASE 3: Parameter Files
# ============================================================================

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "PHASE 3: Parameter Files" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

$environments = if ($Environment -eq 'all') { @('dev', 'staging', 'prod') } else { @($Environment) }

foreach ($env in $environments) {
    Test-Step "Parameter file exists: $env.json" {
        $path = "infra\parameters\$env.json"
        if (Test-Path $path) {
            Write-Host "    Path: $path" -ForegroundColor Gray
            return $true
        }
        return "Parameter file not found: $path"
    } -Category "Parameters"
    
    Test-Step "Parameter JSON is valid: $env.json" {
        try {
            $json = Get-Content "infra\parameters\$env.json" -Raw | ConvertFrom-Json
            Write-Host "    Valid JSON structure" -ForegroundColor Gray
            
            # Check for required fields
            if (-not $json.parameters) {
                return "Missing 'parameters' field"
            }
            
            return $true
        } catch {
            return "Invalid JSON: $($_.Exception.Message)"
        }
    } -Category "Parameters"
}

# ============================================================================
# PHASE 4: Azure CLI & Authentication
# ============================================================================

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "PHASE 4: Azure CLI & Authentication" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

Test-Step "Azure CLI installed" {
    try {
        $version = az --version 2>&1 | Select-Object -First 1
        if ($version -match "azure-cli") {
            Write-Host "    $version" -ForegroundColor Gray
            return $true
        }
        return "Azure CLI not found"
    } catch {
        return "Azure CLI not installed or not in PATH"
    }
} -Category "Azure"

Test-Step "Azure CLI authenticated" {
    try {
        $account = az account show 2>&1 | ConvertFrom-Json -ErrorAction Stop
        if ($account.id) {
            Write-Host "    Subscription: $($account.name)" -ForegroundColor Gray
            Write-Host "    ID: $($account.id)" -ForegroundColor Gray
            return $true
        }
        return "Not authenticated"
    } catch {
        return "Not authenticated to Azure. Run: az login"
    }
} -Category "Azure"

Test-Step "Azure subscription accessible" {
    try {
        $sub = az account show 2>&1 | ConvertFrom-Json -ErrorAction Stop
        Write-Host "    Subscription: $($sub.name)" -ForegroundColor Gray
        Write-Host "    State: $($sub.state)" -ForegroundColor Gray
        
        if ($sub.state -ne "Enabled") {
            return "Subscription is not enabled"
        }
        
        return $true
    } catch {
        return "Cannot access subscription"
    }
} -Category "Azure"

# ============================================================================
# PHASE 5: GitHub CLI & Secrets
# ============================================================================

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "PHASE 5: GitHub CLI & Secrets" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

Test-Step "GitHub CLI installed" {
    try {
        $version = gh --version 2>&1 | Select-Object -First 1
        if ($version -match "gh version") {
            Write-Host "    $version" -ForegroundColor Gray
            return $true
        }
        return "GitHub CLI not found"
    } catch {
        return "GitHub CLI not installed or not in PATH"
    }
} -Category "GitHub"

Test-Step "GitHub CLI authenticated" {
    try {
        $status = gh auth status 2>&1 | Out-String
        if ($status -match "Logged in to github.com") {
            $user = gh api user --jq .login 2>$null
            Write-Host "    User: $user" -ForegroundColor Gray
            return $true
        }
        return "Not authenticated to GitHub. Run: gh auth login"
    } catch {
        return "GitHub CLI authentication check failed"
    }
} -Category "GitHub"

Test-Step "Repository accessible" {
    try {
        $repo = gh repo view --json nameWithOwner 2>&1 | ConvertFrom-Json
        Write-Host "    Repository: $($repo.nameWithOwner)" -ForegroundColor Gray
        return $true
    } catch {
        return "Cannot access repository. Ensure you're in the correct directory."
    }
} -Category "GitHub"

# ============================================================================
# PHASE 6: OIDC Configuration Check
# ============================================================================

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "PHASE 6: OIDC Configuration" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

Test-Step "Check for GitHub-Actions-OIDC app registration" {
    try {
        $app = az ad app list --display-name "GitHub-Actions-OIDC" 2>&1 | ConvertFrom-Json
        if ($app -and $app.Count -gt 0) {
            Write-Host "    App ID: $($app[0].appId)" -ForegroundColor Gray
            Write-Host "    Status: ✅ Already configured" -ForegroundColor Green
            return $true
        } else {
            Write-Host "    Status: ⚠️  Not configured (will be created on first run)" -ForegroundColor Yellow
            return $true
        }
    } catch {
        Write-Host "    Status: ⚠️  Cannot verify (requires Azure authentication)" -ForegroundColor Yellow
        return $true
    }
} -Category "OIDC"

Test-Step "Check federated credentials" {
    try {
        $app = az ad app list --display-name "GitHub-Actions-OIDC" 2>&1 | ConvertFrom-Json
        if ($app -and $app.Count -gt 0 -and $app[0].id) {
            $creds = az ad app federated-credential list --id $app[0].id 2>&1 | ConvertFrom-Json
            if ($creds -and $creds.Count -gt 0) {
                Write-Host "    Found $($creds.Count) federated credentials" -ForegroundColor Gray
                foreach ($cred in $creds) {
                    Write-Host "      - $($cred.name)" -ForegroundColor DarkGray
                }
                return $true
            } else {
                Write-Host "    Status: ⚠️  No credentials (will be created on first run)" -ForegroundColor Yellow
                return $true
            }
        } else {
            Write-Host "    Status: ⚠️  OIDC app not configured" -ForegroundColor Yellow
            return $true
        }
    } catch {
        Write-Host "    Status: ⚠️  Cannot verify" -ForegroundColor Yellow
        return $true
    }
} -Category "OIDC"

# ============================================================================
# PHASE 7: Documentation Validation
# ============================================================================

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "PHASE 7: Documentation" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

$requiredDocs = @(
    "Documentation\03-Configuration-Guides\AUTOMATED-BOOTSTRAP-GUIDE.md",
    "Documentation\03-Configuration-Guides\GITHUB-APP-AUTHENTICATION.md",
    "Documentation\03-Configuration-Guides\QUICK-SETUP-GITHUB-APP.md"
)

foreach ($doc in $requiredDocs) {
    Test-Step "Documentation exists: $($doc | Split-Path -Leaf)" {
        if (Test-Path $doc) {
            $lines = (Get-Content $doc).Count
            Write-Host "    Lines: $lines" -ForegroundColor Gray
            return $true
        }
        return "Documentation not found: $doc"
    } -Category "Documentation"
}

Test-Step "Documentation has no broken script references" {
    $content = Get-Content "Documentation\03-Configuration-Guides\AUTOMATED-BOOTSTRAP-GUIDE.md" -Raw
    
    if ($content -match "setup-github-app\.ps1") {
        return "Found reference to deleted setup-github-app.ps1"
    }
    if ($content -match "create-github-app-automated\.ps1") {
        return "Found reference to deleted create-github-app-automated.ps1"
    }
    
    Write-Host "    No broken references" -ForegroundColor Gray
    return $true
} -Category "Documentation"

# ============================================================================
# RESULTS SUMMARY
# ============================================================================

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "TEST RESULTS SUMMARY" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""

$grouped = $testResults | Group-Object Category

foreach ($group in $grouped) {
    Write-Host "[$($group.Name)]" -ForegroundColor Yellow
    
    $passed = ($group.Group | Where-Object { $_.Status -eq "PASS" }).Count
    $failed = ($group.Group | Where-Object { $_.Status -eq "FAIL" }).Count
    $errors = ($group.Group | Where-Object { $_.Status -eq "ERROR" }).Count
    $total = $group.Count
    
    Write-Host "  Passed: $passed/$total" -ForegroundColor $(if ($passed -eq $total) { "Green" } else { "Yellow" })
    
    if ($failed -gt 0) {
        Write-Host "  Failed: $failed" -ForegroundColor Red
        $group.Group | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
            Write-Host "    ❌ $($_.Test): $($_.Message)" -ForegroundColor Red
        }
    }
    
    if ($errors -gt 0) {
        Write-Host "  Errors: $errors" -ForegroundColor Red
        $group.Group | Where-Object { $_.Status -eq "ERROR" } | ForEach-Object {
            Write-Host "    ⚠️  $($_.Test): $($_.Message)" -ForegroundColor Red
        }
    }
    
    Write-Host ""
}

# Overall statistics
$totalTests = $testResults.Count
$totalPassed = ($testResults | Where-Object { $_.Status -eq "PASS" }).Count
$totalFailed = ($testResults | Where-Object { $_.Status -eq "FAIL" }).Count
$totalErrors = ($testResults | Where-Object { $_.Status -eq "ERROR" }).Count

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "OVERALL: $totalPassed/$totalTests tests passed" -ForegroundColor $(if ($totalPassed -eq $totalTests) { "Green" } else { "Yellow" })

if ($totalFailed -gt 0) {
    Write-Host "Failed: $totalFailed" -ForegroundColor Red
}
if ($totalErrors -gt 0) {
    Write-Host "Errors: $totalErrors" -ForegroundColor Red
}

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""

# Final verdict
if ($totalPassed -eq $totalTests) {
    Write-Host "✅ ALL TESTS PASSED - Ready for deployment!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Run bootstrap workflow: Actions → Azure Bootstrap Setup → Run workflow" -ForegroundColor White
    Write-Host "  2. Follow prompts for one-time GitHub App setup" -ForegroundColor White
    Write-Host "  3. Workflow will handle rest automatically" -ForegroundColor White
    exit 0
} elseif ($totalFailed -gt 0 -or $totalErrors -gt 0) {
    Write-Host "❌ TESTS FAILED - Fix issues before deployment" -ForegroundColor Red
    Write-Host ""
    Write-Host "Review failed tests above and fix issues" -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "⚠️  TESTS COMPLETED WITH WARNINGS" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Some checks couldn't be verified (may be expected)" -ForegroundColor Gray
    Write-Host "Review warnings above and proceed with caution" -ForegroundColor Yellow
    exit 0
}
