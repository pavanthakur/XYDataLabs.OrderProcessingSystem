param(
    [switch]$NoRestore
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Command
    )

    Write-Host ""
    Write-Host "=== $Name ===" -ForegroundColor Cyan
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE"
    }
}

Set-Location $repoRoot

$buildArgs = @('build', 'XYDataLabs.OrderProcessingSystem.sln')
if ($NoRestore) {
    $buildArgs += '--no-restore'
}

Invoke-Step -Name 'Build' -Command {
    & dotnet @buildArgs
}

Invoke-Step -Name 'Architecture Tests' -Command {
    $args = @('test', 'tests\XYDataLabs.OrderProcessingSystem.Architecture.Tests\XYDataLabs.OrderProcessingSystem.Architecture.Tests.csproj')
    if ($NoRestore) { $args += '--no-restore' }
    & dotnet @args
}

Invoke-Step -Name 'Gateway Tests' -Command {
    $args = @('test', 'tests\XYDataLabs.OrderProcessingSystem.Gateway.Tests\XYDataLabs.OrderProcessingSystem.Gateway.Tests.csproj')
    if ($NoRestore) { $args += '--no-restore' }
    & dotnet @args
}

Write-Host ""
Write-Host "=== Integration Tests ===" -ForegroundColor Yellow
Write-Host "Skipped in the core closeout runner because integration coverage requires Docker/Testcontainers." -ForegroundColor Yellow
Write-Host "Run the integration-only phase runner on a Docker-capable machine to validate that gate." -ForegroundColor Yellow

Write-Host ""
Write-Host "Phase 9 core closeout sequence completed." -ForegroundColor Green
