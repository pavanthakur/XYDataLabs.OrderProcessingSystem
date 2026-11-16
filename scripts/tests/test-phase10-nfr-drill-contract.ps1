$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\phase10-nfr-drill-contract.ps1')

function Assert-DrillStatus {
    param([string]$Name, [bool]$ExpectedPassed, [hashtable]$Overrides = @{})
    $arguments = @{
        Drill = [ordered]@{ status = 'running' }
        ExecutionPassed = $true
        ProbeStopped = $true
        ConsumersStartExitCode = 0
        ConsumersReady = $true
        EnvironmentRestored = $true
    }
    foreach ($key in $Overrides.Keys) { $arguments[$key] = $Overrides[$key] }
    $result = Complete-Phase10NfrDrillResult @arguments
    $expected = if ($ExpectedPassed) { 'passed' } else { 'failed' }
    if ($result -ne $expected) { throw "${Name}: expected $expected, got $result." }
    if ($ExpectedPassed -and $arguments.Drill.restorationFailures.Count -ne 0) { throw "${Name}: unexpected restoration findings." }
    if (-not $ExpectedPassed -and $arguments.Drill.restorationStatus -eq 'passed' -and $arguments.ExecutionPassed) {
        throw "${Name}: expected a failed restoration to be recorded."
    }
    if ($Name -eq 'drill execution failed' -and $arguments.Drill.restorationStatus -ne 'passed') {
        throw "${Name}: execution failure must remain distinct from successful restoration."
    }
}

Assert-DrillStatus -Name 'complete restoration' -ExpectedPassed $true
Assert-DrillStatus -Name 'probe process not stopped' -ExpectedPassed $false -Overrides @{ ProbeStopped = $false }
Assert-DrillStatus -Name 'consumer start failed' -ExpectedPassed $false -Overrides @{ ConsumersStartExitCode = 1 }
Assert-DrillStatus -Name 'consumer readiness failed' -ExpectedPassed $false -Overrides @{ ConsumersReady = $false }
Assert-DrillStatus -Name 'environment restoration failed' -ExpectedPassed $false -Overrides @{ EnvironmentRestored = $false }
Assert-DrillStatus -Name 'drill execution failed' -ExpectedPassed $false -Overrides @{ ExecutionPassed = $false }
Assert-DrillStatus -Name 'restoration action failed' -ExpectedPassed $false -Overrides @{ RestorationFailures = @('consumer-readiness') }

$cancelledDrill = [ordered]@{ status = 'running' }
$cancelledStatus = Complete-Phase10NfrDrillResult -Drill $cancelledDrill -ExecutionPassed $false `
    -ProbeStopped $true -ConsumersStartExitCode 0 -ConsumersReady $true -EnvironmentRestored $true `
    -ExecutionFailureType 'System.OperationCanceledException'
if ($cancelledStatus -ne 'failed' -or $cancelledDrill.executionStatus -ne 'failed' -or
    $cancelledDrill.executionFailureType -ne 'System.OperationCanceledException' -or
    $cancelledDrill.restorationStatus -ne 'passed') {
    throw 'Cancelled execution must be evidenced separately from successful restoration.'
}

$restoredDrill = [ordered]@{ restorationStatus = 'passed' }
$failedRestoreDrill = [ordered]@{ restorationStatus = 'failed' }
if (-not (Test-Phase10NfrMutationsAllowed -Drill $restoredDrill)) { throw 'A fully restored drill should permit subsequent gated work.' }
if (Test-Phase10NfrMutationsAllowed -Drill $failedRestoreDrill) { throw 'A failed restoration must stop subsequent mutations.' }

Write-Host 'PASS NFR drill finalization fails closed on execution, child-process cleanup, consumer readiness, environment restoration, and finalizer errors.'

$evidencePath = Join-Path ([IO.Path]::GetTempPath()) ('phase10-replay-restoration-' + [guid]::NewGuid().ToString('N') + '.json')
$started = [DateTime]::UtcNow.AddSeconds(-1)
try {
    if (Test-Phase10ReplayRestorationEvidence -Path $evidencePath -NotBeforeUtc $started) { throw 'Missing evidence was accepted.' }
    foreach ($invalid in @('{', '{}', '{"status":"passed","exitCode":0,"inspectExitCode":0,"effectiveSettingMatches":"true"}', '{"status":"failed","exitCode":0,"inspectExitCode":0,"effectiveSettingMatches":true}', '{"status":"passed","exitCode":1,"inspectExitCode":0,"effectiveSettingMatches":true}')) {
        Set-Content -LiteralPath $evidencePath -Value $invalid
        if (Test-Phase10ReplayRestorationEvidence -Path $evidencePath -NotBeforeUtc $started) { throw 'Malformed or failed restoration was accepted.' }
    }
    Set-Content -LiteralPath $evidencePath -Value '{"status":"passed","exitCode":0,"inspectExitCode":0,"effectiveSettingMatches":true}'
    if (-not (Test-Phase10ReplayRestorationEvidence -Path $evidencePath -NotBeforeUtc $started)) { throw 'Valid restoration was rejected.' }
    if (Test-Phase10ReplayRestorationEvidence -Path $evidencePath -NotBeforeUtc ([DateTime]::UtcNow.AddMinutes(1))) { throw 'Stale restoration was accepted.' }
} finally { if (Test-Path -LiteralPath $evidencePath) { Remove-Item -LiteralPath $evidencePath } }
Write-Host 'PASS replay restoration validation: missing, malformed, failed, wrong-type, stale and valid evidence.'
