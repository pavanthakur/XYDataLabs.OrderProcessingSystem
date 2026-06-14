param(
    [string]$PromptFile,
    [string]$Model,
    [int]$ExitCode,
    [string]$OutputFile,
    [string]$SessionId = ''
)
# Writes a JSONL entry into local models/prompt-runs/prompt_runs.jsonl
if (-not (Test-Path "local models\prompt-runs")) { New-Item -ItemType Directory -Path "local models\prompt-runs" -Force | Out-Null }
$out = Get-Content -Path $OutputFile -Raw -ErrorAction SilentlyContinue
$prompt = Get-Content -Path $PromptFile -Raw -ErrorAction SilentlyContinue
$timestamp = (Get-Date).ToString("o")
$promptHash = if ($prompt) { [System.BitConverter]::ToString((New-Object Security.Cryptography.SHA256Managed).ComputeHash([System.Text.Encoding]::UTF8.GetBytes($prompt))).Replace('-', '').ToLower() } else { '' }
$outputHash = if ($out) { [System.BitConverter]::ToString((New-Object Security.Cryptography.SHA256Managed).ComputeHash([System.Text.Encoding]::UTF8.GetBytes($out))).Replace('-', '').ToLower() } else { '' }
$durationMs = $env:AI_DURATION_MS
$entry = @{
    timestamp = $timestamp
    model = $Model
    prompt_file = $PromptFile
    prompt_hash = $promptHash
    output_hash = $outputHash
    duration_ms = $durationMs
    exit_code = $ExitCode
    session_id = $SessionId
}
$json = ($entry | ConvertTo-Json -Compress)
$logfile = "local models\prompt-runs\prompt_runs.jsonl"
Add-Content -Path $logfile -Value $json
Write-Host "Logged prompt run to $logfile"
