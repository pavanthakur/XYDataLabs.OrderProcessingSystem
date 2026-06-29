#Requires -Version 7.0

param(
    [ValidateRange(1, 365)]
    [int] $KeepDays = 7
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$resultsRoot = Join-Path $workspaceRoot 'TestResults\Integration'

if (-not (Test-Path $resultsRoot)) {
    exit 0
}

$cutoff = (Get-Date).AddDays(-$KeepDays)
Get-ChildItem -LiteralPath $resultsRoot -Directory |
    Where-Object { $_.LastWriteTime -lt $cutoff } |
    Remove-Item -Recurse -Force

$projectFocusedTrx = Join-Path $workspaceRoot 'tests\XYDataLabs.OrderProcessingSystem.Integration.Tests\TestResults\focused.trx'
if (Test-Path $projectFocusedTrx) {
    Remove-Item -LiteralPath $projectFocusedTrx -Force
}
