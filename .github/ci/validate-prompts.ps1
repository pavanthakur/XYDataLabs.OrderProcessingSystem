Write-Host "Validating prompt files..."
$promptFiles = Get-ChildItem -Path .github\prompts -Recurse -Include *.md -File
if (-not $promptFiles) { Write-Error "No prompt files found"; exit 1 }
$fail = $false
foreach ($f in $promptFiles) {
    Write-Host "Checking $($f.FullName)"
    $content = Get-Content -Path $f.FullName -Raw
    if ($content.Trim().Length -lt 20) { Write-Error "Prompt $($f.Name) seems too short"; $fail = $true }
    $secretPattern = '(?i)\b(?:password|api[_-]?key|secret|token)\b\s*[:=]\s*["'']?(?!<|{|\$|set-a-local|example|placeholder|retrieve-from-key-vault)[A-Za-z0-9+/=_-]{8,}'
    if ($content -match $secretPattern) { Write-Error "Prompt $($f.Name) contains potential secret patterns"; $fail = $true }
}
if ($fail) { exit 1 } else { Write-Host "Prompt validation passed"; exit 0 }
