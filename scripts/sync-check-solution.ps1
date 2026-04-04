#Requires -Version 7.0
<#
.SYNOPSIS
    Checks that maintained files in tracked solution-item surfaces stay in sync with the VS solution file.

.DESCRIPTION
    Compares files on disk in:
      - docs/architecture/decisions/
      - .github/workflows/
      - scripts/
      - Resources/Azure-Deployment/
            - docs/internal/
            - Documentation/05-Self-Learning/Azure-Curriculum/
            - infra/
            - infra/parameters/
            - infra/modules/
            - bicep/
            - bicep/parameters/
    against entries in XYDataLabs.OrderProcessingSystem.sln.
        Exits with code 1 if any maintained file is missing from the solution or if the
        solution still contains stale entries under those tracked surfaces; exits 0 if clean.

.EXAMPLE
    .\scripts\sync-check-solution.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$slnPath  = Join-Path $repoRoot 'XYDataLabs.OrderProcessingSystem.sln'

if (-not (Test-Path $slnPath)) {
    Write-Error "Solution file not found: $slnPath"
    exit 1
}

$slnContent = Get-Content $slnPath -Raw

# Directories to check — relative to repo root, using backslash to match .sln entries.
# These are intentionally non-recursive maintained surfaces; archive subfolders are not
# treated as required registrations, but stale entries underneath these prefixes are flagged.
$trackedDirs = @(
    'docs\architecture\decisions'
    '.github\workflows'
    'scripts'
    'Resources\Azure-Deployment'
    'docs\internal'
    'Documentation\05-Self-Learning\Azure-Curriculum'
    'infra'
    'infra\parameters'
    'infra\modules'
    'bicep'
    'bicep\parameters'
)

# File extensions to ignore — generated outputs, not source files
$excludeExtensions = @('.log', '.tmp', '.bak')

$missing = [System.Collections.Generic.List[string]]::new()
$stale = [System.Collections.Generic.List[string]]::new()

foreach ($relDir in $trackedDirs) {
    $absDir = Join-Path $repoRoot $relDir
    if (-not (Test-Path $absDir)) { continue }

    $files = Get-ChildItem -Path $absDir -File |
             Where-Object { $excludeExtensions -notcontains $_.Extension.ToLower() } |
             Select-Object -ExpandProperty Name
    foreach ($file in $files) {
        $slnEntry = "$relDir\$file"
        if ($slnContent -notmatch [regex]::Escape($slnEntry)) {
            $missing.Add($slnEntry)
        }
    }

    $prefixPattern = '(?m)^\s*(' + [regex]::Escape($relDir) + '\\[^=\r\n]+?)\s*='
    $trackedSlnEntries = [regex]::Matches($slnContent, $prefixPattern) |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object -Unique

    foreach ($entry in $trackedSlnEntries) {
        $entryPath = Join-Path $repoRoot $entry
        if (-not (Test-Path $entryPath)) {
            $stale.Add($entry)
        }
    }
}

if ($missing.Count -gt 0 -or $stale.Count -gt 0) {
    Write-Host ''
    Write-Host 'Solution sync check FAILED — tracked solution-item surfaces are out of sync:' -ForegroundColor Red

    if ($missing.Count -gt 0) {
        Write-Host 'Files on disk not registered in .sln:' -ForegroundColor Yellow
        foreach ($item in ($missing | Sort-Object)) {
            Write-Host "  MISSING  $item" -ForegroundColor Yellow
        }
        Write-Host ''
    }

    if ($stale.Count -gt 0) {
        Write-Host 'Entries still present in .sln but missing on disk:' -ForegroundColor Yellow
        foreach ($item in ($stale | Sort-Object)) {
            Write-Host "  STALE    $item" -ForegroundColor Yellow
        }
        Write-Host ''
    }

    Write-Host 'Fix: add missing path = path entries and remove stale ones from the correct ProjectSection(SolutionItems) block in XYDataLabs.OrderProcessingSystem.sln.' -ForegroundColor Cyan
    exit 1
}

Write-Host 'Solution sync check PASSED — tracked solution-item surfaces are in sync with .sln.' -ForegroundColor Green
exit 0
