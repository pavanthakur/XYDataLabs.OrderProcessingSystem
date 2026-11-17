$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot '../run-phase10-local-nfr-proof.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) { throw 'NFR runner must parse before operational-lane contract checks.' }
$source = Get-Content -LiteralPath $path -Raw

$parameter = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'OperationalOnly' }
if ($null -eq $parameter -or $parameter.StaticType -ne [switch]) { throw 'The operational-only selector must be an explicit switch.' }
if ($source -notmatch '\$OperationalOnly\s+-and\s+\$UseCleanReset' -or
    $source -notmatch '\$OperationalOnly\s+-and\s+\$SkipOperationalChecks') {
    throw 'Operational-only mode must reject reset and skipped operational checks.'
}
if ($source -notmatch 'if\s*\(\s*-not\s+\$OperationalOnly\s*\)\s*\{(?s).*?playwright-matrix') {
    throw 'Payment matrix execution must remain inside the non-operational-only branch.'
}
if ($source -notmatch '(?s)if\s*\(\s*\$operationalPassed\s+-and\s+\$OperationalOnly\s*\).*?--message-count 100') {
    throw 'Operational-only lane must run an explicit 100-message durable burst.'
}
if ($source -notmatch '(?s)Invoke-ConsumerOutageBacklogDrill.*?-MessageCount\s+\$\(if\s*\(\$OperationalOnly\)\s*\{\s*100') {
    throw 'Operational-only lane must run a bounded 100-message outage backlog drill.'
}
if ($source -notmatch "status = 'not-run'" -or
    $source -notmatch 'Not run because -OperationalOnly selected only local transport/recovery checks') {
    throw 'Skipped categories must be reported explicitly as not-run, never passed.'
}
if ($source -notmatch 'Get-Phase10RollbackPreflight' -or
    $source -notmatch 'Running Inventory image differs from the selected current image tag' -or
    $source -notmatch 'Running Inventory image was not restored to the exact pre-drill image ID') {
    throw 'Rollback must verify provenance, selected image identity and exact restoration.'
}

Write-Host 'PASS operational-only mode is payment-free, reset-free, reports unselected categories as not-run, and verifies image rollback provenance/restoration.'
