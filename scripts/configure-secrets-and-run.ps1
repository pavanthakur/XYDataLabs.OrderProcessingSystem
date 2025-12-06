#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Configure secrets and run application environment setup

.DESCRIPTION
    This script orchestrates the configuration of GitHub secrets and application environment.
    It calls configure-github-secrets.ps1 and configure-app-environment.ps1 in sequence,
    validates exit codes, and runs a health check at the end.

.PARAMETER Environment
    Target environment (dev, uat, prod)

.PARAMETER ResourceGroup
    Azure Resource Group name

.PARAMETER AppServiceName
    Azure App Service name

.PARAMETER KeyVaultName
    Azure Key Vault name

.PARAMETER HealthCheckUrl
    Optional health check URL (defaults to https://{appservice}.azurewebsites.net/health)

.EXAMPLE
    ./configure-secrets-and-run.ps1 -Environment dev -ResourceGroup rg-orderprocessing-dev -AppServiceName pavanthakur-orderprocessing-api-xyapp-dev -KeyVaultName kv-orderprocessing-dev

.NOTES
    Prerequisites:
    - Azure CLI installed and authenticated
    - GitHub CLI installed and authenticated
    - PowerShell 7.0 or higher
    - Required Azure permissions (Key Vault, App Service)
    - Required GitHub permissions (manage secrets)
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('dev', 'uat', 'prod')]
    [string]$Environment,
    
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,
    
    [Parameter(Mandatory = $true)]
    [string]$AppServiceName,
    
    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,
    
    [Parameter(Mandatory = $false)]
    [string]$HealthCheckUrl
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Script constants
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$CONFIGURE_GITHUB_SECRETS = Join-Path $SCRIPT_DIR "configure-github-secrets.ps1"
$CONFIGURE_APP_ENVIRONMENT = Join-Path $SCRIPT_DIR "configure-app-environment.ps1"

Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Configure Secrets and Run Application Environment" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Environment:       $Environment" -ForegroundColor Yellow
Write-Host "Resource Group:    $ResourceGroup" -ForegroundColor Yellow
Write-Host "App Service:       $AppServiceName" -ForegroundColor Yellow
Write-Host "Key Vault:         $KeyVaultName" -ForegroundColor Yellow
Write-Host ""

# Default health check URL if not provided
if ([string]::IsNullOrWhiteSpace($HealthCheckUrl)) {
    $HealthCheckUrl = "https://${AppServiceName}.azurewebsites.net/health"
    Write-Host "Health Check URL:  $HealthCheckUrl (default)" -ForegroundColor Yellow
} else {
    Write-Host "Health Check URL:  $HealthCheckUrl" -ForegroundColor Yellow
}
Write-Host ""

#region Step 1: Configure GitHub Secrets
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  STEP 1: Configure GitHub Secrets" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""

if (-not (Test-Path $CONFIGURE_GITHUB_SECRETS)) {
    Write-Host "❌ Error: configure-github-secrets.ps1 not found at: $CONFIGURE_GITHUB_SECRETS" -ForegroundColor Red
    Write-Host "   This script is a placeholder. Please create it or skip this step." -ForegroundColor Yellow
    Write-Host ""
} else {
    try {
        Write-Host "📝 Calling: $CONFIGURE_GITHUB_SECRETS" -ForegroundColor Cyan
        & $CONFIGURE_GITHUB_SECRETS -Environment $Environment -KeyVaultName $KeyVaultName
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Error: configure-github-secrets.ps1 failed with exit code: $LASTEXITCODE" -ForegroundColor Red
            exit $LASTEXITCODE
        }
        
        Write-Host "✅ GitHub secrets configured successfully" -ForegroundColor Green
        Write-Host ""
    } catch {
        Write-Host "❌ Error executing configure-github-secrets.ps1: $_" -ForegroundColor Red
        exit 1
    }
}
#endregion

#region Step 2: Configure App Environment
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  STEP 2: Configure Application Environment" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""

if (-not (Test-Path $CONFIGURE_APP_ENVIRONMENT)) {
    Write-Host "❌ Error: configure-app-environment.ps1 not found at: $CONFIGURE_APP_ENVIRONMENT" -ForegroundColor Red
    Write-Host "   This script is a placeholder. Please create it or skip this step." -ForegroundColor Yellow
    Write-Host ""
} else {
    try {
        Write-Host "📝 Calling: $CONFIGURE_APP_ENVIRONMENT" -ForegroundColor Cyan
        & $CONFIGURE_APP_ENVIRONMENT -Environment $Environment -ResourceGroup $ResourceGroup -AppServiceName $AppServiceName -KeyVaultName $KeyVaultName
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Error: configure-app-environment.ps1 failed with exit code: $LASTEXITCODE" -ForegroundColor Red
            exit $LASTEXITCODE
        }
        
        Write-Host "✅ Application environment configured successfully" -ForegroundColor Green
        Write-Host ""
    } catch {
        Write-Host "❌ Error executing configure-app-environment.ps1: $_" -ForegroundColor Red
        exit 1
    }
}
#endregion

#region Step 3: Health Check
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  STEP 3: Health Check" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""

try {
    Write-Host "🏥 Performing health check: $HealthCheckUrl" -ForegroundColor Cyan
    Write-Host "   Waiting for application to start..." -ForegroundColor Gray
    Start-Sleep -Seconds 5
    
    $maxRetries = 3
    $retryDelay = 10
    $success = $false
    
    for ($i = 1; $i -le $maxRetries; $i++) {
        Write-Host "   Attempt $i of $maxRetries..." -ForegroundColor Gray
        
        try {
            $response = Invoke-WebRequest -Uri $HealthCheckUrl -TimeoutSec 30 -UseBasicParsing -ErrorAction Stop
            
            if ($response.StatusCode -eq 200) {
                Write-Host "✅ Health check passed (HTTP $($response.StatusCode))" -ForegroundColor Green
                Write-Host "   Response: $($response.Content.Substring(0, [Math]::Min(100, $response.Content.Length)))..." -ForegroundColor Gray
                $success = $true
                break
            } else {
                Write-Host "⚠️  Unexpected status code: $($response.StatusCode)" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "⚠️  Health check attempt $i failed: $($_.Exception.Message)" -ForegroundColor Yellow
            
            if ($i -lt $maxRetries) {
                Write-Host "   Retrying in $retryDelay seconds..." -ForegroundColor Gray
                Start-Sleep -Seconds $retryDelay
            }
        }
    }
    
    if (-not $success) {
        Write-Host "⚠️  Health check did not pass after $maxRetries attempts" -ForegroundColor Yellow
        Write-Host "   The application may need more time to start, or there may be configuration issues" -ForegroundColor Yellow
        Write-Host "   Please verify manually at: $HealthCheckUrl" -ForegroundColor Yellow
        Write-Host ""
    }
    
} catch {
    Write-Host "⚠️  Health check error: $_" -ForegroundColor Yellow
    Write-Host "   Please verify manually at: $HealthCheckUrl" -ForegroundColor Yellow
    Write-Host ""
}
#endregion

#region Summary
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Configuration Complete" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "✅ All configuration steps completed" -ForegroundColor Green
Write-Host ""
Write-Host "📋 Summary:" -ForegroundColor Cyan
Write-Host "   Environment:       $Environment" -ForegroundColor White
Write-Host "   Resource Group:    $ResourceGroup" -ForegroundColor White
Write-Host "   App Service:       $AppServiceName" -ForegroundColor White
Write-Host "   Key Vault:         $KeyVaultName" -ForegroundColor White
Write-Host "   Health Check URL:  $HealthCheckUrl" -ForegroundColor White
Write-Host ""
Write-Host "🔗 Quick Links:" -ForegroundColor Cyan
Write-Host "   Azure Portal:      https://portal.azure.com/#@/resource/subscriptions/{subscription-id}/resourceGroups/$ResourceGroup" -ForegroundColor Blue
Write-Host "   App Service:       https://portal.azure.com/#@/resource/subscriptions/{subscription-id}/resourceGroups/$ResourceGroup/providers/Microsoft.Web/sites/$AppServiceName" -ForegroundColor Blue
Write-Host "   Key Vault:         https://portal.azure.com/#@/resource/subscriptions/{subscription-id}/resourceGroups/$ResourceGroup/providers/Microsoft.KeyVault/vaults/$KeyVaultName" -ForegroundColor Blue
Write-Host ""
#endregion

exit 0
