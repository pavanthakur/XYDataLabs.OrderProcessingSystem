#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Wrapper script to configure GitHub secrets and run app environment configuration.

.DESCRIPTION
    Implements Option 3 then Option 1 flow:
    1. Populates GitHub environment secrets via configure-github-secrets.ps1
    2. Runs configure-app-environment.ps1 to set app settings
    3. Validates exit codes at each step
    4. Runs health check on the deployed app

.PARAMETER Environment
    Target environment: dev, staging, or prod

.PARAMETER Repository
    GitHub repository in format owner/repo (e.g., pavanthakur/XYDataLabs.OrderProcessingSystem)

.PARAMETER BaseName
    Base name for resources (default: orderprocessing)

.PARAMETER GitHubOwner
    GitHub repository owner name (default: pavanthakur)

.PARAMETER Force
    Overwrite existing secrets without prompting

.PARAMETER SkipHealthCheck
    Skip health check after configuration

.EXAMPLE
    .\configure-secrets-and-run.ps1 -Environment dev -Repository pavanthakur/XYDataLabs.OrderProcessingSystem

.EXAMPLE
    .\configure-secrets-and-run.ps1 -Environment dev -Force -SkipHealthCheck
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment,
    
    [Parameter(Mandatory=$false)]
    [string]$Repository = "pavanthakur/XYDataLabs.OrderProcessingSystem",
    
    [Parameter(Mandatory=$false)]
    [string]$BaseName = 'orderprocessing',
    
    [Parameter(Mandatory=$false)]
    [string]$GitHubOwner = 'pavanthakur',
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipHealthCheck
)

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     CONFIGURE SECRETS AND RUN - $($Environment.ToUpper().PadRight(29))║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Environment:    $Environment" -ForegroundColor Gray
Write-Host "  Repository:     $Repository" -ForegroundColor Gray
Write-Host "  Base Name:      $BaseName" -ForegroundColor Gray
Write-Host "  GitHub Owner:   $GitHubOwner" -ForegroundColor Gray
Write-Host "  Force Secrets:  $Force" -ForegroundColor Gray
Write-Host "  Skip Health:    $SkipHealthCheck" -ForegroundColor Gray
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host ""

$scriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptRoot
$azureDeploymentScripts = Join-Path $repoRoot "Resources/Azure-Deployment"

# Step 1: Configure GitHub Secrets
Write-Host "[STEP 1/3] Configuring GitHub Secrets..." -ForegroundColor Cyan
Write-Host ""

$configureSecretsScript = Join-Path $azureDeploymentScripts "configure-github-secrets.ps1"

if (-not (Test-Path $configureSecretsScript)) {
    Write-Host "  [ERROR] Script not found: $configureSecretsScript" -ForegroundColor Red
    exit 1
}

try {
    if ($Force) {
        & $configureSecretsScript -Repository $Repository -Force
    } else {
        & $configureSecretsScript -Repository $Repository
    }
    
    $secretsExitCode = $LASTEXITCODE
    
    if ($secretsExitCode -ne 0) {
        Write-Host ""
        Write-Host "  [ERROR] GitHub secrets configuration failed with exit code: $secretsExitCode" -ForegroundColor Red
        Write-Host "  [ACTION] Review the error output above and try again" -ForegroundColor Yellow
        exit $secretsExitCode
    }
    
    Write-Host ""
    Write-Host "  [SUCCESS] GitHub secrets configured successfully" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "  [ERROR] Exception while configuring GitHub secrets: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host ""

# Step 2: Configure App Environment
Write-Host "[STEP 2/3] Configuring App Service Environment..." -ForegroundColor Cyan
Write-Host ""

$configureAppScript = Join-Path $azureDeploymentScripts "configure-app-environment.ps1"

if (-not (Test-Path $configureAppScript)) {
    Write-Host "  [ERROR] Script not found: $configureAppScript" -ForegroundColor Red
    exit 1
}

try {
    & $configureAppScript -Environment $Environment -BaseName $BaseName -GitHubOwner $GitHubOwner
    
    $appConfigExitCode = $LASTEXITCODE
    
    if ($appConfigExitCode -ne 0) {
        Write-Host ""
        Write-Host "  [ERROR] App environment configuration failed with exit code: $appConfigExitCode" -ForegroundColor Red
        Write-Host "  [ACTION] Review the error output above and try again" -ForegroundColor Yellow
        exit $appConfigExitCode
    }
    
    Write-Host ""
    Write-Host "  [SUCCESS] App environment configured successfully" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "  [ERROR] Exception while configuring app environment: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host ""

# Step 3: Health Check
if ($SkipHealthCheck) {
    Write-Host "[STEP 3/3] Skipping health check (--SkipHealthCheck specified)" -ForegroundColor Yellow
    Write-Host ""
} else {
    Write-Host "[STEP 3/3] Running Health Check..." -ForegroundColor Cyan
    Write-Host ""
    
    # Construct app URL based on environment
    # Note: This naming convention matches configure-app-environment.ps1 and GitHub workflows
    # Format: {owner}-{basename}-api-xyapp-{env} where staging uses 'stg' abbreviation
    $appName = "$GitHubOwner-$BaseName-api-xyapp-$Environment"
    if ($Environment -eq 'staging') {
        $appName = "$GitHubOwner-$BaseName-api-xyapp-stg"
    }
    
    $apiUrl = "https://$appName.azurewebsites.net"
    $healthUrl = "$apiUrl/api/info/environment"
    
    Write-Host "  Waiting 30 seconds for app to stabilize..." -ForegroundColor Gray
    Start-Sleep -Seconds 30
    
    Write-Host "  Testing health endpoint: $healthUrl" -ForegroundColor Gray
    
    try {
        $response = Invoke-WebRequest -Uri $healthUrl -Method Get -TimeoutSec 30 -UseBasicParsing
        
        if ($response.StatusCode -eq 200) {
            Write-Host "  [SUCCESS] Health check passed (HTTP $($response.StatusCode))" -ForegroundColor Green
            
            # Parse and display environment info
            try {
                $envInfo = $response.Content | ConvertFrom-Json
                Write-Host ""
                Write-Host "  Environment Info:" -ForegroundColor Cyan
                Write-Host "    Environment: $($envInfo.Environment)" -ForegroundColor Gray
                Write-Host "    Deployment:  $($envInfo.DeploymentType)" -ForegroundColor Gray
                Write-Host "    Timestamp:   $($envInfo.Timestamp)" -ForegroundColor Gray
            }
            catch {
                Write-Host "  [INFO] Could not parse environment info from response" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  [WARNING] Health check returned unexpected status: $($response.StatusCode)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  [ERROR] Health check failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  [INFO] App may still be starting up. Check Azure Portal for details." -ForegroundColor Yellow
        Write-Host "  [URL] $apiUrl" -ForegroundColor Gray
        exit 1
    }
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host "✅ CONFIGURATION AND DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host ""
Write-Host "Summary:" -ForegroundColor Yellow
Write-Host "  1. GitHub secrets configured" -ForegroundColor Green
Write-Host "  2. App Service environment configured" -ForegroundColor Green
if (-not $SkipHealthCheck) {
    Write-Host "  3. Health check passed" -ForegroundColor Green
}
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  • Verify app settings in Azure Portal" -ForegroundColor Gray
Write-Host "  • Test API: $apiUrl/swagger" -ForegroundColor Gray
Write-Host "  • Monitor Application Insights for telemetry" -ForegroundColor Gray
Write-Host ""

exit 0
