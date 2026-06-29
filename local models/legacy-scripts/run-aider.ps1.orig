param(
    [string]$Mode = 'fast'
)

Set-Location -Path (Split-Path -Parent $PSScriptRoot)\..

if (Test-Path .venv -PathType Container) {
    Write-Host "Using existing .venv"
} else {
    if (Get-Command python -ErrorAction SilentlyContinue) {
        Write-Host "Creating .venv via python -m venv .venv"
        python -m venv .venv
    } else {
        Write-Warning "Python not found in PATH; please create .venv manually or install Python."
    }
}

if (Test-Path .venv\Scripts\Activate.ps1) {
    & .venv\Scripts\Activate.ps1
}

if (Test-Path ..\.env.aider) {
    Get-Content ..\.env.aider | ForEach-Object {
        if ($_ -match "^\s*([A-Za-z0-9_]+)=(.*)$") { Set-Item -Path Env:$($matches[1]) -Value $matches[2] }
    }
}

switch ($Mode.ToLower()) {
    'fast' {
        Write-Host "Starting Aider (fast coding mode)"
        Write-Host "Model: $env:AIDER_MODEL"
        & aimer # typo-proof: call aider
    }
    'smart' {
        Write-Host "Starting Aider (smart architect mode)"
        & aider --model ollama/deepseek-coder-v2
    }
    'review' {
        Write-Host "Starting Aider (review mode)"
        & aider --model ollama/qwen2.5-coder:7b --read
    }
    default {
        Write-Host "Unknown mode '$Mode'. Use 'fast','smart', or 'review'."
    }
}
