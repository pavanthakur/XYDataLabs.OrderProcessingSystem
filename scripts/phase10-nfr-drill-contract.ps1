function Complete-Phase10NfrDrillResult {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Drill,
        [Parameter(Mandatory = $true)][bool]$ExecutionPassed,
        [Parameter(Mandatory = $true)][bool]$ProbeStopped,
        [Parameter(Mandatory = $true)][int]$ConsumersStartExitCode,
        [Parameter(Mandatory = $true)][bool]$ConsumersReady,
        [Parameter(Mandatory = $true)][bool]$EnvironmentRestored,
        [string]$ExecutionFailureType,
        [string[]]$RestorationFailures = @()
    )

    $failures = @($RestorationFailures | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if (-not $ProbeStopped) { $failures += 'probe-stop' }
    if ($ConsumersStartExitCode -ne 0) { $failures += 'consumer-start' }
    if (-not $ConsumersReady) { $failures += 'consumer-readiness' }
    if (-not $EnvironmentRestored) { $failures += 'environment-restoration' }

    $Drill.probeStopped = $ProbeStopped
    $Drill.consumersRestoredExitCode = $ConsumersStartExitCode
    $Drill.consumersReadyAfterRestore = $ConsumersReady
    $Drill.environmentRestored = $EnvironmentRestored
    $Drill.executionStatus = if ($ExecutionPassed) { 'passed' } else { 'failed' }
    $Drill.executionFailureType = if ($ExecutionPassed) { $null } else { $ExecutionFailureType }
    $Drill.restorationFailures = @($failures | Select-Object -Unique)
    $Drill.restorationStatus = if ($Drill.restorationFailures.Count -eq 0) { 'passed' } else { 'failed' }
    $Drill.status = if ($ExecutionPassed -and $Drill.restorationStatus -eq 'passed') { 'passed' } else { 'failed' }
    return $Drill.status
}

function Test-Phase10NfrMutationsAllowed {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Drill)
    return $Drill.restorationStatus -eq 'passed'
}

function Test-Phase10ReplayRestorationEvidence {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][DateTime]$NotBeforeUtc)
    try {
        $file = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($file.PSIsContainer -or $file.Length -gt 65536 -or $file.LastWriteTimeUtc -lt $NotBeforeUtc -or
            ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $false }
        $record = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        return $record.status -ceq 'passed' -and $record.exitCode -is [long] -and $record.exitCode -eq 0 -and
            $record.inspectExitCode -is [long] -and $record.inspectExitCode -eq 0 -and
            $record.effectiveSettingMatches -is [bool] -and $record.effectiveSettingMatches
    } catch { return $false }
}
