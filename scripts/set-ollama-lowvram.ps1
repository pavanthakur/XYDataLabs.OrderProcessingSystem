Write-Host "Setting Ollama low-VRAM environment variables (user scope)..."
setx OLLAMA_NUM_PARALLEL 1
setx OLLAMA_MAX_LOADED_MODELS 1
setx OLLAMA_FLASH_ATTENTION 1
Write-Host "Done. Please restart your terminal to apply changes."
