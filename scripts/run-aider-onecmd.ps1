param(
    [ValidateSet('developer','architect','automation','all')]
    [string]$Mode = 'developer'
)

Set-Location -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))

Write-Host "One-command Aider entry: mode=$Mode"

# Bootstrap .venv if needed
if (-not (Test-Path .venv)) {
    if (Get-Command python -ErrorAction SilentlyContinue) {
        Write-Host "Creating .venv..."
        python -m venv .venv
    } else {
        Write-Warning "Python not found; please install Python 3.8+ or ensure .venv exists.";
    }
}

if (Test-Path .venv\Scripts\Activate.ps1) { & .venv\Scripts\Activate.ps1 }

# Load .env.aider if present
if (Test-Path .env.aider) {
    Get-Content .env.aider | ForEach-Object {
        if ($_ -match "^\s*([A-Za-z0-9_]+)=(.*)$") { Set-Item -Path Env:$($matches[1]) -Value $matches[2] }
    }
}

function Ensure-Model([string]$tag) {
    $exists = (ollama list) -match [regex]::Escape($tag)
    if (-not $exists) {
        Write-Host "Pulling model $tag..."
        try {
            ollama pull $tag
        } catch {
            Write-Warning ("Failed to pull {0}: {1}" -f $tag, $_.Exception.Message)
        }
    } else { Write-Host "Model $tag already available." }
}

# Map required models for each role to installed equivalents
$mapping = @{
    developer = @('qwen2.5-coder:7b')
    architect  = @('qwen3-8b-64k:latest','deepseek-r1-14b-32k:latest')
    automation = @('qwen3:8b','qwen2.5-coder:7b')
}

if ($Mode -eq 'all') { $modes = $mapping.Keys } else { $modes = @($Mode) }

foreach ($m in $modes) {
    Write-Host "Ensuring models for role: $m"
    foreach ($tag in $mapping[$m]) { Ensure-Model $tag }
}

# Run the requested Aider invocation(s)
switch ($Mode) {
    'developer' {
        Write-Host "Running Aider (developer) with qwen2.5-coder:7b"
            $repoRoot = (Split-Path -Parent $PSScriptRoot)
            $venvAider = Join-Path -Path $repoRoot -ChildPath ".venv\Scripts\aider.exe"
            $venvPython = Join-Path -Path $repoRoot -ChildPath ".venv\Scripts\python.exe"
            if (Test-Path $venvAider) {
                try {
                    & $venvAider --model ollama/qwen2.5-coder:7b
                } catch {
                    Write-Warning "Aider executable failed; falling back to Ollama CLI. Details: $_"
                    $fallback = $true
                }
            } elseif (Test-Path $venvPython) {
                try {
                    & $venvPython -m aider --model ollama/qwen2.5-coder:7b
                } catch {
                    Write-Warning "Aider module failed; falling back to Ollama CLI. Details: $_"
                    $fallback = $true
                }
            } else {
                Write-Warning "No .venv aider or python found at $repoRoot\.venv\Scripts — falling back to Ollama CLI"
                $fallback = $true
            }

            if ($fallback) {
                # Diagnostic: list aider package files if present
                $aiderPkg = Join-Path -Path $repoRoot -ChildPath ".venv\Lib\site-packages\aider"
                if (Test-Path $aiderPkg) {
                    Write-Host "Aider package contents:"
                    Get-ChildItem -Path $aiderPkg | ForEach-Object { Write-Host $_.Name }
                }
                Write-Host "Using Ollama CLI fallback: streaming prompt to ollama run qwen2.5-coder:7b"
                $prompt = Get-Content -Path (Join-Path $repoRoot '.github\prompts\phase-handoffs\phase-09-microservices-architecture.prompt.md') -Raw
                $prompt | ollama run qwen2.5-coder:7b
            }
    }
    'architect' {
        Write-Host "Running Aider (architect) with deepseek fallback"
        & aider --model ollama/deepseek-coder-v2
    }
    'automation' {
        Write-Host "Running Aider (automation) with qwen3:8b"
        & aider --model ollama/qwen3:8b
    }
    'all' {
        Write-Host "Running all modes sequentially"
        & aider --model ollama/qwen2.5-coder:7b
        & aider --model ollama/deepseek-coder-v2
        & aider --model ollama/qwen3:8b
    }
}
