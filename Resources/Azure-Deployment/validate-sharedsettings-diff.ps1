<#!
.SYNOPSIS
    Validates configuration consistency across sharedsettings.*.json files.
.DESCRIPTION
    Compares keys between dev, staging, prod, uat sharedsettings files under Resources/Configuration.
    Reports missing keys, extra keys, and differing scalar values.
.PARAMETER BasePath
    Override path to configuration directory. Default resolves relative to script.
.EXAMPLE
    ./validate-sharedsettings-diff.ps1
.NOTES
    Only top-level keys are compared; nested objects produce flattened dotted paths.
!#>
[CmdletBinding()] param(
    [string]$BasePath
)
$ErrorActionPreference='Stop'
if (-not $BasePath) { $BasePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Configuration' }
if (!(Test-Path $BasePath)) { Write-Error "Configuration path not found: $BasePath" }

$files = @('sharedsettings.dev.json','sharedsettings.staging.json','sharedsettings.prod.json','sharedsettings.uat.json') | ForEach-Object { Join-Path $BasePath $_ }
$loaded = @{}
foreach ($f in $files) { 
    if (Test-Path $f){ 
        # ConvertFrom-Json -Depth only available in PS Core; omit for PS 5.1 compatibility
        $loaded[(Split-Path $f -Leaf)] = Get-Content $f -Raw | ConvertFrom-Json
    } 
}

function Expand-Object($obj, [string]$prefix='') {
    $result = @{}
    foreach ($p in $obj.PSObject.Properties) {
        $key = if ($prefix) { "$prefix.$($p.Name)" } else { $p.Name }
        if ($p.Value -is [System.Management.Automation.PSObject]) { $result += Expand-Object $p.Value $key }
        elseif ($p.Value -is [System.Collections.IEnumerable] -and -not ($p.Value -is [string])) { $result[$key] = ($p.Value | ConvertTo-Json -Compress) }
        else { $result[$key] = [string]$p.Value }
    }
    return $result
}

$expanded = @{}
foreach ($kv in $loaded.GetEnumerator()) { $expanded[$kv.Key] = Expand-Object $kv.Value }

$allKeys = $expanded.Values | ForEach-Object { $_.Keys } | Sort-Object -Unique

$issues = @()
foreach ($k in $allKeys) {
    $presentIn = @()
    $values = @{}
    foreach ($fileName in $expanded.Keys) {
        if ($expanded[$fileName].ContainsKey($k)) {
            $presentIn += $fileName
            $values[$fileName] = $expanded[$fileName][$k]
        }
    }
    if ($presentIn.Count -ne $expanded.Count) {
        $missing = ($expanded.Keys | Where-Object { $_ -notin $presentIn })
        $issues += [PSCustomObject]@{ Type='Missing'; Key=$k; Present=$presentIn -join ','; Missing=$missing -join ','; Detail='' }
    } else {
        $distinct = ($values.Values | Select-Object -Unique)
        if ($distinct.Count -gt 1) {
            $issues += [PSCustomObject]@{ Type='Diff'; Key=$k; Present=''; Missing=''; Detail=(($values.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '; ') }
        }
    }
}

if ($issues.Count -eq 0) { Write-Host "All sharedsettings files aligned (top-level & nested keys)." -ForegroundColor Green; exit 0 }
Write-Host "Discrepancies detected:" -ForegroundColor Yellow
$issues | Format-Table Type,Key,Present,Missing,Detail -AutoSize

$missingCount = ($issues | Where-Object { $_.Type -eq 'Missing' }).Count
$diffCount = ($issues | Where-Object { $_.Type -eq 'Diff' }).Count
Write-Host "Summary: MissingKeyGroups=$missingCount ValueDiffGroups=$diffCount" -ForegroundColor White
if ($missingCount -gt 0 -or $diffCount -gt 0) { exit 2 } else { exit 0 }
