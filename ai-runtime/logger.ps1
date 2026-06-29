param()
. "$PSScriptRoot\config.ps1"

function Write-PromptRunLog {
    param(
        [string]$PromptFile,
        [string]$Model,
        [int]$ExitCode,
        [string]$OutputFile,
        [string]$SessionId = ''
    )

    if (-not (Test-Path $PROMPT_RUNS_DIR)) { New-Item -ItemType Directory -Path $PROMPT_RUNS_DIR -Force | Out-Null }

    $out = ''
    if (Test-Path $OutputFile) { $out = Get-Content -Path $OutputFile -Raw -ErrorAction SilentlyContinue }
    $prompt = ''
    if (Test-Path $PromptFile) { $prompt = Get-Content -Path $PromptFile -Raw -ErrorAction SilentlyContinue }

    $timestamp = (Get-Date).ToString('o')
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

    $json = $entry | ConvertTo-Json -Compress
    Add-Content -Path $PROMPT_RUNS_FILE -Value $json
    Write-Host "Logged prompt run to $PROMPT_RUNS_FILE"
}
