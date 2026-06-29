# Helper: check Ollama daemon and pull recommended models
Write-Host "Checking Ollama daemon..."
try {
    ollama list | Write-Host
} catch {
    Write-Error "ollama command not found or Ollama daemon not running. Start Ollama and try again."
    exit 1
}

Write-Host "Reading local model index..."
$json = Get-Content -Raw -Path "$PSScriptRoot\ollama_models.json" | ConvertFrom-Json
foreach ($m in $json.models) {
    Write-Host "Model: $($m.model) (recommended: $($m.recommended))"
}

Write-Host "To pull a recommended model, run:`ollama pull <model>`"