param(
    [ValidateRange(1,3)]
    [int]$MaxRetries = 3,

    [ValidateRange(5,60)]
    [int]$HealthWaitSeconds = 30
)

$slices = @('9.3', '9.4', '9.5', '9.6', '9.7', '9.8', '9.9', '9.10', '9.11', '9.12', '9.13', '9.14', '9.15', '9.16', '9.17', '9.18', '9.19', '9.20', '9.21', '9.22', '9.23')
$launcherRoot = $PSScriptRoot

foreach ($slice in $slices) {
    $launcher = Join-Path $launcherRoot "launch-phase9-$slice-e2e.ps1"
    if (-not (Test-Path $launcher)) {
        throw "Required script not found: $launcher"
    }

    Write-Host ""
    Write-Host "Starting Phase $slice..."

    $sliceLog = Join-Path $launcherRoot "_temp\launch-$slice.log"
    if (Test-Path $sliceLog) {
        Remove-Item -LiteralPath $sliceLog -Force
    }

    $job = Start-Job -ScriptBlock {
        param($scriptPath, $retries, $healthWait)
        & $scriptPath -MaxRetries $retries -HealthWaitSeconds $healthWait
    } -ArgumentList $launcher, $MaxRetries, $HealthWaitSeconds

    try {
        while ($true) {
            $state = $job.State
            if ($state -eq 'Completed' -or $state -eq 'Failed' -or $state -eq 'Stopped') {
                break
            }

            Write-Host "Phase $slice heartbeat at $(Get-Date -Format HH:mm:ss)..."
            Start-Sleep -Seconds 20
        }

        $jobOutput = Receive-Job -Job $job -Keep
        $jobOutput | Out-File -FilePath $sliceLog -Encoding utf8
        Write-Host "Phase $slice completed. Detailed log: $sliceLog"
        if ($job.State -ne 'Completed') {
            throw "Phase $slice failed with job state $($job.State)."
        }
    }
    finally {
        if ($job) {
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host ""
Write-Host "Phase 9.3 through 9.23 completed successfully."

Write-Host ""
Write-Host "Running final solution build gate..."
dotnet build
