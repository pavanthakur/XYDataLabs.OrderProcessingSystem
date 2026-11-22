$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot '../run-phase10-local-nfr-proof.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) { throw 'NFR runner must parse before operational-lane contract checks.' }
$source = Get-Content -LiteralPath $path -Raw
$dockerWrapper = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../run-phase10-docker-nfr-proof.ps1') -Raw
$functionsAcceptance = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../tools/Phase10.NfrProbe/FunctionsAcceptance.cs') -Raw

if ($dockerWrapper -notmatch '(?s)SelectedCategories\s*=\s*@\(\$Categories\).*?&\s+\$localProofScript\s+@localProofArguments') {
    throw 'Docker NFR wrapper must preserve selected category arrays through PowerShell parameter binding.'
}
if ($dockerWrapper -notmatch '\[switch\]\$OperationalOnly' -or
    $dockerWrapper -notmatch 'OperationalOnly\s*=\s*\$OperationalOnly' -or
    $dockerWrapper -notmatch '\$OperationalOnly\s+-and\s+\$Categories\.Count\s*-gt\s*0' -or
    $dockerWrapper -notmatch '\$OperationalOnly\s+-and\s+\$SkipOperationalChecks') {
    throw 'Docker NFR wrapper must expose and safely propagate the operational-only profile.'
}
if ($dockerWrapper -notmatch '\$Categories\s*=\s*@\(\$Categories\s*\|\s*ForEach-Object\s*\{\s*\(\[string\]\$_\s*-split' -or
    $dockerWrapper -notmatch '\$unsupportedCategories\s*=') {
    throw 'Docker NFR wrapper must accept comma-separated CLI category values and reject unsupported categories before creating artifacts.'
}
if ($dockerWrapper -notmatch "'functional',\s*'performance',\s*'tenant',\s*'payments',\s*'security'") {
    throw 'Docker NFR wrapper must expose the implemented no-charge performance category for image-bound acceptance.'
}
if ($dockerWrapper -notmatch '(?s)status\s+-eq\s+''incomplete''.*?after-image inventory' -or
    $dockerWrapper -notmatch 'status\s*=\s*\$finalStatus') {
    throw 'Docker NFR wrapper must preserve finalized incomplete runs and capture their after-image inventory without reporting PASS.'
}

$parameter = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'OperationalOnly' }
if ($null -eq $parameter -or $parameter.StaticType -ne [switch]) { throw 'The operational-only selector must be an explicit switch.' }
if ($source -notmatch '\$OperationalOnly\s+-and\s+\$UseCleanReset' -or
    $source -notmatch '\$OperationalOnly\s+-and\s+\$SkipOperationalChecks') {
    throw 'Operational-only mode must reject reset and skipped operational checks.'
}
if ($source -notmatch 'if\s*\(\s*-not\s+\$OperationalOnly\s*\)\s*\{(?s).*?playwright-matrix') {
    throw 'Payment matrix execution must remain inside the non-operational-only branch.'
}
$targetedInitMatch = [regex]::Match($source, '(?m)^if\s*\(\s*\$targetedNoChargeRun\s*\)\s*\{')
$targetedInit = if ($targetedInitMatch.Success) { $targetedInitMatch.Index } else { -1 }
foreach ($functionName in @('Write-NfrSummary', 'Write-CategorySummaryFile')) {
    $definition = $source.IndexOf("function $functionName", [StringComparison]::Ordinal)
    if ($definition -lt 0 -or $targetedInit -lt 0 -or $definition -gt $targetedInit) {
        throw "$functionName must be defined before targeted-mode initialization."
    }
}
$paymentSelector = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'SkipDynamicPaymentMatrix' }
if ($null -eq $paymentSelector -or $paymentSelector.StaticType -ne [switch] -or
    $source -notmatch '(?s)if\s*\(\s*\$SkipDynamicPaymentMatrix\s*\).*?status\s*=\s*''partial''.*?playwright-matrix') {
    throw 'Skipping the dynamic payment matrix must be explicit, never invoke Playwright, and remain partial.'
}
$categoriesParameter = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'SelectedCategories' }
if ($null -eq $categoriesParameter -or $source -notmatch "Test-Phase10NfrCategorySelected -Name 'functional'" -or
    $source -notmatch "Test-Phase10NfrCategorySelected -Name 'tenant'" -or
    $source -notmatch "Test-Phase10NfrCategorySelected -Name 'payments'" -or
    $source -notmatch "Test-Phase10NfrCategorySelected -Name 'security'" -or
    $source -notmatch 'integrationStatus = ''passed''' -or
    $source -notmatch 'dynamicMatrixStatus = ''not-run''') {
    throw 'Targeted NFR mode must independently select the no-charge categories and separate payment integration from the browser matrix.'
}
$functionalFilterAssignment = [regex]::Match($source, "(?m)^\s*\`$functionalFilter\s*=\s*'([^']*)'")
if (-not $functionalFilterAssignment.Success) { throw 'The local NFR functional test filter is missing or is not a static literal.' }
$functionalFilterValue = $functionalFilterAssignment.Groups[1].Value
$replayFilters = @($functionalFilterValue -split '\|' | Where-Object { $_ -match 'FullyQualifiedName~Replay' })
if ($replayFilters.Count -ne 1 -or $replayFilters[0] -notmatch 'FullyQualifiedName!~AzureReplayDrillAcceptanceTests') {
    throw 'The local functional NFR filter must exclude the opt-in Azure replay drill while retaining the global skipped-test policy.'
}
if ($source -notmatch '(?s)if\s*\(\s*\$operationalPassed\s+-and\s+\$OperationalOnly\s*\).*?--message-count 100') {
    throw 'Operational-only lane must run an explicit 100-message durable burst.'
}
if ($source -notmatch '(?s)Invoke-ConsumerOutageBacklogDrill.*?-MessageCount\s+\$\(if\s*\(\$OperationalOnly\)\s*\{\s*100') {
    throw 'Operational-only lane must run a bounded 100-message outage backlog drill.'
}
if ($source -notmatch "status = 'not-run'" -or
    $source -notmatch 'execution = ''not-selected''' -or
    $source -notmatch 'Not run because targeted no-charge category selection excludes Docker operational mutations and rollback' -or
    $source -notmatch 'selection = \[ordered\]@\{' -or
    $source -notmatch 'carriedForwardEvidence = @\(\)') {
    throw 'Unselected categories must be reported explicitly as not-run and must not be presented as passed.'
}
if ($source -notmatch '\$skipOperationalExecution\s*=\s*\$SkipOperationalChecks\s+-or\s+\$targetedNoChargeRun' -or
    $source -notmatch 'if\s*\(\s*\$skipOperationalExecution\s*\)') {
    throw 'Targeted no-charge category selection must automatically bypass every Docker operational/recovery mutation.'
}
if ($source -notmatch 'Get-Phase10RollbackPreflight' -or
    $source -notmatch 'Running Inventory image differs from the selected current image tag' -or
    $source -notmatch 'Running Inventory image was not restored to the exact pre-drill image ID') {
    throw 'Rollback must verify provenance, selected image identity and exact restoration.'
}
if ($functionsAcceptance -notmatch 'var\s+approvalSubmissionAttempts\s*=\s*0;\s*result\["approvalSubmissionAttempts"\]\s*=\s*approvalSubmissionAttempts;' -or
    $functionsAcceptance -notmatch 'approvalSubmissionAttempts\+\+;\s*result\["approvalSubmissionAttempts"\]\s*=\s*approvalSubmissionAttempts;\s*result\["approvalResubmitted"\]\s*=\s*approvalSubmissionAttempts\s*>\s*1;\s*result\["approvalStatus"\]') {
    throw 'Functions replay proof must record its approval attempt count and derive resubmission status from that count.'
}
if ([regex]::Matches($functionsAcceptance, 'RequestLocalReplayApprovalAsync\(options,quarantine,approvalPath\)').Count -ne 1) {
    throw 'Functions acceptance must submit the replay approval exactly once per run; retries require explicit reconciliation.'
}

Write-Host 'PASS operational-only mode is payment-free, reset-free, reports unselected categories as not-run, and verifies image rollback provenance/restoration.'
