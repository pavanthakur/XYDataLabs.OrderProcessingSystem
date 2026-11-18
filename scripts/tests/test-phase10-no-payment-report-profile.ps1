#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$paths = @(
    (Join-Path $root 'scripts/run-phase10-docker-dev-e2e-hook.ps1'),
    (Join-Path $root 'scripts/run-phase10-local-container-stack-end-to-end.ps1')
)
$asts = foreach ($path in $paths) {
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "PowerShell syntax invalid: $path" }
    $ast
}
$hook = Get-Content -LiteralPath $paths[0] -Raw
$runner = Get-Content -LiteralPath $paths[1] -Raw
foreach ($scriptAst in $asts) {
    $paymentParameter = $scriptAst.Find({
        param($node)
        $node -is [Management.Automation.Language.ParameterAst] -and $node.Name.VariablePath.UserPath -eq 'PaymentSuite'
    }, $true)
    if (-not $paymentParameter -or $paymentParameter.Extent.Text -notmatch "ValidateSet\([^\)]*'none'") {
        throw 'The no-payment profile must be an explicit accepted runner mode.'
    }
}
if ($runner -notmatch 'if\s*\(\s*\$PaymentSuite\s*-eq\s*''none''\s*\)[\s\S]*?status=''not-run''[\s\S]*?No-payment reporting mode explicitly excludes provider transactions' -or
    $runner -notmatch 'if\s*\(\s*\$PaymentSuite\s*-eq\s*''none''\s*\)\s*\{\s*\$runPartial\s*=\s*\$true') {
    throw 'No-payment mode must record payment suites as not-run and force a partial—not PASS—result.'
}
if ($runner -match 'if\s*\(\s*\$PaymentSuite\s*-in\s*@\(''none''.*?run-local-payment-tests' -or
    $runner -match 'if\s*\(\s*\$PaymentSuite\s*-in\s*@\(''none''.*?run-phase10-sandbox-gates') {
    throw 'No-payment mode must not invoke deterministic or provider payment runners.'
}
if ($hook -notmatch '\$PaymentSuite\s*-eq\s*''none''[\s\S]*?\$childSummary\.status\s*-eq\s*''partial''[\s\S]*?\$childSummary\.paymentSuite\s*-eq\s*''none''[\s\S]*?status\s*-eq\s*''failed''') {
    throw 'Outer orchestration may accept only a structured, failure-free no-payment partial.'
}
if ($hook -notmatch '\$coverage\.runId\s*-cne\s*\$Summary\.runId[\s\S]*?\$coverage\.provisional\s*-ne\s*\$true[\s\S]*?\$coverage\.provisional\s*=\s*\$false[\s\S]*?Get-FileHash') {
    throw 'Coverage must be identity-checked, finalized, and then included in completion hashes.'
}
Write-Host 'PASS no-payment runner mode is explicit, transaction-free, partial-only, and coverage-finalized.'
