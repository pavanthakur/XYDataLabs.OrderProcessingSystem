#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Configures Azure App Service environment variables for OrderProcessingSystem applications.

.DESCRIPTION
    This script configures the ASPNETCORE_ENVIRONMENT variable on Azure App Services
    to ensure proper environment detection in the deployed applications.

.PARAMETER Environment
    Target environment: dev, staging, or prod

.PARAMETER BaseName
    Base name for resources (default: orderprocessing)

.PARAMETER GitHubOwner
    GitHub repository owner name (default: pavanthakur)

.EXAMPLE
    .\configure-app-environment.ps1 -Environment dev
    
.EXAMPLE
    .\configure-app-environment.ps1 -Environment dev -BaseName orderprocessing -GitHubOwner pavanthakur
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment,
    
    [Parameter(Mandatory=$false)]
    [string]$BaseName = 'orderprocessing',
    
    [Parameter(Mandatory=$false)]
    [string]$GitHubOwner = 'pavanthakur'
)

$ErrorActionPreference = 'Stop'

# Environment mapping
$envMap = @{
    'dev' = @{
        Name = 'dev'
        ResourceGroup = "rg-$BaseName-dev"
        ApiApp = "$GitHubOwner-$BaseName-api-xyapp-dev"
        UiApp = "$GitHubOwner-$BaseName-ui-xyapp-dev"
        AspNetCoreEnvironment = 'Development'
    }
    'staging' = @{
        Name = 'staging'
        ResourceGroup = "rg-$BaseName-stg"
        ApiApp = "$GitHubOwner-$BaseName-api-xyapp-stg"
        UiApp = "$GitHubOwner-$BaseName-ui-xyapp-stg"
        AspNetCoreEnvironment = 'Staging'
    }
    'prod' = @{
        Name = 'prod'
        ResourceGroup = "rg-$BaseName-prod"
        ApiApp = "$GitHubOwner-$BaseName-api-xyapp-prod"
        UiApp = "$GitHubOwner-$BaseName-ui-xyapp-prod"
        AspNetCoreEnvironment = 'Production'
    }
}

$config = $envMap[$Environment]

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         CONFIGURE APP SERVICE ENVIRONMENT - $($config.Name.ToUpper().PadRight(19))║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Environment:             $($config.Name)" -ForegroundColor Gray
Write-Host "  Resource Group:          $($config.ResourceGroup)" -ForegroundColor Gray
Write-Host "  API App:                 $($config.ApiApp)" -ForegroundColor Gray
Write-Host "  UI App:                  $($config.UiApp)" -ForegroundColor Gray
Write-Host "  ASPNETCORE_ENVIRONMENT:  $($config.AspNetCoreEnvironment)" -ForegroundColor Gray
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host ""

try {
    # Verify Azure CLI is logged in
    Write-Host "[1/5] Verifying Azure CLI login..." -ForegroundColor Cyan
    $account = az account show 2>&1 | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $account) {
        throw "Not logged in to Azure CLI. Please run 'az login' first."
    }
    Write-Host "  ✅ Logged in as: $($account.user.name)" -ForegroundColor Green
    Write-Host ""
    
    # Verify resource group exists
    Write-Host "[2/5] Verifying resource group..." -ForegroundColor Cyan
    $rgExists = az group exists --name $config.ResourceGroup
    if ($rgExists -ne 'true') {
        throw "Resource group '$($config.ResourceGroup)' does not exist. Run bootstrap first."
    }
    Write-Host "  ✅ Resource group exists: $($config.ResourceGroup)" -ForegroundColor Green
    Write-Host ""
    
    # Configure API App Service
    Write-Host "[3/5] Configuring API App Service environment..." -ForegroundColor Cyan
    Write-Host "  Setting ASPNETCORE_ENVIRONMENT=$($config.AspNetCoreEnvironment) on $($config.ApiApp)..." -ForegroundColor Gray
    
    $apiResult = az webapp config appsettings set `
        --resource-group $config.ResourceGroup `
        --name $config.ApiApp `
        --settings "ASPNETCORE_ENVIRONMENT=$($config.AspNetCoreEnvironment)" `
        2>&1
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to configure API app settings: $apiResult"
    }
    
    Write-Host "  ✅ API App environment configured" -ForegroundColor Green
    Write-Host ""
    
    # Configure UI App Service
    Write-Host "[4/5] Configuring UI App Service environment..." -ForegroundColor Cyan
    Write-Host "  Setting ASPNETCORE_ENVIRONMENT=$($config.AspNetCoreEnvironment) on $($config.UiApp)..." -ForegroundColor Gray
    
    $uiResult = az webapp config appsettings set `
        --resource-group $config.ResourceGroup `
        --name $config.UiApp `
        --settings "ASPNETCORE_ENVIRONMENT=$($config.AspNetCoreEnvironment)" `
        2>&1
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to configure UI app settings: $uiResult"
    }
    
    Write-Host "  ✅ UI App environment configured" -ForegroundColor Green
    Write-Host ""
    
    # Verify configuration
    Write-Host "[5/5] Verifying configuration..." -ForegroundColor Cyan
    
    # Get API app settings
    Write-Host "  Checking API app settings..." -ForegroundColor Gray
    $apiSettings = az webapp config appsettings list `
        --resource-group $config.ResourceGroup `
        --name $config.ApiApp `
        2>&1 | ConvertFrom-Json
    
    $apiEnv = $apiSettings | Where-Object { $_.name -eq 'ASPNETCORE_ENVIRONMENT' }
    if ($apiEnv.value -eq $config.AspNetCoreEnvironment) {
        Write-Host "  ✅ API: ASPNETCORE_ENVIRONMENT = $($apiEnv.value)" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️  API: ASPNETCORE_ENVIRONMENT verification failed" -ForegroundColor Yellow
    }
    
    # Get UI app settings
    Write-Host "  Checking UI app settings..." -ForegroundColor Gray
    $uiSettings = az webapp config appsettings list `
        --resource-group $config.ResourceGroup `
        --name $config.UiApp `
        2>&1 | ConvertFrom-Json
    
    $uiEnv = $uiSettings | Where-Object { $_.name -eq 'ASPNETCORE_ENVIRONMENT' }
    if ($uiEnv.value -eq $config.AspNetCoreEnvironment) {
        Write-Host "  ✅ UI: ASPNETCORE_ENVIRONMENT = $($uiEnv.value)" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️  UI: ASPNETCORE_ENVIRONMENT verification failed" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host "✅ APP SERVICE ENVIRONMENT CONFIGURED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host ""
    Write-Host "Environment Configuration Complete:" -ForegroundColor Yellow
    Write-Host "  API App:  https://$($config.ApiApp).azurewebsites.net" -ForegroundColor Gray
    Write-Host "  UI App:   https://$($config.UiApp).azurewebsites.net" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. Deploy application code using GitHub Actions workflows" -ForegroundColor Gray
    Write-Host "  2. Test API: https://$($config.ApiApp).azurewebsites.net/swagger" -ForegroundColor Gray
    Write-Host "  3. Test UI:  https://$($config.UiApp).azurewebsites.net/" -ForegroundColor Gray
    Write-Host ""
    
    exit 0
}
catch {
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Red
    Write-Host "❌ CONFIGURATION FAILED" -ForegroundColor Red
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    exit 1
}
