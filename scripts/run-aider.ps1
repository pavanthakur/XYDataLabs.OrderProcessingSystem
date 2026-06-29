param(
    [string]$Mode = 'developer'
)

# Delegator to the centralized ai-runtime entrypoint
Set-Location -Path (Split-Path -Parent $PSScriptRoot)\..

Write-Host "Delegating to ai-runtime/run.ps1 (Mode=$Mode)"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$PWD\ai-runtime\run.ps1" -Mode $Mode
