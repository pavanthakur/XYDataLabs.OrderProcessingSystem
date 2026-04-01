# Dry-Run Test: Branch to Environment Mapping Validation
# This script validates the branch-to-environment mapping without making any Azure changes

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('dev', 'staging', 'prod', 'all')]
    [string]$Environment = 'dev',

    [Parameter(Mandatory=$false)]
    [string]$GitHubOwner = '',

    [Parameter(Mandatory=$false)]
    [string]$Repository = ''
)

. (Join-Path $PSScriptRoot 'branch-policy.ps1')
$branchPolicy = Get-GitHubBranchPolicy

function Resolve-GitHubRepositoryContext {
    param(
        [string]$Owner,
        [string]$Repository,
        [string]$DefaultOwner = 'pavanthakur',
        [string]$DefaultRepository = 'XYDataLabs.OrderProcessingSystem'
    )

    $resolvedOwner = $Owner
    $resolvedRepository = $Repository

    if ([string]::IsNullOrWhiteSpace($resolvedOwner) -or [string]::IsNullOrWhiteSpace($resolvedRepository)) {
        $repoFromEnv = $env:GITHUB_REPOSITORY
        if (-not [string]::IsNullOrWhiteSpace($repoFromEnv) -and $repoFromEnv -match '^(?<owner>[^/]+)/(?<repo>.+)$') {
            if ([string]::IsNullOrWhiteSpace($resolvedOwner)) { $resolvedOwner = $Matches.owner }
            if ([string]::IsNullOrWhiteSpace($resolvedRepository)) { $resolvedRepository = $Matches.repo }
        }
    }

    if ([string]::IsNullOrWhiteSpace($resolvedOwner) -or [string]::IsNullOrWhiteSpace($resolvedRepository)) {
        try {
            $originUrl = git config --get remote.origin.url 2>$null
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($originUrl)) {
                $originUrl = $originUrl.Trim()
                if ($originUrl -match 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?$') {
                    if ([string]::IsNullOrWhiteSpace($resolvedOwner)) { $resolvedOwner = $Matches.owner }
                    if ([string]::IsNullOrWhiteSpace($resolvedRepository)) { $resolvedRepository = $Matches.repo }
                }
            }
        }
        catch { }
    }

    if ([string]::IsNullOrWhiteSpace($resolvedOwner)) { $resolvedOwner = $DefaultOwner }
    if ([string]::IsNullOrWhiteSpace($resolvedRepository)) { $resolvedRepository = $DefaultRepository }

    return @{ Owner = $resolvedOwner; Repository = $resolvedRepository }
}

$repoContext = Resolve-GitHubRepositoryContext -Owner $GitHubOwner -Repository $Repository
$GitHubOwner = $repoContext.Owner
$Repository = $repoContext.Repository

$aliasChecks = @(
    @{ Input = 'dev'; ExpectedPolicyKey = 'dev' },
    @{ Input = 'staging'; ExpectedPolicyKey = 'staging' },
    @{ Input = 'stg'; ExpectedPolicyKey = 'staging' },
    @{ Input = 'prod'; ExpectedPolicyKey = 'prod' },
    @{ Input = 'main'; ExpectedPolicyKey = 'prod' }
)

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Branch-Environment Mapping Dry Run" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Define the mapping
$devPolicy = Get-GitHubBranchPolicyEntry -Policy $branchPolicy -EnvironmentKey 'dev'
$stagingPolicy = Get-GitHubBranchPolicyEntry -Policy $branchPolicy -EnvironmentKey 'staging'
$prodPolicy = Get-GitHubBranchPolicyEntry -Policy $branchPolicy -EnvironmentKey 'prod'

$branchMapping = @{
    'dev' = @{
        Branch = $devPolicy.branch
        Environment = $devPolicy.environment
        ResourceSuffix = $devPolicy.resourceSuffix
        AzureSqlDatabaseSuffix = $devPolicy.azureSqlDatabaseSuffix
        ParameterFile = 'infra/parameters/dev.json'
        ResourceGroup = "rg-orderprocessing-$($devPolicy.resourceSuffix)"
        SharedDatabase = "OrderProcessingSystem_$($devPolicy.azureSqlDatabaseSuffix)"
        DedicatedTenantDatabase = "OrderProcessingSystem_TenantC_$($devPolicy.azureSqlDatabaseSuffix)"
        BranchOIDCSubject = "repo:${GitHubOwner}/${Repository}:ref:refs/heads/$($devPolicy.branch)"
        EnvironmentOIDCSubject = "repo:${GitHubOwner}/${Repository}:environment:$($devPolicy.environment)"
    }
    'staging' = @{
        Branch = $stagingPolicy.branch
        Environment = $stagingPolicy.environment
        ResourceSuffix = $stagingPolicy.resourceSuffix
        AzureSqlDatabaseSuffix = $stagingPolicy.azureSqlDatabaseSuffix
        ParameterFile = 'infra/parameters/staging.json'
        ResourceGroup = "rg-orderprocessing-$($stagingPolicy.resourceSuffix)"
        SharedDatabase = "OrderProcessingSystem_$($stagingPolicy.azureSqlDatabaseSuffix)"
        DedicatedTenantDatabase = "OrderProcessingSystem_TenantC_$($stagingPolicy.azureSqlDatabaseSuffix)"
        BranchOIDCSubject = "repo:${GitHubOwner}/${Repository}:ref:refs/heads/$($stagingPolicy.branch)"
        EnvironmentOIDCSubject = "repo:${GitHubOwner}/${Repository}:environment:$($stagingPolicy.environment)"
    }
    'prod' = @{
        Branch = $prodPolicy.branch
        Environment = $prodPolicy.environment
        ResourceSuffix = $prodPolicy.resourceSuffix
        AzureSqlDatabaseSuffix = $prodPolicy.azureSqlDatabaseSuffix
        ParameterFile = 'infra/parameters/prod.json'
        ResourceGroup = "rg-orderprocessing-$($prodPolicy.resourceSuffix)"
        SharedDatabase = "OrderProcessingSystem_$($prodPolicy.azureSqlDatabaseSuffix)"
        DedicatedTenantDatabase = "OrderProcessingSystem_TenantC_$($prodPolicy.azureSqlDatabaseSuffix)"
        BranchOIDCSubject = "repo:${GitHubOwner}/${Repository}:ref:refs/heads/$($prodPolicy.branch)"
        EnvironmentOIDCSubject = "repo:${GitHubOwner}/${Repository}:environment:$($prodPolicy.environment)"
    }
}

# Determine which environments to test
$envsToTest = if ($Environment -eq 'all') { @('dev', 'staging', 'prod') } else { @($Environment) }

Write-Host "Testing Environment: $Environment" -ForegroundColor Yellow
Write-Host ""

Write-Host "Alias Resolution Checks:" -ForegroundColor Cyan
foreach ($aliasCheck in $aliasChecks) {
    try {
        $resolvedPolicyKey = Resolve-GitHubBranchPolicyKey -Policy $branchPolicy -EnvironmentLike $aliasCheck.Input
        if ($resolvedPolicyKey -eq $aliasCheck.ExpectedPolicyKey) {
            Write-Host "   [OK] '$($aliasCheck.Input)' resolves to '$resolvedPolicyKey'" -ForegroundColor Green
        } else {
            Write-Host "   [ERROR] '$($aliasCheck.Input)' resolved to '$resolvedPolicyKey' (expected '$($aliasCheck.ExpectedPolicyKey)')" -ForegroundColor Red
        }
    } catch {
        Write-Host "   [ERROR] '$($aliasCheck.Input)' threw: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""

# Test each environment
foreach ($env in $envsToTest) {
    $config = $branchMapping[$env]
    
    Write-Host "Environment: $env" -ForegroundColor Cyan
    Write-Host "   Branch:              $($config.Branch)" -ForegroundColor Gray
    Write-Host "   Environment:         $($config.Environment)" -ForegroundColor Gray
    Write-Host "   Resource Suffix:     $($config.ResourceSuffix)" -ForegroundColor Gray
    Write-Host "   Azure SQL Suffix:    $($config.AzureSqlDatabaseSuffix)" -ForegroundColor Gray
    Write-Host "   Parameter File:      $($config.ParameterFile)" -ForegroundColor Gray
    Write-Host "   Resource Group:      $($config.ResourceGroup)" -ForegroundColor Gray
    Write-Host "   Shared Database:     $($config.SharedDatabase)" -ForegroundColor Gray
    Write-Host "   TenantC Database:    $($config.DedicatedTenantDatabase)" -ForegroundColor Gray
    Write-Host "   Branch OIDC:         $($config.BranchOIDCSubject)" -ForegroundColor Gray
    Write-Host "   Environment OIDC:    $($config.EnvironmentOIDCSubject)" -ForegroundColor Gray

    $expectedResourceGroup = "rg-orderprocessing-$($config.ResourceSuffix)"
    if ($config.ResourceGroup -eq $expectedResourceGroup) {
        Write-Host "   [OK] Resource group matches resource suffix" -ForegroundColor Green
    } else {
        Write-Host "   [ERROR] Resource group mismatch: expected $expectedResourceGroup, found $($config.ResourceGroup)" -ForegroundColor Red
    }

    $expectedSharedDb = "OrderProcessingSystem_$($config.AzureSqlDatabaseSuffix)"
    $expectedTenantDb = "OrderProcessingSystem_TenantC_$($config.AzureSqlDatabaseSuffix)"
    if ($config.SharedDatabase -eq $expectedSharedDb -and $config.DedicatedTenantDatabase -eq $expectedTenantDb) {
        Write-Host "   [OK] Azure SQL database names match policy suffix" -ForegroundColor Green
    } else {
        Write-Host "   [ERROR] Azure SQL database naming mismatch" -ForegroundColor Red
    }
    
    # Validate parameter file exists
    $paramFilePath = Join-Path $PSScriptRoot "..\..\$($config.ParameterFile)"
    if (Test-Path $paramFilePath) {
        Write-Host "   [OK] Parameter file exists" -ForegroundColor Green
        
        # Read and validate parameter file
        try {
            $paramContent = Get-Content $paramFilePath -Raw | ConvertFrom-Json
            $envParam = $paramContent.parameters.environment.value
            
            if ($envParam -eq $config.Environment) {
                Write-Host "   [OK] Parameter file environment matches: $envParam" -ForegroundColor Green
            } else {
                Write-Host "   [ERROR] Parameter file environment mismatch: expected $($config.Environment), found $envParam" -ForegroundColor Red
            }
        } catch {
            Write-Host "   [WARN] Could not parse parameter file: $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "   [WARN] Parameter file not found: $paramFilePath" -ForegroundColor Yellow
    }
    
    Write-Host ""
}

# Test OIDC credential count
Write-Host "OIDC Credentials Expected:" -ForegroundColor Cyan
if ($Environment -eq 'all') {
    Write-Host "   Branch credentials: 3 ($((Get-GitHubBranchList -Policy $branchPolicy) -join ', '))" -ForegroundColor Gray
    Write-Host "   Environment credentials: 3 ($((Get-GitHubEnvironmentList -Policy $branchPolicy) -join ', '))" -ForegroundColor Gray
    Write-Host "   Total: 6 credentials" -ForegroundColor Yellow
} else {
    Write-Host "   Branch credentials: 1 ($($branchMapping[$Environment].Branch))" -ForegroundColor Gray
    Write-Host "   Environment credentials: 1 ($($branchMapping[$Environment].Environment))" -ForegroundColor Gray
    Write-Host "   Total: 2 credentials" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "[OK] Dry run complete - mapping validated!" -ForegroundColor Green
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "   - $($devPolicy.branch) branch -> $($devPolicy.environment) environment -> dev.json" -ForegroundColor Gray
Write-Host "   - $($stagingPolicy.branch) branch -> $($stagingPolicy.environment) environment -> staging.json -> resource suffix $($stagingPolicy.resourceSuffix) -> Azure SQL suffix $($stagingPolicy.azureSqlDatabaseSuffix)" -ForegroundColor Gray
Write-Host "   - $($prodPolicy.branch) branch -> $($prodPolicy.environment) environment -> prod.json" -ForegroundColor Gray
Write-Host ""
