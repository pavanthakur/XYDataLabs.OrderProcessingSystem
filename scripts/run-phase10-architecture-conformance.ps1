#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$ArtifactRoot = 'TestResults\Phase10\local-preazure'
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$istZone = [TimeZoneInfo]::FindSystemTimeZoneById('India Standard Time')
$startedAt = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $istZone)
$runStamp = $startedAt.ToString('yyyyMMdd-HHmmssfff')
$runDir = Join-Path $workspaceRoot (Join-Path $ArtifactRoot "${runStamp}_architecture-conformance")
$progressLogPath = Join-Path $runDir 'progress.log'
$currentStepPath = Join-Path $runDir 'current-step.txt'
$summaryPath = Join-Path $runDir 'summary.json'
$latestPointerPath = Join-Path $workspaceRoot (Join-Path $ArtifactRoot 'latest-architecture-conformance.txt')

$steps = [System.Collections.Generic.List[object]]::new()
$summary = [ordered]@{
    task = 'phase10-architecture-conformance'
    status = 'running'
    startedAtIst = $startedAt.ToString('o')
    completedAtIst = $null
    reportDirectory = $runDir
    commitSha = (& git -C $workspaceRoot rev-parse HEAD).Trim()
    steps = $steps
    error = $null
}

New-Item -ItemType Directory -Path $runDir -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $latestPointerPath) -Force | Out-Null
Set-Content -LiteralPath $latestPointerPath -Value $runDir -Encoding utf8
Set-Content -LiteralPath $progressLogPath -Value '' -Encoding utf8
Set-Content -LiteralPath $currentStepPath -Value 'initializing' -Encoding utf8
Set-Content -LiteralPath (Join-Path $runDir 'run-plan.txt') -Encoding utf8 -Value @(
    'Phase 10 architecture conformance gate',
    "Started (IST): $($startedAt.ToString('o'))",
    'Purpose: prove final pre-Azure architecture invariants, ownership boundaries, and gateway topology before full acceptance.',
    'Stages:',
    '1. Run focused Phase 10 architecture tests.',
    '2. Run focused gateway topology tests.',
    '3. Write summary.json and latest pointer.'
)

function Get-IstNow {
    [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $istZone)
}

function Write-Progress {
    param([Parameter(Mandatory = $true)][string]$Message)

    $line = '[{0}] {1}' -f (Get-IstNow).ToString('o'), $Message
    Write-Host $line
    Add-Content -LiteralPath $progressLogPath -Value $line -Encoding utf8
}

function Write-RunSummary {
    $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding utf8
}

function Invoke-LoggedStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Command
    )

    $started = Get-IstNow
    $logName = (($Name -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLowerInvariant()) + '.log'
    $logPath = Join-Path $runDir $logName
    Set-Content -LiteralPath $currentStepPath -Value $Name -Encoding utf8
    Write-Progress "START $Name"

    try {
        & $Command 2>&1 | Tee-Object -FilePath $logPath | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) {
            throw "$Name failed with exit code $LASTEXITCODE."
        }

        $steps.Add([ordered]@{
            name = $Name
            status = 'passed'
            startedAtIst = $started.ToString('o')
            completedAtIst = (Get-IstNow).ToString('o')
            log = $logName
        })
        Write-Progress "PASS $Name"
        Write-RunSummary
    }
    catch {
        $steps.Add([ordered]@{
            name = $Name
            status = 'failed'
            startedAtIst = $started.ToString('o')
            completedAtIst = (Get-IstNow).ToString('o')
            log = $logName
            error = $_.Exception.Message
        })
        $summary.error = $_.Exception.Message
        Write-RunSummary
        throw
    }
}

Write-RunSummary
Write-Progress "Phase 10 architecture conformance initialized. reportDirectory=$runDir"

Push-Location $workspaceRoot
try {
    Invoke-LoggedStep -Name 'Phase 10 architecture invariant tests' -Command {
        dotnet test 'tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests.csproj' `
            --filter 'FullyQualifiedName~Phase10|FullyQualifiedName~ModulePublicApi|FullyQualifiedName~ModuleAssemblyReference|FullyQualifiedName~ModuleBoundary|FullyQualifiedName~ModuleSchema|FullyQualifiedName~OrdersModuleProjectSplit|FullyQualifiedName~OtherModuleProjectSplit|FullyQualifiedName~InventoryBoundary|FullyQualifiedName~NotificationsBoundary|FullyQualifiedName~APISurfaceDrift' `
            --logger "trx;LogFileName=$runDir\architecture-conformance.trx"
    }

    Invoke-LoggedStep -Name 'Phase 10 gateway topology tests' -Command {
        dotnet test 'tests/XYDataLabs.OrderProcessingSystem.Gateway.Tests/XYDataLabs.OrderProcessingSystem.Gateway.Tests.csproj' `
            --filter 'FullyQualifiedName~GatewayTopology' `
            --logger "trx;LogFileName=$runDir\gateway-topology.trx"
    }

    $summary.status = 'passed'
    $summary.completedAtIst = (Get-IstNow).ToString('o')
    Set-Content -LiteralPath $currentStepPath -Value 'completed' -Encoding utf8
    Write-RunSummary
    Write-Progress 'Phase 10 architecture conformance passed.'
}
catch {
    $summary.status = 'failed'
    $summary.completedAtIst = (Get-IstNow).ToString('o')
    $summary.error = $_.Exception.Message
    Set-Content -LiteralPath $currentStepPath -Value 'failed' -Encoding utf8
    Write-RunSummary
    Write-Progress "Phase 10 architecture conformance failed: $($_.Exception.Message)"
    throw
}
finally {
    Pop-Location
}
