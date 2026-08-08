#Requires -Version 7.0

[CmdletBinding()]
param(
    [switch]$DryRun,

    [ValidateRange(60, 3600)]
    [int]$CommandTimeoutSeconds = 900
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$artifactRoot = Join-Path $workspaceRoot 'TestResults\Phase10\local-preazure'
$sequenceStamp = (Get-Date).ToString('yyyyMMdd-HHmmssfff')
$runDir = Join-Path $artifactRoot "${sequenceStamp}_sequence"
$planPath = Join-Path $runDir 'run-plan.txt'
$progressPath = Join-Path $runDir 'progress.log'
$currentStepPath = Join-Path $runDir 'current-step.txt'
$summaryPath = Join-Path $runDir 'summary.json'
$latestPointerPath = Join-Path $artifactRoot 'latest-preazure-sequence.txt'
$failurePointerPath = Join-Path $artifactRoot 'latest-failure-preazure-sequence.txt'
$milestoneScript = Join-Path $PSScriptRoot 'run-phase10-preazure-milestone.ps1'
$istZone = [TimeZoneInfo]::FindSystemTimeZoneById('India Standard Time')

New-Item -ItemType Directory -Path $runDir -Force | Out-Null
Set-Content -LiteralPath $latestPointerPath -Value $runDir -Encoding utf8
Set-Content -LiteralPath $currentStepPath -Value 'initializing' -Encoding utf8

function Get-IstNow {
    [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $istZone)
}

function Write-SequenceLog {
    param([Parameter(Mandatory = $true)][string]$Message)

    $line = '[{0}] [PRE-AZURE] {1}' -f (Get-IstNow).ToString('o'), $Message
    Write-Host $line
    Add-Content -LiteralPath $progressPath -Value $line -Encoding utf8
}

function Write-Summary {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Summary
    )

    $Summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath -Encoding utf8
}

$milestones = @(
    @{ Name = 'L1'; Title = 'Real Services' },
    @{ Name = 'L2'; Title = 'Messaging' },
    @{ Name = 'L3'; Title = 'DLQ and Functions' },
    @{ Name = 'L4'; Title = 'Identity' },
    @{ Name = 'L5'; Title = 'Operational Readiness Proof' },
    @{ Name = 'L6'; Title = 'Pre-Azure Full Validation' }
)

$summary = [ordered]@{
    target = 'phase10-preazure-sequence'
    startedUtc = (Get-Date).ToUniversalTime().ToString('o')
    finishedUtc = $null
    startedIst = (Get-IstNow).ToString('o')
    finishedIst = $null
    status = 'running'
    dryRun = [bool]$DryRun
    runDir = $runDir
    milestones = @()
}

$previousMessagingEnabled = [Environment]::GetEnvironmentVariable('LOCAL_SERVICEBUS_ENABLED')
$previousReplayEnabled = [Environment]::GetEnvironmentVariable('LOCAL_SERVICEBUS_REPLAY_ENABLED')
$env:LOCAL_SERVICEBUS_ENABLED = 'true'
$env:LOCAL_SERVICEBUS_REPLAY_ENABLED = 'true'

Set-Content -LiteralPath $planPath -Value @(
    'Phase 10 Pre-Azure Sequence',
    "Started (IST): $($summary.startedIst)",
    'Purpose: run the complete local pre-Azure ladder in order so the operator does not have to click each milestone manually.',
    'Stages: L1 real services, L2 messaging, L3 DLQ + Functions, L4 identity, L5 NFR, L6 full validation.',
    "Dry run: $([bool]$DryRun)",
    'Policy: stop on the first failed required milestone.'
) -Encoding utf8
Set-Content -LiteralPath $progressPath -Value '' -Encoding utf8

Write-SequenceLog "Sequence initialized. reportDirectory=$runDir"

try {
    foreach ($milestone in $milestones) {
        $name = $milestone.Name
        $title = $milestone.Title
        Set-Content -LiteralPath $currentStepPath -Value $name -Encoding utf8
        Write-SequenceLog "Starting $name - $title"

        $arguments = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', $milestoneScript,
            '-Milestone', $name,
            '-CommandTimeoutSeconds', $CommandTimeoutSeconds
        )
        if ($DryRun) {
            $arguments += '-DryRun'
        }

        & pwsh @arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Phase 10 pre-Azure milestone $name failed with exit code $LASTEXITCODE."
        }

        $pointerSuffix = switch ($name) {
            'L1' { 'real-services' }
            'L2' { 'messaging' }
            'L3' { 'dlq-functions' }
            'L4' { 'identity' }
            'L5' { 'nfr' }
            'L6' { 'full-validation' }
            default { throw "Unknown milestone '$name'." }
        }
        $pointerName = "latest-$($name.ToLowerInvariant())-$pointerSuffix.txt"
        $pointerPath = Join-Path $artifactRoot $pointerName
        $milestoneRunDir = if (Test-Path -LiteralPath $pointerPath) {
            (Get-Content -LiteralPath $pointerPath -Raw).Trim()
        }
        else {
            $null
        }

        $summary.milestones += [ordered]@{
            name = $name
            title = $title
            status = 'passed'
            runDirectory = $milestoneRunDir
            pointerPath = $pointerPath
        }
        Write-Summary -Summary $summary
        Write-SequenceLog "PASS $name - $title"
    }

    $summary.status = if ($DryRun) { 'planned' } else { 'passed' }
    $summary.finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
    $summary.finishedIst = (Get-IstNow).ToString('o')
    Set-Content -LiteralPath $currentStepPath -Value 'completed' -Encoding utf8
    Remove-Item -LiteralPath $failurePointerPath -Force -ErrorAction SilentlyContinue
    Write-Summary -Summary $summary
    Write-SequenceLog "Sequence $($summary.status)."
}
catch {
    $summary.status = 'failed'
    $summary.finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
    $summary.finishedIst = (Get-IstNow).ToString('o')
    $summary.error = $_.Exception.Message
    Set-Content -LiteralPath $currentStepPath -Value 'failed' -Encoding utf8
    Set-Content -LiteralPath $failurePointerPath -Value $runDir -Encoding utf8
    Write-Summary -Summary $summary
    Write-SequenceLog "Sequence FAILED: $($_.Exception.Message)"
    throw
}
finally {
    if ([string]::IsNullOrWhiteSpace($previousMessagingEnabled)) {
        Remove-Item Env:LOCAL_SERVICEBUS_ENABLED -ErrorAction SilentlyContinue
    }
    else {
        $env:LOCAL_SERVICEBUS_ENABLED = $previousMessagingEnabled
    }

    if ([string]::IsNullOrWhiteSpace($previousReplayEnabled)) {
        Remove-Item Env:LOCAL_SERVICEBUS_REPLAY_ENABLED -ErrorAction SilentlyContinue
    }
    else {
        $env:LOCAL_SERVICEBUS_REPLAY_ENABLED = $previousReplayEnabled
    }
}
