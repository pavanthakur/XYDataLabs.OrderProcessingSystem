<#!
.SYNOPSIS
    Runs Azure what-if deployment against main.bicep for specified or all environments.
.DESCRIPTION
    Iterates environment parameter files in infra/parameters (dev, staging, prod by default) and executes
    az deployment group what-if (resource group scope) to preview changes. Summarizes potential deletes/additions/updates.
.PARAMETER Environment
    Single environment name (dev|staging|prod). If omitted and -All not supplied, defaults to dev.
.PARAMETER All
    Switch to run across dev, staging, prod.
.PARAMETER ResourceGroupPrefix
    Base resource group name prefix (e.g. xyorderprocessing). Final name becomes <prefix>-<env>-rg.
.PARAMETER Location
    Azure location (used only if needing to create RG). Default: eastus.
.EXAMPLE
    ./validate-parameters-whatif.ps1 -Environment dev -ResourceGroupPrefix xyorderprocessing
.EXAMPLE
    ./validate-parameters-whatif.ps1 -All -ResourceGroupPrefix xyorderprocessing
.NOTES
    Requires: Azure CLI logged in (az login), permission to read resource groups.
!#>
[CmdletBinding()] param(
    [string]$Environment,
    [switch]$All,
    [string]$ResourceGroupPrefix = 'xyorderprocessing',
    [string]$Location = 'eastus'
)

$ErrorActionPreference = 'Stop'
$script:HadRisk = $false
$root = Split-Path -Parent $PSScriptRoot
$infraRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'infra'
$paramDir = Join-Path $infraRoot 'parameters'
$mainFile = Join-Path $infraRoot 'main.bicep'

if (!(Test-Path $mainFile)) { Write-Error "main.bicep not found at $mainFile" }
if (!(Test-Path $paramDir)) { Write-Error "Parameters directory not found at $paramDir" }

$envs = @()
if ($All) { $envs = 'dev','staging','prod' }
elseif ($Environment) { $envs = @($Environment) }
else { $envs = @('dev') }

function Ensure-ResourceGroup($rgName, $location) {
    $rg = az group show -n $rgName --only-show-errors 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
    if (!$rg) {
        Write-Host "[info] Creating missing resource group $rgName ($location)" -ForegroundColor Yellow
        az group create -n $rgName -l $location --only-show-errors | Out-Null
    }
}

function Run-WhatIf($env) {
    $paramFile = Join-Path $paramDir "$env.json"
    if (!(Test-Path $paramFile)) { Write-Warning "Skipping $env: parameter file missing ($paramFile)"; return }
    $rgName = "$ResourceGroupPrefix-$env-rg"
    Ensure-ResourceGroup $rgName $Location
    Write-Host "\n=== WHAT-IF: $env ($paramFile) ===" -ForegroundColor Cyan
    $raw = az deployment group what-if -g $rgName -f $mainFile -p $paramFile --no-pretty-print --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Warning "what-if failed for $env"; return }
    $json = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if (!$json) { Write-Warning "Unable to parse what-if JSON for $env"; return }
    $changes = $json.changes
    if (!$changes) { Write-Host "No changes detected." -ForegroundColor Green; return }
    $adds = @($changes | Where-Object { $_.changeType -eq 'Create' })
    $mods = @($changes | Where-Object { $_.changeType -eq 'Modify' })
    $deps = @($changes | Where-Object { $_.changeType -eq 'Deploy' })
    $del = @($changes | Where-Object { $_.changeType -eq 'Delete' })

    Write-Host "Adds: $($adds.Count)  Modify: $($mods.Count)  Deploy: $($deps.Count)  Delete: $($del.Count)" -ForegroundColor White

    if ($del.Count -gt 0 -or $mods.Count -gt 0) {
        $script:HadRisk = $true
        Write-Host "Potential risk: deletes or modifications present." -ForegroundColor Yellow
        $del | Select-Object -First 5 | ForEach-Object { Write-Host "  DEL -> $($_.resourceId)" -ForegroundColor DarkYellow }
        $mods | Select-Object -First 5 | ForEach-Object { Write-Host "  MOD -> $($_.resourceId)" -ForegroundColor DarkYellow }
    }
}

foreach ($e in $envs) { Run-WhatIf $e }

if ($script:HadRisk) { Write-Host "\nRisk summary: One or more environments show deletes/modifications." -ForegroundColor Red; exit 2 }
Write-Host "\nAll what-if checks completed without high-risk changes." -ForegroundColor Green; exit 0
