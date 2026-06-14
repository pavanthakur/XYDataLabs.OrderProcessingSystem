<#
Bootstrap Aider Python virtual environment and install aider package if pip is available.
#>
 Set-Location -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Error "Python not found in PATH. Install Python 3.8+ and retry."
    exit 1
}

if (-not (Test-Path .venv)) {
    python -m venv .venv
}

if (Test-Path .venv\Scripts\Activate.ps1) {
    & .venv\Scripts\Activate.ps1
}

if (Get-Command pip -ErrorAction SilentlyContinue) {
    pip install --upgrade pip
    pip install aider
    Write-Host "Installed aider into .venv"
} else {
    Write-Warning "pip not found in virtualenv. Activate .venv and install 'aider' manually."
}
