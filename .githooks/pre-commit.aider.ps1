<# Simple Aider-aware pre-commit hook
   This script is not automatically installed. Run `scripts\install-git-hooks.ps1` to copy hooks into .git\hooks.
   It checks for unstaged changes introduced by Aider (dirty commits guard) and prevents accidental commits.
#>
param()

Set-Location -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))

$status = git status --porcelain
if ($status -match '^\s*M') {
    Write-Host "Unstaged modifications present. Please review before committing."
    exit 1
}

exit 0
