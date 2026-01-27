#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Automates GitHub App creation using app manifest for XYDataLabs Order Processing System

.DESCRIPTION
    This script simplifies GitHub App creation by:
    1. Reading the app manifest configuration
    2. Generating a unique manifest URL for app creation
    3. Guiding the user through the semi-automated setup process
    4. Validating the created app's configuration
    
    Note: Due to GitHub security requirements, app creation requires interactive user approval.
    This script streamlines the process but cannot fully automate it.

.PARAMETER Repository
    GitHub repository in format owner/repo (default: pavanthakur/XYDataLabs.OrderProcessingSystem)

.PARAMETER AppName
    Name for the GitHub App (default: from manifest)

.PARAMETER ValidateOnly
    Only validate existing app configuration without creating new app

.EXAMPLE
    .\setup-github-app-from-manifest.ps1
    
.EXAMPLE
    .\setup-github-app-from-manifest.ps1 -ValidateOnly

.EXAMPLE
    .\setup-github-app-from-manifest.ps1 -Repository myorg/myrepo -AppName MyCustomApp
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$Repository = "pavanthakur/XYDataLabs.OrderProcessingSystem",
    
    [Parameter(Mandatory=$false)]
    [string]$AppName = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

# Color definitions
$colors = @{
    Header = "Cyan"
    Success = "Green"
    Warning = "Yellow"
    Error = "Red"
    Info = "Gray"
    Prompt = "White"
}

function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor $colors.Header
    Write-Host "║  $($Message.PadRight(60))  ║" -ForegroundColor $colors.Header
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor $colors.Header
    Write-Host ""
}

function Write-Section {
    param([string]$Message)
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $colors.Info
    Write-Host $Message -ForegroundColor $colors.Header
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $colors.Info
    Write-Host ""
}

Write-Header "GitHub App Setup - Manifest-Based Automation"

Write-Host "Repository: $Repository" -ForegroundColor $colors.Info
Write-Host "Timestamp:  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor $colors.Info
Write-Host ""

# Locate manifest file
$scriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptRoot
$manifestPath = Join-Path $repoRoot ".github/app-manifest.json"

if (-not (Test-Path $manifestPath)) {
    Write-Host "❌ Manifest file not found: $manifestPath" -ForegroundColor $colors.Error
    Write-Host ""
    Write-Host "Expected location: .github/app-manifest.json" -ForegroundColor $colors.Info
    exit 1
}

Write-Host "✅ Found manifest: $manifestPath" -ForegroundColor $colors.Success

# Read and parse manifest
try {
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    Write-Host "✅ Manifest parsed successfully" -ForegroundColor $colors.Success
} catch {
    Write-Host "❌ Failed to parse manifest: $($_.Exception.Message)" -ForegroundColor $colors.Error
    exit 1
}

# Override app name if provided
if ($AppName) {
    $manifest.name = $AppName
}

Write-Host ""
Write-Host "📋 Manifest Configuration:" -ForegroundColor $colors.Header
Write-Host "  Name:        $($manifest.name)" -ForegroundColor $colors.Info
Write-Host "  Repository:  $($manifest.url)" -ForegroundColor $colors.Info
Write-Host "  Public:      $($manifest.public)" -ForegroundColor $colors.Info
Write-Host "  Webhook:     $(if ($manifest.hook_attributes.active) { 'Enabled' } else { 'Disabled' })" -ForegroundColor $colors.Info
Write-Host ""
Write-Host "  Permissions:" -ForegroundColor $colors.Header
foreach ($perm in $manifest.default_permissions.PSObject.Properties) {
    Write-Host "    - $($perm.Name.PadRight(20)): $($perm.Value)" -ForegroundColor $colors.Info
}

if ($ValidateOnly) {
    Write-Section "Validation Mode - Checking Existing Configuration"
    
    # Check if gh CLI is available
    $ghInstalled = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $ghInstalled) {
        Write-Host "❌ GitHub CLI (gh) not found" -ForegroundColor $colors.Error
        Write-Host "   Install from: https://cli.github.com/" -ForegroundColor $colors.Info
        exit 1
    }
    
    # Check authentication
    try {
        $ghAuthStatus = gh auth status 2>&1 | Out-String
        if ($ghAuthStatus -notmatch "Logged in to github.com") {
            Write-Host "❌ Not authenticated to GitHub" -ForegroundColor $colors.Error
            Write-Host "   Run: gh auth login" -ForegroundColor $colors.Info
            exit 1
        }
        Write-Host "✅ Authenticated to GitHub" -ForegroundColor $colors.Success
    } catch {
        Write-Host "❌ GitHub authentication check failed" -ForegroundColor $colors.Error
        exit 1
    }
    
    Write-Host ""
    Write-Host "⚠️  Note: Automated app validation via CLI is limited" -ForegroundColor $colors.Warning
    Write-Host "   Manual verification recommended:" -ForegroundColor $colors.Info
    Write-Host "   1. Go to: https://github.com/settings/apps" -ForegroundColor $colors.Info
    Write-Host "   2. Find your app and verify permissions match the manifest" -ForegroundColor $colors.Info
    Write-Host "   3. Ensure app is installed on: $Repository" -ForegroundColor $colors.Info
    Write-Host ""
    
    exit 0
}

Write-Section "App Creation - Semi-Automated Flow"

Write-Host "Due to GitHub security requirements, app creation requires interactive approval." -ForegroundColor $colors.Warning
Write-Host "This script will guide you through the streamlined process." -ForegroundColor $colors.Info
Write-Host ""

# Note: GitHub's app creation from manifest requires a web-based flow
# The manifest needs to be posted to GitHub's endpoint, which requires interactive approval
# We'll provide the manifest in readable form for the user to use

Write-Host "Step 1: Create App from Manifest" -ForegroundColor $colors.Header
Write-Host "  The manifest file contains all required configuration." -ForegroundColor $colors.Info
Write-Host "  Follow these steps:" -ForegroundColor $colors.Info
Write-Host ""
Write-Host "  Option A: Use GitHub's manifest flow (recommended):" -ForegroundColor $colors.Prompt
Write-Host "    1. Go to: https://github.com/settings/apps/new" -ForegroundColor Cyan
Write-Host "    2. Fill in the form using the manifest configuration shown below" -ForegroundColor $colors.Info
Write-Host ""
Write-Host "  Option B: Create manually and match manifest settings" -ForegroundColor $colors.Prompt
Write-Host ""
Write-Host "═══════════════ APP CONFIGURATION (MANIFEST) ═══════════════" -ForegroundColor DarkGray
Write-Host ($manifest | ConvertTo-Json -Depth 10) -ForegroundColor Yellow
Write-Host "═══════════════  END CONFIGURATION  ═══════════════" -ForegroundColor DarkGray
Write-Host ""

Write-Host "Step 2: Generate Private Key" -ForegroundColor $colors.Header
Write-Host "  1. After app creation, scroll to 'Private keys' section" -ForegroundColor $colors.Info
Write-Host "  2. Click 'Generate a private key'" -ForegroundColor $colors.Info
Write-Host "  3. Save the downloaded .pem file securely" -ForegroundColor $colors.Info
Write-Host ""

Write-Host "Step 3: Install App on Repository" -ForegroundColor $colors.Header
Write-Host "  1. Click 'Install App' in left sidebar" -ForegroundColor $colors.Info
Write-Host "  2. Select your account" -ForegroundColor $colors.Info
Write-Host "  3. Choose 'Only select repositories'" -ForegroundColor $colors.Info
Write-Host "  4. Select: $Repository" -ForegroundColor $colors.Info
Write-Host "  5. Click 'Install'" -ForegroundColor $colors.Info
Write-Host ""

Write-Host "Step 4: Add Repository Secrets" -ForegroundColor $colors.Header
Write-Host "  1. Go to: https://github.com/$Repository/settings/secrets/actions" -ForegroundColor $colors.Info
Write-Host "  2. Add two secrets:" -ForegroundColor $colors.Info
Write-Host "     - APP_ID: [From app settings page]" -ForegroundColor $colors.Info
Write-Host "     - APP_PRIVATE_KEY: [Full contents of .pem file]" -ForegroundColor $colors.Info
Write-Host ""

Write-Section "Next Steps"

Write-Host "After completing the setup above:" -ForegroundColor $colors.Header
Write-Host "  1. Run the bootstrap workflow" -ForegroundColor $colors.Info
Write-Host "  2. Enable 'Configure Secrets' option" -ForegroundColor $colors.Info
Write-Host "  3. The workflow will automatically use your GitHub App" -ForegroundColor $colors.Info
Write-Host ""
Write-Host "✅ App will provide automated secret management with zero maintenance!" -ForegroundColor $colors.Success
Write-Host ""

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $colors.Success
Write-Host "Setup guide complete! Follow the steps above to create your GitHub App." -ForegroundColor $colors.Success
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $colors.Success
Write-Host ""

exit 0
