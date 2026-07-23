#Requires -Version 7.0

param(
    [string]$ArtifactRoot = 'TestResults\Phase10\local-setup'
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$solutionPath = Join-Path $workspaceRoot 'XYDataLabs.OrderProcessingSystem.sln'
$artifactsPath = Join-Path $workspaceRoot '.tmp\phase10-repository-validation-artifacts'
$runStartedAt = Get-Date
$runStamp = $runStartedAt.ToString('yyyyMMdd-HHmmss')
$runDir = Join-Path $workspaceRoot (Join-Path $ArtifactRoot "${runStamp}_repository-validation")
$progressLogPath = Join-Path $runDir 'progress.log'
$summaryPath = Join-Path $runDir 'summary.json'
$latestPointerPath = Join-Path $workspaceRoot (Join-Path $ArtifactRoot 'latest-repository-validation.txt')
$testProjects = @(
    'tests\XYDataLabs.OrderProcessingSystem.Domain.Tests\XYDataLabs.OrderProcessingSystem.Domain.Tests.csproj',
    'tests\XYDataLabs.OrderProcessingSystem.Application.Tests\XYDataLabs.OrderProcessingSystem.Application.Tests.csproj',
    'tests\XYDataLabs.OrderProcessingSystem.API.Tests\XYDataLabs.OrderProcessingSystem.API.Tests.csproj',
    'tests\XYDataLabs.OrderProcessingSystem.Architecture.Tests\XYDataLabs.OrderProcessingSystem.Architecture.Tests.csproj',
    'tests\XYDataLabs.OrderProcessingSystem.Gateway.Tests\XYDataLabs.OrderProcessingSystem.Gateway.Tests.csproj'
)

New-Item -ItemType Directory -Path $runDir -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $latestPointerPath) -Force | Out-Null
Set-Content -LiteralPath $latestPointerPath -Value $runDir -Encoding utf8

function Write-RunLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $line = "[{0}] {1}" -f (Get-Date).ToString('o'), $Message
    Write-Host $line
    Add-Content -LiteralPath $progressLogPath -Value $line -Encoding utf8
}

function Write-RunSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Status,

        [string]$Message = ''
    )

    [ordered]@{
        status = $Status
        task = 'phase10-local-setup-repository-validation'
        startedAtIst = $runStartedAt.ToString('o')
        completedAtIst = (Get-Date).ToString('o')
        message = $Message
        reportDirectory = $runDir
        testProjects = $testProjects
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $summaryPath -Encoding utf8
}

Write-RunLog 'Phase 10 repository validation started.'
Write-RunSummary -Status 'running' -Message 'Repository validation checks are running.'

Push-Location $workspaceRoot
try {
    Write-RunLog 'Restoring solution...'
    dotnet restore $solutionPath --artifacts-path $artifactsPath
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet restore failed with exit code $LASTEXITCODE."
    }
    Write-RunLog 'Solution restore passed.'

    Write-RunLog 'Building solution...'
    dotnet build $solutionPath --no-restore --artifacts-path $artifactsPath
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet build failed with exit code $LASTEXITCODE."
    }
    Write-RunLog 'Solution build passed.'

    foreach ($testProject in $testProjects) {
        Write-RunLog "Running unit/regression tests: $testProject"
        dotnet test (Join-Path $workspaceRoot $testProject) --no-build --artifacts-path $artifactsPath --logger "console;verbosity=minimal"
        if ($LASTEXITCODE -ne 0) {
            throw "dotnet test failed for $testProject with exit code $LASTEXITCODE."
        }
        Write-RunLog "Unit/regression tests passed: $testProject"
    }

    Write-RunSummary -Status 'passed' -Message 'Phase 10 repository validation passed.'
    Write-RunLog "Phase 10 repository validation passed. reportDirectory=$runDir"
}
catch {
    Write-RunSummary -Status 'failed' -Message $_.Exception.Message
    Write-RunLog "Phase 10 repository validation failed: $($_.Exception.Message)"
    throw
}
finally {
    Pop-Location
}
