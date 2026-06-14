param()
. "$PSScriptRoot\config.ps1"

function Get-AiderPath {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $venvAider = Join-Path -Path $repoRoot -ChildPath ".venv\Scripts\aider.exe"
    $venvPython = Join-Path -Path $repoRoot -ChildPath ".venv\Scripts\python.exe"
    return @{ aiderExe = $venvAider; pythonExe = $venvPython; repoRoot = $repoRoot }
}

function Invoke-OllamaFallback {
    param(
        [string]$PromptFile,
        [string]$Model = $DEFAULT_MODEL_DEVELOPER
    )
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    if (-not $PromptFile) { $PromptFile = (Join-Path $repoRoot '.github\prompts\phase-handoffs\phase-09-microservices-architecture.prompt.md') }
    Write-Host "Using Ollama CLI fallback: streaming prompt file $PromptFile to ollama run $Model"
    $prompt = Get-Content -Path $PromptFile -Raw
    $start = Get-Date
    # write temporary output to system temp with a GUID filename to avoid repo-root artifacts
    $tmpName = 'phase9_output_{0}.txt' -f ([guid]::NewGuid().ToString())
    $tmpOut = Join-Path $env:TEMP $tmpName
    $prompt | ollama run $Model > $tmpOut 2>&1
    $end = Get-Date
    $duration = ($end - $start).TotalMilliseconds
    $env:AI_DURATION_MS = [int]$duration
    return @{ exit = $LASTEXITCODE; out = $tmpOut }
}

function Invoke-Engine {
    param(
        [ValidateSet('developer','architect','automation','all')]
        [string]$Mode = 'developer',
        [string]$PromptFile = '',
        [string]$SessionId = ''
    )

    # decide model mapping
    $mapping = @{
        developer = $DEFAULT_MODEL_DEVELOPER
        architect = $DEFAULT_MODEL_ARCHITECT
        automation = $DEFAULT_MODEL_DEVELOPER
    }

    $paths = Get-AiderPath
    $repoRoot = $paths.repoRoot

    $selectedModel = $mapping[$Mode]

    # Try venv aider execution
    if (Test-Path $paths.aiderExe) {
        try {
            & $paths.aiderExe --model ollama/$selectedModel
            $exit = $LASTEXITCODE
            $out = ''
        } catch {
            Write-Warning "Aider executable failed: $_"
            $res = Invoke-OllamaFallback -PromptFile $PromptFile -Model $selectedModel
            $exit = $res.exit; $out = $res.out
        }
    } elseif (Test-Path $paths.pythonExe) {
        try {
            & $paths.pythonExe -m aider --model ollama/$selectedModel
            $exit = $LASTEXITCODE
            $out = ''
        } catch {
            Write-Warning "Aider module failed: $_"
            $res = Invoke-OllamaFallback -PromptFile $PromptFile -Model $selectedModel
            $exit = $res.exit; $out = $res.out
        }
    } else {
        $res = Invoke-OllamaFallback -PromptFile $PromptFile -Model $selectedModel
        $exit = $res.exit; $out = $res.out
    }

    # Do not write logs here; return metadata for caller to log
    return @{ exit = $exit; output = $out; model = $selectedModel; prompt = $PromptFile; session = $SessionId }
}
