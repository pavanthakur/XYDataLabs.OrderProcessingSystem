function Resolve-Phase10NfrSelection {
    [CmdletBinding()]
    param(
        [string[]]$Categories = @(),
        [switch]$OperationalOnly,
        [switch]$SkipDynamicPaymentMatrix
    )

    $supportedTargeted = @('functional', 'tenant', 'payments', 'security')
    $allCategories = @('functional', 'performance', 'tenant', 'payments', 'operational', 'recovery', 'security')
    $explicit = $PSBoundParameters.ContainsKey('Categories') -and $Categories.Count -gt 0

    if ($OperationalOnly -and $explicit) {
        throw '-OperationalOnly cannot be combined with -Categories.'
    }
    if ($explicit) {
        $unknown = @($Categories | Where-Object { $_ -cnotin $supportedTargeted })
        if ($unknown.Count -gt 0) {
            throw "Targeted category selection supports only: $($supportedTargeted -join ', '). Unsupported: $($unknown -join ', ')."
        }
        $selected = @($Categories | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
        if ($selected -contains 'payments' -and -not $SkipDynamicPaymentMatrix) {
            throw 'Selecting payments for no-charge integration coverage requires -SkipDynamicPaymentMatrix; the browser matrix is a separate charge-capable action.'
        }
    }
    elseif ($OperationalOnly) {
        $selected = @('operational', 'recovery')
    }
    else {
        $selected = $allCategories
    }

    [ordered]@{
        mode = if ($explicit) { 'targeted-no-charge' } elseif ($OperationalOnly) { 'operational-only' } else { 'full' }
        requestedCategories = if ($explicit) { $selected } else { @() }
        selectedCategories = $selected
        notSelectedCategories = @($allCategories | Where-Object { $_ -notin $selected })
        dynamicPaymentMatrix = if ($SkipDynamicPaymentMatrix) { 'not-run-explicit' } elseif ($selected -contains 'payments') { 'selected' } else { 'not-selected' }
    }
}
