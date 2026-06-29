<#
Drift scanner v1
- Scans repo for risky patterns that bypass `ai-runtime/` execution contract.
- Exit codes: 0 = clean, 2 = warnings only, 3 = critical findings
#>
param(
    [string]$Root = "${PSScriptRoot}\.."
)

Write-Host "Running AI runtime drift scanner against $Root"

$patterns = [ordered]@{
    Critical = @(
        '(^|\\s)ollama\\s+run',
        '(^|\\s)python\\s+-m\\s+aider',
        '(^|\\s)aider\\b'
    )
    High = @(
        'run-.*\\.ps1',
        'Invoke-Expression',
        'Write-Host .*prompt_runs' # possible ad-hoc logging
    )
}

$cwd = Resolve-Path $Root
$ignoreGlobs = @('*/.git/*','*/.venv/*','*/local models/*','*.aider*','*/docs/*','*/Resources/*','repomix-output.xml','*/frontend/node_modules/*')
$files = Get-ChildItem -Path $cwd -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
    $full = $_.FullName -replace '\\','/'
    foreach ($g in $ignoreGlobs) { if ($full -like $g) { return $false } }
    return $true
}

$report = [System.Collections.ArrayList]::new()
$critical = @()
$high = @()

foreach ($f in $files) {
    $text = Get-Content -Path $f.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $text) { continue }

    # Only check CRITICAL patterns in likely executable/source files to avoid doc noise
    $exeExt = $f.Extension.ToLower()
    $executableExtensions = @('.ps1','.psm1','.psd1','.cmd','.bat','.sh','.py','.js')
    if ($executableExtensions -contains $exeExt) {
        foreach ($p in $patterns.Critical) {
            if ($text -match $p) {
                $critical += @{ file = $f.FullName; pattern = $p }
            }
        }
    }
    # Only run HIGH-level heuristics on PowerShell scripts to reduce false positives from docs
    if ($f.Extension -ieq '.ps1') {
        foreach ($p in $patterns.High) {
            if ($text -match $p) {
                # ignore legitimate ai-runtime files and the scanner itself
                if ($f.FullName -match '\\ai-runtime\\' -or $f.Name -ieq 'drift-scanner.ps1' -or $f.Name -ieq 'logger.ps1') { continue }
                $high += @{ file = $f.FullName; pattern = $p }
            }
        }
    }
}

if ($critical.Count -gt 0) {
    Write-Host "CRITICAL: Found raw model invocation patterns:" -ForegroundColor Red
    $critical | ForEach-Object { Write-Host " - $($_.file) matches $($_.pattern)" }
    exit 3
}

if ($high.Count -gt 0) {
    Write-Host "HIGH: Potential bypass scripts or patterns:" -ForegroundColor Yellow
    $high | ForEach-Object { Write-Host " - $($_.file) matches $($_.pattern)" }
    exit 2
}

Write-Host "Drift scanner: no issues found"
exit 0
