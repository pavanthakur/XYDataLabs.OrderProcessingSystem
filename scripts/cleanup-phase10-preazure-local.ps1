#Requires -Version 7.0

[CmdletBinding()]
param(
    [switch]$RemoveVolumes
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $workspaceRoot 'compose\docker-compose.phase10.yml'
$envExampleFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local.example'
$envFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local'
$arguments = @(
    'compose',
    '--env-file', $envExampleFile,
    '--env-file', $envFile,
    '-f', $composeFile,
    '--profile', 'data',
    '--profile', 'identity',
    '--profile', 'storage',
    '--profile', 'messaging',
    '--profile', 'apps',
    '--profile', 'functions',
    'down',
    '--remove-orphans'
)

if ($RemoveVolumes) {
    $arguments += '--volumes'
}

Write-Host "Stopping the Phase 10 Pre-Azure local stack. RemoveVolumes=$([bool]$RemoveVolumes)"
& docker @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Phase 10 Pre-Azure cleanup failed with exit code $LASTEXITCODE."
}
