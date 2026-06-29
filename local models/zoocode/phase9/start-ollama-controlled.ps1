param(
    [string]$LogDir = (Join-Path $PSScriptRoot '_temp'),
    [string]$OllamaPath = 'ollama',
    [switch]$PassThru
)

$null = New-Item -ItemType Directory -Path $LogDir -Force
$logFile = Join-Path $LogDir 'ollama.log'
$stdoutFile = Join-Path $LogDir 'ollama.stdout.log'
$stderrFile = Join-Path $LogDir 'ollama.stderr.log'

function Write-Log {
    param([string]$Message)
    $timestamp = (Get-Date).ToString('s')
    Add-Content -LiteralPath $logFile -Value "[$timestamp] $Message"
}

Write-Log "Starting controlled Ollama session."

$existing = Get-Process -Name 'ollama' -ErrorAction SilentlyContinue
if ($existing) {
    Write-Log "Detected existing Ollama process ids: $(@($existing.Id) -join ', '). Reusing running server."
    Write-Host "Ollama already running. Log: $logFile"
    if ($PassThru) {
        return $existing
    }
    exit 0
}

if (-not (Get-Command $OllamaPath -ErrorAction SilentlyContinue)) {
    throw "Ollama executable not found on PATH: $OllamaPath"
}

$process = Start-Process -FilePath $OllamaPath -ArgumentList 'serve' -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
Write-Log "Started Ollama serve with pid=$($process.Id)."

Start-Sleep -Seconds 2
if ($process.HasExited) {
    Write-Log "Ollama exited immediately with code=$($process.ExitCode)."
    throw "Ollama exited immediately. Check $stderrFile and $stdoutFile."
}

Write-Host "Ollama started with pid $($process.Id)."
Write-Host "Logs:"
Write-Host "  $logFile"
Write-Host "  $stdoutFile"
Write-Host "  $stderrFile"

if ($PassThru) {
    return $process
}
