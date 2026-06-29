param(
    [string]$PromptDir = ''
)

. "$PSScriptRoot\..\ai-runtime\config.ps1"

if (-not $PromptDir) { $PromptDir = Join-Path $PSScriptRoot '..\.github\prompts' }

Write-Host "Validating prompts in $PromptDir using ai_config"

$errors = @()

if (-not (Test-Path $PromptDir)) {
    Write-Error "Prompt directory not found: $PromptDir"
    exit 2
}

Get-ChildItem -Path $PromptDir -Recurse -File -Include *.md,*.prompt,*.jsonl | ForEach-Object {
    $file = $_.FullName
    try {
        $size = (Get-Item $file).Length
    } catch {
        $errors += "Unreadable file: $file"
        return
    }

    if ($size -gt 200KB) { $errors += "File too large (>200KB): $file ($size bytes)" }

    $content = Get-Content -Path $file -Raw -ErrorAction SilentlyContinue
    if (-not $content) { $errors += "Empty or unreadable content: $file"; return }

    # Detect binary-ish files
    if ($content -match "[\x00-\x08\x0B\x0C\x0E-\x1F]") { $errors += "Binary content detected: $file" }

    # Simple secrets pattern heuristics
    if ($content -match "(-----BEGIN PRIVATE KEY-----|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z\-_]{35}|ssh-rsa\s+[A-Za-z0-9+/=]{100,})") {
        $errors += "Potential secret pattern detected: $file"
    }

    # Ensure file is under ai-runtime or .github/prompts (allowed)
    $normalized = $file.Replace('\','/')
    if ($normalized -notmatch '/ai-runtime/' -and $normalized -notmatch '/.github/prompts/' -and $normalized -notmatch '/docs/') {
        $errors += "Prompt file outside allowed locations: $file"
    }
}

# Reject presence of runner scripts that bypass ai-runtime
$runnerCandidates = Get-ChildItem -Path "$PSScriptRoot\..\scripts" -File -Include *.ps1 | Where-Object { $_.Name -match 'run.*aider|run-.*ai|run-.*model' }
foreach ($r in $runnerCandidates) {
    # if file is executable and not a thin delegator to ai-runtime/run.ps1, fail
    $content = Get-Content -Path $r.FullName -Raw -ErrorAction SilentlyContinue
    if ($content -and $content -notmatch 'ai-runtime\\run.ps1') {
        $errors += "Found runner script outside ai-runtime that does not delegate: $($r.FullName)"
    }
}

if ($errors.Count -gt 0) {
    Write-Error "Prompt validation failed with $($errors.Count) issues:`n$(($errors -join "`n"))"
    exit 3
}

Write-Host "Prompt validation passed"
exit 0
