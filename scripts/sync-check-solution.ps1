#Requires -Version 7.0
<#
.SYNOPSIS
    Checks that every file in the four tracked directories is registered in the VS solution file.

.DESCRIPTION
    Compares files on disk in:
      - docs/architecture/decisions/
      - .github/workflows/
      - scripts/
      - Resources/Azure-Deployment/
    against entries in XYDataLabs.OrderProcessingSystem.sln.
    Exits with code 1 if any file is missing from the solution; exits 0 if clean.

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

# Directories to check — relative to repo root, using backslash to match .sln entries
$trackedDirs = @(
    'docs\architecture\decisions'
    '.github\workflows'
    'scripts'
    'Resources\Azure-Deployment'
)

# File extensions to ignore — generated outputs, not source files
$excludeExtensions = @('.log', '.tmp', '.bak')

$missing = [System.Collections.Generic.List[string]]::new()

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
}

if ($missing.Count -gt 0) {
    Write-Host ''
    Write-Host 'Solution sync check FAILED — files on disk not registered in .sln:' -ForegroundColor Red
    foreach ($item in ($missing | Sort-Object)) {
        Write-Host "  MISSING  $item" -ForegroundColor Yellow
    }
    Write-Host ''
    Write-Host 'Fix: add the missing path = path entries to the correct ProjectSection(SolutionItems) block in XYDataLabs.OrderProcessingSystem.sln.' -ForegroundColor Cyan
    exit 1
}

Write-Host 'Solution sync check PASSED — all tracked files are registered in .sln.' -ForegroundColor Green
exit 0
