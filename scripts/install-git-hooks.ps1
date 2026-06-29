Set-Location -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
try {
    git config core.hooksPath .githooks
    Write-Host "Configured git to use .githooks as hooksPath"
} catch {
    Write-Warning "Could not set git core.hooksPath automatically. Please run: git config core.hooksPath .githooks"
}
# Copy hooks (idempotent)
Get-ChildItem -Path .githooks -File | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination .git\hooks\$($_.Name) -Force
}
Write-Host "Installed Aider pre-commit hook to .git/hooks and configured core.hooksPath"

$gitHooksDir = Join-Path -Path (Get-Location) -ChildPath ".git\hooks"
if (-not (Test-Path $gitHooksDir)) {
    Write-Warning ".git/hooks not found — are you in a git repo?"
    exit 1
}

$sourceHook = Join-Path $PSScriptRoot '..\.githooks\pre-commit.aider.ps1'
$targetHook = Join-Path $gitHooksDir 'pre-commit'

Copy-Item -Path $sourceHook -Destination $targetHook -Force
Write-Host "Installed Aider pre-commit hook to $targetHook"
