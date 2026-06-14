Write-Host "Validating prompt files..."
$promptFiles = Get-ChildItem -Path .github\prompts -Recurse -Include *.md -File
if (-not $promptFiles) { Write-Error "No prompt files found"; exit 1 }
$fail = $false
foreach ($f in $promptFiles) {
    Write-Host "Checking $($f.FullName)"
    $content = Get-Content -Path $f.FullName -Raw
    if ($content.Trim().Length -lt 20) { Write-Error "Prompt $($f.Name) seems too short"; $fail = $true }
    if ($content -match "\b(password|secret|api_key|token)\b") { Write-Error "Prompt $($f.Name) contains potential secret patterns"; $fail = $true }
}
if ($fail) { exit 1 } else { Write-Host "Prompt validation passed"; exit 0 }
