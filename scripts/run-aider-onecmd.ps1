param(
    [ValidateSet('developer','architect','automation','all')]
    [string]$Mode = 'developer',
    [string]$PromptFile = ''
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
        # Delegate execution to ai-runtime run entrypoint
        & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\..\ai-runtime\run.ps1" -Mode $Mode -PromptFile $PromptFile
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
            $paths = Get-AiderPath
            $repoRoot = $paths.repoRoot
            $venvAider = $paths.aiderExe
            $venvPython = $paths.pythonExe
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
                Invoke-OllamaFallback -PromptFile $PromptFile -Model 'qwen2.5-coder:7b' -RepoRoot $repoRoot
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
