#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../..'),
    [string]$ArtifactDirectory
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath($RepositoryRoot)
if (-not $ArtifactDirectory) {
    $ArtifactDirectory = Join-Path $repo ('TestResults/AIGovernance/exit-regression-' + [guid]::NewGuid().ToString('N'))
}
$artifact = [IO.Path]::GetFullPath($ArtifactDirectory)
$prefix = [IO.Path]::GetFullPath((Join-Path $repo 'TestResults')).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
if (-not $artifact.StartsWith($prefix, $comparison)) { throw 'Exit-test artifacts must stay under repository TestResults.' }
if ((Test-Path -LiteralPath $artifact) -and @(Get-ChildItem -LiteralPath $artifact -Force).Count) {
    throw 'Choose a fresh artifact directory; prior exit-test evidence must not be overwritten.'
}
[void][IO.Directory]::CreateDirectory((Join-Path $artifact 'logs'))
$utf8 = [Text.UTF8Encoding]::new($false)
$runner = Join-Path $repo 'scripts/tests/test-ai-customization.ps1'
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($runner, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Governance runner syntax is invalid.' }
$statements = @($ast.EndBlock.Statements)
$tryIndex = -1
for ($i = 0; $i -lt $statements.Count; $i++) {
    if ($statements[$i] -is [Management.Automation.Language.TryStatementAst]) { $tryIndex = $i }
}
if ($tryIndex -lt 0 -or $tryIndex -eq $statements.Count - 1) { throw 'Cannot locate runner finalization and terminal exit statements.' }
$tryNode = $statements[$tryIndex]
$finallyCode = $tryNode.Finally.Statements.Extent.Text -join [Environment]::NewLine
$catchCode = $tryNode.CatchClauses[0].Body.Statements.Extent.Text -join [Environment]::NewLine
$terminalCode = $statements[($tryIndex + 1)..($statements.Count - 1)].Extent.Text -join [Environment]::NewLine
$countNode = $ast.Find({ param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$expectedCount' }, $true)
$expectedCount = [int]::Parse($countNode.Right.Extent.Text)
$results = [Collections.Generic.List[object]]::new()

# Execute real aggregation/exit code, not a rewritten equivalent. Only the case
# results are synthetic. These unit fixtures do not prove the 29 governance cases.
$cases = @(
    @{ name='complete-success'; status='passed'; exit=0; delta=0; result='passed'; error=$false; abort=$false },
    @{ name='failed-case'; status='failed'; exit=1; delta=0; result='failed'; error=$false; abort=$false },
    @{ name='not-tested-case'; status='partial'; exit=1; delta=0; result='not-tested'; error=$false; abort=$false },
    @{ name='missing-result'; status='failed'; exit=1; delta=-1; result='passed'; error=$false; abort=$false },
    @{ name='extra-result'; status='failed'; exit=1; delta=1; result='passed'; error=$false; abort=$false },
    @{ name='recorded-error'; status='failed'; exit=1; delta=0; result='passed'; error=$true; abort=$false },
    @{ name='aborted-run'; status='failed'; exit=1; delta=0; result='passed'; error=$false; abort=$true }
)
foreach ($case in $cases) {
    foreach ($nativeExit in @(0, 1)) {
        $name = $case.name + '-native-' + $nativeExit
        $caseRoot = Join-Path $artifact ('fixtures/' + $name)
        [void][IO.Directory]::CreateDirectory((Join-Path $caseRoot 'unit-output'))
        $setup = @'
$ErrorActionPreference = 'Stop'
$artifact = Join-Path $PSScriptRoot 'unit-output'
$utf8 = [Text.UTF8Encoding]::new($false)
$results = [Collections.Generic.List[object]]::new()
$runError = $null
'@
        $setup += "`n`$expectedCount = $expectedCount`n"
        $setup += "for (`$i=0; `$i -lt $($expectedCount + $case.delta); `$i++) { `$results.Add([pscustomobject]@{name=('synthetic-' + `$i);status='passed'}) }`n"
        if ($case.result -ne 'passed') { $setup += "`$results[0].status = '$($case.result)'`n" }
        if ($case.error) { $setup += "`$runError = 'Synthetic recorded error'`n" }
        $setup += "& pwsh -NoProfile -Command 'exit $nativeExit'`n"
        $body = if ($case.abort) { "try { throw 'Synthetic runner abort' } catch {`n$catchCode`n} finally {`n$finallyCode`n}`n" } else { "$finallyCode`n" }
        $scriptPath = Join-Path $caseRoot 'exit-fixture.ps1'
        [IO.File]::WriteAllText($scriptPath, ($setup + $body + $terminalCode), $utf8)
        $escapedPath = $scriptPath.Replace("'", "''")
        # GitHub's built-in pwsh shell dot-sources the step and appends this check.
        $wrapper = ". '$escapedPath'; if (Test-Path -LiteralPath variable:\LASTEXITCODE) { exit `$LASTEXITCODE }"
        $output = (& pwsh -NoProfile -Command $wrapper 2>&1 | Out-String)
        $actualExit = $LASTEXITCODE
        $summaryPath = Join-Path $caseRoot 'unit-output/summary.json'
        $actualStatus = if (Test-Path -LiteralPath $summaryPath) { (Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json).status } else { 'missing' }
        $passed = $actualExit -eq $case.exit -and $actualStatus -eq $case.status
        [IO.File]::WriteAllText((Join-Path $artifact "logs/$name.log"), $output, $utf8)
        $results.Add([pscustomobject]@{name=$name;status=$(if($passed){'passed'}else{'failed'});expectedExit=$case.exit;actualExit=$actualExit;expectedSummary=$case.status;actualSummary=$actualStatus})
        Write-Output "$(if($passed){'PASSED'}else{'FAILED'}) $name (exit=$actualExit; summary=$actualStatus)"
    }
}
$failed = @($results | Where-Object status -eq 'failed').Count
$status = if ($failed -or $results.Count -ne 14) { 'failed' } else { 'passed' }
$packet = @{kind='runner-exit-unit-tests';syntheticResults=$true;governanceCaseCoverage=$false;status=$status;results=@($results)}
[IO.File]::WriteAllText((Join-Path $artifact 'summary.json'), ($packet | ConvertTo-Json -Depth 6), $utf8)
Write-Output "Runner exit-status unit tests: $status; artifacts=$artifact"
if ($status -ne 'passed') { exit 1 }
exit 0
