#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'phase10-appinsights-query.ps1')

$tests = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $tests.Add($Name)
}
function Assert-Throws([scriptblock]$Action, [string]$Name, [string]$ExpectedPattern) {
    try { & $Action; throw "Expected failure: $Name" }
    catch {
        if ($_.Exception.Message -notmatch $ExpectedPattern) { throw "FAIL: $Name (unexpected sanitized failure category)." }
        $tests.Add($Name)
    }
}

$valid = ConvertFrom-Phase10AppInsightsCliResult -Output @('{"tables":[{"columns":[{"name":"Result","type":"long"}],"rows":[[1]]}]}') -ExitCode 0 -Operation 'unit-valid'
$rows = @(ConvertTo-Phase10AppInsightsRows -Response $valid)
Assert-True ($rows.Count -eq 1 -and [string]$rows[0].Result -eq '1') 'valid single-row response is parsed'

$empty = ConvertFrom-Phase10AppInsightsCliResult -Output @('{"tables":[{"columns":[{"name":"Result","type":"long"}],"rows":[]}]}') -ExitCode 0 -Operation 'unit-empty'
Assert-True (@(ConvertTo-Phase10AppInsightsRows -Response $empty).Count -eq 0) 'valid empty result remains distinct from query failure'

$secretMarker = 'never-print-this-secret'
Assert-Throws {
    ConvertFrom-Phase10AppInsightsCliResult -Output @("ERROR: BadArgumentError $secretMarker") -ExitCode 2 -Operation 'unit-invalid'
} 'nonzero CLI exit fails closed' 'invalidQuery'
try {
    ConvertFrom-Phase10AppInsightsCliResult -Output @("ERROR: BadArgumentError $secretMarker") -ExitCode 2 -Operation 'unit-redaction' | Out-Null
}
catch { Assert-True (-not $_.Exception.Message.Contains($secretMarker)) 'CLI diagnostics do not expose raw output' }

Assert-Throws {
    ConvertFrom-Phase10AppInsightsCliResult -Output @('{}') -ExitCode 0 -Operation 'unit-missing'
} 'missing tables collection rejected' 'no tables collection'
Assert-Throws {
    ConvertFrom-Phase10AppInsightsCliResult -Output @('{"error":{"code":"BadArgumentError"},"tables":[]}') -ExitCode 0 -Operation 'unit-error-payload'
} 'error payload cannot masquerade as empty data' 'error payload'
Assert-Throws {
    $response = ConvertFrom-Phase10AppInsightsCliResult -Output @('{"tables":[{"columns":[{"name":"a"},{"name":"b"}],"rows":[[1]]}]}') -ExitCode 0 -Operation 'unit-column-count'
    ConvertTo-Phase10AppInsightsRows -Response $response | Out-Null
} 'malformed row shape rejected' 'column-count mismatch'

Write-Host "PASS: $($tests.Count) App Insights query contract tests"
$tests | ForEach-Object { Write-Host "  - $_" }
