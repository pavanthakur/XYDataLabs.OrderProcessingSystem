param(
    [ValidateSet('9.1', '9.2', '9.3', '9.4', '9.5', '9.6', '9.7', '9.8', '9.9', '9.10', '9.11', '9.12', '9.13', '9.14', '9.15', '9.16', '9.17')]
    [string]$Slice = '9.1',

    [ValidateRange(1,3)]
    [int]$MaxRetries = 3,

    [ValidateRange(5,60)]
    [int]$HealthWaitSeconds = 20
)

$startOllama = Join-Path $PSScriptRoot 'start-ollama-controlled.ps1'
$watchLogs = Join-Path $PSScriptRoot 'watch-phase9-logs.ps1'
$runE2E = Join-Path $PSScriptRoot 'run-phase9-e2e.ps1'

foreach ($path in @($startOllama, $watchLogs, $runE2E)) {
    if (-not (Test-Path $path)) {
        throw "Required script not found: $path"
    }
}

Write-Host "Starting controlled Ollama..."
& $startOllama
if ($LASTEXITCODE -ne 0) {
    throw "Ollama launch failed with exit code $LASTEXITCODE."
}

Write-Host "Waiting for Ollama readiness on http://127.0.0.1:11434/api/tags ..."
$healthOk = $false
for ($i = 1; $i -le $HealthWaitSeconds; $i++) {
    try {
        $response = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -Method Get -TimeoutSec 5
        if ($null -ne $response) {
            $healthOk = $true
            Write-Host "Ollama is ready after $i second(s)."
            break
        }
    }
    catch {
        Write-Host "Health check attempt $i of $HealthWaitSeconds failed. Retrying..."
        Start-Sleep -Seconds 1
    }
}

if (-not $healthOk) {
    throw "Ollama health check failed after $HealthWaitSeconds second(s). Verify ollama.log, ollama.stdout.log, and ollama.stderr.log in _temp."
}

Write-Host "Opening live log watcher..."
Write-Host "Watcher log: $(Join-Path $PSScriptRoot '_temp\phase9-e2e.log')"
Start-Process -FilePath 'powershell' -ArgumentList @(
    '-NoExit',
    '-ExecutionPolicy', 'Bypass',
    '-File', $watchLogs
) -WindowStyle Normal | Out-Null

Write-Host "Running Phase $Slice end-to-end..."
& $runE2E -Slice $Slice -MaxRetries $MaxRetries
$exitCode = $LASTEXITCODE

Write-Host ""
if ($exitCode -eq 0) {
    Write-Host "Phase $Slice launch completed successfully."
    Write-Host "Inspect:"
    Write-Host "  $(Join-Path $PSScriptRoot '_temp\ollama.log')"
    Write-Host "  $(Join-Path $PSScriptRoot '_temp\phase9-e2e.log')"
}
else {
    Write-Host "Phase $Slice launch failed with exit code $exitCode."
    Write-Host "Inspect:"
    Write-Host "  $(Join-Path $PSScriptRoot '_temp\ollama.log')"
    Write-Host "  $(Join-Path $PSScriptRoot '_temp\phase9-e2e.log')"
}

exit $exitCode
