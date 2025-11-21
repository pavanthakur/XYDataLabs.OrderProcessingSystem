<#
.SYNOPSIS
  Validate Bicep parameter files and run a safe What-If check stub.
.DESCRIPTION
  Non-destructive validation helper for the pre-deployment test workflow. This stub
  verifies parameter files exist and attempts to run an az what-if if az and
  environment connectivity are available. Exit codes:
    0 = success (no high-risk changes or checks not applicable)
    2 = risk detected / warning (what-if returned deletions/changes or non-fatal issues)
    1 = error (missing files, invalid input, or runtime errors)
.EXAMPLE
  ./validate-parameters-whatif.ps1 -Environment dev -ResourceGroupPrefix xyorderprocessing
#>

param(
    [string]$Environment = 'dev',
    [switch]$All,
    [string]$ResourceGroupPrefix = 'xyorderprocessing'
)

function Show-Help {
    Write-Host "Usage: validate-parameters-whatif.ps1 [-Environment <dev|staging|prod|uat>] [-All] [-ResourceGroupPrefix <prefix>]"
}

try {
    # Resolve repository root relative to this script
    $scriptDir = Split-Path -Parent $PSCommandPath
    $resourcesDir = Split-Path -Parent $scriptDir   # .../Resources
    $repoRoot = Split-Path -Parent $resourcesDir    # repo root

    if ($All.IsPresent) {
        $envs = @('dev','staging','prod')
        foreach ($e in $envs) {
            Write-Host "\n--- Testing what-if for environment: $e ---"
            & $MyInvocation.MyCommand.Definition -Environment $e -ResourceGroupPrefix $ResourceGroupPrefix
            $rc = $LASTEXITCODE
            if ($rc -ne 0) { exit $rc }
        }
        exit 0
    }

    # Validate environment value
    if (-not ($Environment -in @('dev','staging','prod','uat'))) {
        Write-Host "Invalid environment: $Environment" -ForegroundColor Red
        Show-Help
        exit 1
    }

    # Parameter file path (repo-relative)
    $paramPath = Join-Path -Path $repoRoot -ChildPath "Resources/Configuration/parameters.$Environment.json"
    if (-not (Test-Path $paramPath)) {
        Write-Host "Parameter file not found: $paramPath" -ForegroundColor Red
        exit 1
    }

    Write-Host "Found parameter file: $paramPath" -ForegroundColor Green

    # Locate a main.bicep template in the repo (best-effort)
    $templateFile = Get-ChildItem -Path $repoRoot -Recurse -Depth 5 -Filter 'main.bicep' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($templateFile) { $templatePath = $templateFile.FullName } else { $templatePath = Join-Path -Path $repoRoot -ChildPath 'main.bicep' }
    if (-not (Test-Path $templatePath)) {
        Write-Host "main.bicep template not found (skipping live what-if): $templatePath" -ForegroundColor Yellow
        exit 0
    }

    # If az CLI is present, attempt a lightweight what-if. If not, return success so tests can proceed.
    $az = (Get-Command az -ErrorAction SilentlyContinue)
    if (-not $az) {
        Write-Host "az CLI not found in runner; skipping live what-if. (This is a safe stub run)" -ForegroundColor Yellow
        exit 0
    }

    # Build a resource group name for the what-if check (non-destructive)
    $rg = "$($ResourceGroupPrefix)-$Environment-rg"
    Write-Host "Attempting az deployment group what-if for resource group: $rg (non-destructive)" -ForegroundColor Cyan

    # Run a what-if and capture structured JSON output. This requires az logged in and proper subscription.
    $whatifJson = az deployment group what-if --resource-group $rg --template-file $templatePath --parameters @${paramPath} --no-progress -o json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $whatifJson) {
        Write-Host "What-If command failed or returned no result. Ensure az is logged in and resource group exists." -ForegroundColor Yellow
        # Treat missing what-if as warning to allow test iteration, but surface as non-zero
        exit 2
    }

    try {
        $whatifObj = $whatifJson | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Host "Unable to parse what-if JSON output" -ForegroundColor Yellow
        exit 2
    }

    # Inspect structured changes if present
    $changes = $null
    if ($whatifObj.properties -and $whatifObj.properties.changes) { $changes = $whatifObj.properties.changes }
    elseif ($whatifObj.changes) { $changes = $whatifObj.changes }

    if ($changes) {
        $deletes = @($changes | Where-Object { $_.changeType -eq 'Delete' })
        if ($deletes.Count -gt 0) {
            Write-Host "What-If detected deletions: $($deletes.Count) - review carefully" -ForegroundColor Yellow
            exit 2
        }
    }

    Write-Host "What-If returned no destructive changes" -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "Error running validate-parameters-whatif: $_" -ForegroundColor Red
    exit 1
}