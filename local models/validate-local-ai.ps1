param(
    [switch]$RunRepoValidation
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $root

Write-Host 'Local models validation'
Write-Host "Local models root: $PSScriptRoot"

$requiredPaths = @(
    'README.md',
    'metadata.json',
    'ollama/README.md',
    'ollama/ollama_models.json',
    'ollama/model-routing.json',
    'ai-guidelines/README.md',
    'ai-guidelines/architect-profile.md',
    'ai-guidelines/developer-profile.md',
    'ai-guidelines/local-ai-performance-tuning.md',
    'ai-guidelines/phase-execution-model.md',
    'prompt-runs/README.md',
    'prompt-runs/run-record-template.md',
    'zoocode/phase9/README.md',
    'zoocode/phase9/00-phase9-zoo-code-runner.md'
)

$missing = @()
foreach ($relativePath in $requiredPaths) {
    $path = Join-Path $PSScriptRoot $relativePath
    if (Test-Path $path) {
        Write-Host "OK: $relativePath"
    } else {
        Write-Host "MISSING: $relativePath"
        $missing += $relativePath
    }
}

if ($missing.Count -gt 0) {
    throw "Missing required local model files: $($missing -join ', ')"
}

try {
    $ollamaVersion = ollama --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Ollama available: $ollamaVersion"
    } else {
        Write-Host 'Ollama not available or daemon not running; skipping model availability check.'
    }
} catch {
    Write-Host 'Ollama command not found; skipping model availability check.'
}

if ($RunRepoValidation) {
    $validationScript = Join-Path $repoRoot 'scripts/validate-ai-customization.ps1'
    if (Test-Path $validationScript) {
        Write-Host 'Running repo AI customization validation...'
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $validationScript
    } else {
        Write-Host 'Repo AI customization validation script not found; skipping.'
    }
}

Write-Host 'Local models validation complete.'
