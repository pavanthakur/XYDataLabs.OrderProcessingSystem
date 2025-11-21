<#
.SYNOPSIS
  Compare top-level keys across sharedsettings.*.json files to detect drift.
.DESCRIPTION
  Reads all Resources/Configuration/sharedsettings.*.json files, extracts the set of top-level
  keys and reports missing/extra keys per environment. Exit codes:
    0 = all key sets are consistent
    2 = drift detected (missing/extra keys)
    1 = runtime error (JSON parse error, missing files)
#>

try {
    $pattern = 'Resources/Configuration/sharedsettings.*.json'
    $files = Get-ChildItem -Path . -Recurse -Force | Where-Object { $_.FullName -like "*sharedsettings.*.json" }
    if (-not $files -or $files.Count -eq 0) {
        Write-Host "No sharedsettings files found under Resources/Configuration" -ForegroundColor Red
        exit 1
    }

    $keySets = @{}
    foreach ($f in $files) {
        try {
            $json = Get-Content $f.FullName -Raw | ConvertFrom-Json
        }
        catch {
            Write-Host "Failed to parse JSON: $($f.FullName)" -ForegroundColor Red
            exit 1
        }

        $keys = @()
        foreach ($prop in $json.PSObject.Properties) { $keys += $prop.Name }
        $keySets[$f.Name] = ,$keys
        Write-Host "Parsed $($f.Name): $($keys.Count) top-level keys" -ForegroundColor Green
    }

    # Compute union of all keys
    $union = @{}
    foreach ($ks in $keySets.Values) { foreach ($k in $ks) { $union[$k] = $true } }

    $driftFound = $false
    foreach ($file in $keySets.Keys) {
        $missing = @()
        foreach ($k in $union.Keys) {
            if (-not ($keySets[$file] -contains $k)) { $missing += $k }
        }
        if ($missing.Count -gt 0) {
            Write-Host "Drift in $file - missing keys: $($missing -join ', ')" -ForegroundColor Yellow
            $driftFound = $true
        }
    }

    if ($driftFound) { exit 2 }
    Write-Host "All sharedsettings top-level keys are consistent across environments" -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "Error running validate-sharedsettings-diff: $_" -ForegroundColor Red
    exit 1
}