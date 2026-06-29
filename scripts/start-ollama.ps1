param(
    [int]$Port = 11434
)
Write-Host "Checking Ollama daemon on port $Port..."
try {
    $proc = & ollama status 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Ollama appears to be running."
        exit 0
    }
} catch {
    Write-Host "Ollama CLI not returning status; attempting to start daemon..."
}

Write-Host "Starting Ollama daemon (background)..."
Start-Process -FilePath ollama -ArgumentList "serve --port $Port" -WindowStyle Hidden
Start-Sleep -Seconds 2
Write-Host "Ollama serve launched; give it a few seconds to warm up."
