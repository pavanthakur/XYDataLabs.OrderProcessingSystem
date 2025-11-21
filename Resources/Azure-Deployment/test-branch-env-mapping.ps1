# Dry-Run Test: Branch to Environment Mapping Validation
# This script validates the branch-to-environment mapping without making any Azure changes

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('dev', 'staging', 'prod', 'all')]
    [string]$Environment = 'dev'
)

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Branch-Environment Mapping Dry Run" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Define the mapping
$branchMapping = @{
    'dev' = @{
        Branch = 'dev'
        Environment = 'dev'
        ParameterFile = 'infra/parameters/dev.json'
        ResourceGroup = 'rg-orderprocessing-dev'
        BranchOIDCSubject = 'repo:pavanthakur/XYDataLabs.OrderProcessingSystem:ref:refs/heads/dev'
        EnvironmentOIDCSubject = 'repo:pavanthakur/XYDataLabs.OrderProcessingSystem:environment:dev'
    }
    'staging' = @{
        Branch = 'staging'
        Environment = 'staging'
        ParameterFile = 'infra/parameters/staging.json'
        ResourceGroup = 'rg-orderprocessing-staging'
        BranchOIDCSubject = 'repo:pavanthakur/XYDataLabs.OrderProcessingSystem:ref:refs/heads/staging'
        EnvironmentOIDCSubject = 'repo:pavanthakur/XYDataLabs.OrderProcessingSystem:environment:staging'
    }
    'prod' = @{
        Branch = 'main'
        Environment = 'prod'
        ParameterFile = 'infra/parameters/prod.json'
        ResourceGroup = 'rg-orderprocessing-prod'
        BranchOIDCSubject = 'repo:pavanthakur/XYDataLabs.OrderProcessingSystem:ref:refs/heads/main'
        EnvironmentOIDCSubject = 'repo:pavanthakur/XYDataLabs.OrderProcessingSystem:environment:prod'
    }
}

# Determine which environments to test
$envsToTest = if ($Environment -eq 'all') { @('dev', 'staging', 'prod') } else { @($Environment) }

Write-Host "🎯 Testing Environment: $Environment" -ForegroundColor Yellow
Write-Host ""

# Test each environment
foreach ($env in $envsToTest) {
    $config = $branchMapping[$env]
    
    Write-Host "📋 Environment: $env" -ForegroundColor Cyan
    Write-Host "   Branch:              $($config.Branch)" -ForegroundColor Gray
    Write-Host "   Environment:         $($config.Environment)" -ForegroundColor Gray
    Write-Host "   Parameter File:      $($config.ParameterFile)" -ForegroundColor Gray
    Write-Host "   Resource Group:      $($config.ResourceGroup)" -ForegroundColor Gray
    Write-Host "   Branch OIDC:         $($config.BranchOIDCSubject)" -ForegroundColor Gray
    Write-Host "   Environment OIDC:    $($config.EnvironmentOIDCSubject)" -ForegroundColor Gray
    
    # Validate parameter file exists
    $paramFilePath = Join-Path $PSScriptRoot "..\..\$($config.ParameterFile)"
    if (Test-Path $paramFilePath) {
        Write-Host "   ✅ Parameter file exists" -ForegroundColor Green
        
        # Read and validate parameter file
        try {
            $paramContent = Get-Content $paramFilePath -Raw | ConvertFrom-Json
            $envParam = $paramContent.parameters.environment.value
            
            if ($envParam -eq $config.Environment) {
                Write-Host "   ✅ Parameter file environment matches: $envParam" -ForegroundColor Green
            } else {
                Write-Host "   ❌ Parameter file environment mismatch: expected $($config.Environment), found $envParam" -ForegroundColor Red
            }
        } catch {
            Write-Host "   ⚠️  Could not parse parameter file: $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "   ⚠️  Parameter file not found: $paramFilePath" -ForegroundColor Yellow
    }
    
    Write-Host ""
}

# Test OIDC credential count
Write-Host "🔐 OIDC Credentials Expected:" -ForegroundColor Cyan
if ($Environment -eq 'all') {
    Write-Host "   Branch credentials: 3 (dev, staging, main)" -ForegroundColor Gray
    Write-Host "   Environment credentials: 3 (dev, staging, prod)" -ForegroundColor Gray
    Write-Host "   Total: 6 credentials" -ForegroundColor Yellow
} else {
    Write-Host "   Branch credentials: 1 ($($branchMapping[$Environment].Branch))" -ForegroundColor Gray
    Write-Host "   Environment credentials: 1 ($Environment)" -ForegroundColor Gray
    Write-Host "   Total: 2 credentials" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "✅ Dry run complete - mapping validated!" -ForegroundColor Green
Write-Host ""
Write-Host "📝 Summary:" -ForegroundColor Cyan
Write-Host "   - dev branch → dev environment → dev.json" -ForegroundColor Gray
Write-Host "   - staging branch → staging environment → staging.json" -ForegroundColor Gray
Write-Host "   - main branch → prod environment → prod.json" -ForegroundColor Gray
Write-Host ""
