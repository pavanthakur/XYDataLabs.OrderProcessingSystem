$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../phase10-nfr-selection.ps1')

$targeted = Resolve-Phase10NfrSelection -Categories @('functional', 'tenant', 'payments', 'security') -SkipDynamicPaymentMatrix
if ($targeted.mode -ne 'targeted-no-charge' -or
    ($targeted.selectedCategories -join ',') -ne 'functional,tenant,payments,security' -or
    'performance' -notin $targeted.notSelectedCategories -or
    $targeted.dynamicPaymentMatrix -ne 'not-run-explicit') {
    throw 'Targeted no-charge category selection did not resolve as expected.'
}

$default = Resolve-Phase10NfrSelection
if ($default.mode -ne 'full' -or $default.selectedCategories.Count -ne 7) {
    throw 'Default NFR behavior must retain the full seven-category suite.'
}

$performance = Resolve-Phase10NfrSelection -Categories @('performance')
if ($performance.mode -ne 'targeted-no-charge' -or
    ($performance.selectedCategories -join ',') -ne 'performance' -or
    'payments' -notin $performance.notSelectedCategories) {
    throw 'Performance must be independently selectable without enabling payment transactions.'
}

$operational = Resolve-Phase10NfrSelection -OperationalOnly
if ($operational.mode -ne 'operational-only' -or
    ($operational.selectedCategories -join ',') -ne 'operational,recovery') {
    throw 'Legacy operational-only selection must remain unchanged.'
}

foreach ($case in @(
    @{ Name = 'payments without dynamic-matrix opt-out'; Invoke = { Resolve-Phase10NfrSelection -Categories @('payments') } },
    @{ Name = 'runtime-mutating categories in targeted mode'; Invoke = { Resolve-Phase10NfrSelection -Categories @('operational') } },
    @{ Name = 'operational-only combined with targeted selection'; Invoke = { Resolve-Phase10NfrSelection -Categories @('tenant') -OperationalOnly } }
)) {
    $threw = $false
    try { & $case.Invoke } catch { $threw = $true }
    if (-not $threw) { throw "Unsafe NFR selection was accepted: $($case.Name)." }
}

Write-Host 'PASS targeted NFR selection is explicit, payment-matrix-safe, and preserves legacy modes.'
