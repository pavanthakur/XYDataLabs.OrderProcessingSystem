#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Validates ADR markdown files for required frontmatter and naming conventions.

.DESCRIPTION
    Checks each ADR-NNN-*.md file in docs/architecture/decisions/ for:
      - Filename matches ADR-NNN-kebab-case.md pattern
      - First heading is "# ADR-NNN: Title" (number matches filename)
      - "**Status:**" line is present
      - Status base word is one of: Accepted, Proposed, Draft, Deprecated, Superseded

    ADR-000-template.md is intentionally excluded — it is a template, not a decision record.

.PARAMETER AdrDirectory
    Path to the directory containing ADR files. Default: docs/architecture/decisions

.EXAMPLE
    pwsh scripts/validate-adr-frontmatter.ps1

.EXAMPLE
    pwsh scripts/validate-adr-frontmatter.ps1 -AdrDirectory "docs/architecture/decisions"
#>

param(
    [string]$AdrDirectory = "docs/architecture/decisions"
)

$ErrorActionPreference = 'Continue'

$ValidStatusValues = @('Accepted', 'Proposed', 'Draft', 'Deprecated', 'Superseded')
$failures = [System.Collections.Generic.List[string]]::new()

# Resolve to absolute path so the script works from any cwd
if (-not [System.IO.Path]::IsPathRooted($AdrDirectory)) {
    $AdrDirectory = Join-Path $PSScriptRoot ".." $AdrDirectory
}

if (-not (Test-Path $AdrDirectory)) {
    Write-Host "ERROR: ADR directory not found: $AdrDirectory" -ForegroundColor Red
    exit 1
}

# Collect ADR files; skip ADR-000 (template — intentionally non-conforming)
$adrFiles = Get-ChildItem -Path $AdrDirectory -Filter "ADR-*.md" |
    Where-Object { $_.Name -notmatch '^ADR-000-' } |
    Sort-Object Name

if ($adrFiles.Count -eq 0) {
    Write-Host "No ADR files found (excluding template) in '$AdrDirectory'" -ForegroundColor Yellow
    exit 0
}

Write-Host "Validating $($adrFiles.Count) ADR file(s) in '$AdrDirectory'..."
Write-Host ""

foreach ($file in $adrFiles) {
    $name     = $file.Name
    $lines    = Get-Content $file.FullName
    $hasError = $false

    # ── Check 1: Filename pattern ────────────────────────────────────────────
    if ($name -notmatch '^ADR-\d{3}-.+\.md$') {
        $failures.Add("[$name] Filename must match ADR-NNN-kebab-case.md")
        $hasError = $true
        continue  # Can't derive number for further checks
    }

    $fileNumber = [regex]::Match($name, '^ADR-(\d{3})').Groups[1].Value

    # ── Check 2: First H1 heading ────────────────────────────────────────────
    $h1Line = $lines | Where-Object { $_ -match '^\s*#\s' } | Select-Object -First 1
    if (-not $h1Line) {
        $failures.Add("[$name] Missing top-level heading (# ADR-${fileNumber}: Title)")
        $hasError = $true
    } elseif ($h1Line -notmatch "^#\s+ADR-$fileNumber\s*:") {
        $failures.Add("[$name] First heading must start '# ADR-${fileNumber}:', found: $h1Line")
        $hasError = $true
    }

    # ── Check 3: **Status:** line present ───────────────────────────────────
    $statusLine = $lines | Where-Object { $_ -match '\*\*Status:\*\*' } | Select-Object -First 1
    if (-not $statusLine) {
        $failures.Add("[$name] Missing '**Status:**' line")
        $hasError = $true
    } else {
        # ── Check 4: Base status word is a known value ─────────────────────
        # Format: **Status:** Accepted
        #         **Status:** Accepted — some qualifier
        #         **Status:** Superseded by ADR-009
        $statusMatch = [regex]::Match($statusLine, '\*\*Status:\*\*\s+(\w+)')
        if (-not $statusMatch.Success) {
            $failures.Add("[$name] Could not parse status from: $statusLine")
            $hasError = $true
        } else {
            $baseStatus = $statusMatch.Groups[1].Value
            if ($baseStatus -notin $ValidStatusValues) {
                $failures.Add("[$name] Invalid status '$baseStatus'. Allowed: $($ValidStatusValues -join ', ')")
                $hasError = $true
            }
        }
    }

    if (-not $hasError) {
        Write-Host "  PASS  $name" -ForegroundColor Green
    }
}

Write-Host ""

if ($failures.Count -eq 0) {
    Write-Host "ADR frontmatter validation passed — $($adrFiles.Count) file(s) checked." -ForegroundColor Green
    exit 0
} else {
    Write-Host "ADR frontmatter validation FAILED — $($failures.Count) violation(s):" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}
