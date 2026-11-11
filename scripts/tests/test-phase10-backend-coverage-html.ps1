#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Domain', 'Application', 'API', 'Gateway', 'Architecture')]
    [ValidateNotNullOrEmpty()]
    [string[]]$Project = @('Domain')
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runnerPath = Join-Path $root 'scripts\run-phase10-foundation-tests.ps1'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($runnerPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Foundation runner syntax is invalid.' }
$generator = $ast.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Write-BackendCoverageHtml'
}, $true)
if (-not $generator) { throw 'Backend coverage HTML function is missing.' }
. ([scriptblock]::Create($generator.Extent.Text))
function Protect-Phase10Log { process { $_ } }
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('phase10-backend-html-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
Push-Location $root
try {
    foreach ($name in $Project) {
        $projectFile = "tests\XYDataLabs.OrderProcessingSystem.$name.Tests\XYDataLabs.OrderProcessingSystem.$name.Tests.csproj"
        $projectRoot = Join-Path $testRoot $name
        $results = Join-Path $projectRoot 'results'
        & dotnet test $projectFile --no-build --no-restore --blame-hang-timeout 90s --blame-hang-dump-type none `
            --settings 'scripts\phase10-foundation-coverage.runsettings' --collect 'XPlat Code Coverage' `
            --results-directory $results --logger 'console;verbosity=minimal'
        if ($LASTEXITCODE -ne 0) { throw "Isolated $name coverage collection failed." }
        $coverageFiles = @(Get-ChildItem -LiteralPath $results -Filter 'coverage.cobertura.xml' -Recurse -File)
        if ($coverageFiles.Count -ne 1) { throw "Expected exactly one Coverlet output for $name." }
        $coveragePath = $coverageFiles[0].FullName
        $target = Join-Path $projectRoot 'html'
        $log = Join-Path $projectRoot 'reportgenerator.log'
        Write-BackendCoverageHtml -CoveragePath $coveragePath -TargetDirectory $target -LogPath $log
        $html = Get-Content -LiteralPath (Join-Path $target 'index.html') -Raw
        if ($html -notmatch 'XYDataLabs\.OrderProcessingSystem\.' -or
            $html -notmatch 'Line coverage' -or $html -notmatch 'Branch coverage') {
            throw "Generated HTML does not contain expected $name line and branch coverage."
        }
        [xml]$rawCoverage = Get-Content -LiteralPath $coveragePath -Raw
        $branchCovered = 0L
        $branchTotal = 0L
        foreach ($line in $rawCoverage.SelectNodes('/coverage/packages/package/classes/class/lines/line[@branch="True"]')) {
            $condition = [regex]::Match($line.GetAttribute('condition-coverage'), '\((\d+)/(\d+)\)$')
            if (-not $condition.Success) { throw "$name has invalid line-attached branch counts." }
            $branchCovered += [long]$condition.Groups[1].Value
            $branchTotal += [long]$condition.Groups[2].Value
        }
        foreach ($metric in @(
            @('Covered lines', $rawCoverage.coverage.'lines-covered'), @('Coverable lines', $rawCoverage.coverage.'lines-valid'),
            @('Covered branches', $branchCovered), @('Total branches', $branchTotal)
        )) {
            $pattern = '<th>' + [regex]::Escape($metric[0]) + ':</th>\s*<td\b[^>]*>\s*(\d+)\s*</td>'
            $match = [regex]::Match($html, $pattern)
            if (-not $match.Success -or [long]$match.Groups[1].Value -ne [long]$metric[1]) {
                throw "$name generated HTML does not match $($metric[0]) counts."
            }
        }
        Write-Host "PASS real $name coverage HTML"
    }
    $refused = $false
    try { Write-BackendCoverageHtml -CoveragePath $coveragePath -TargetDirectory $target -LogPath $log } catch { $refused = $true }
    if (-not $refused -or (Get-Content -LiteralPath (Join-Path $target 'index.html') -Raw) -ne $html) {
        throw 'Existing HTML was not preserved.'
    }
    Write-Host 'PASS existing HTML is preserved'
    $invalid = Join-Path $testRoot 'invalid.xml'
    foreach ($inputXml in @(
        '<invalid',
        '<coverage lines-covered="10" lines-valid="1" branches-covered="0" branches-valid="1"/>',
        '<coverage lines-covered="0" lines-valid="0" branches-covered="0" branches-valid="1"/>',
        '<coverage lines-covered="1" lines-valid="1" branches-covered="0" branches-valid="0"/>',
        '<!DOCTYPE coverage [<!ENTITY x "x">]><coverage lines-covered="1" lines-valid="1" branches-covered="1" branches-valid="1"/>'
    )) {
        Set-Content -LiteralPath $invalid -Value $inputXml
        $failed = $false
        try {
            Write-BackendCoverageHtml -CoveragePath $invalid -TargetDirectory (Join-Path $testRoot 'invalid-html') `
                -LogPath (Join-Path $testRoot 'invalid.log')
        } catch { $failed = $true }
        if (-not $failed -or (Test-Path -LiteralPath (Join-Path $testRoot 'invalid-html'))) {
            throw 'Invalid coverage was accepted or emitted HTML.'
        }
    }
    Write-Host 'PASS malformed, inconsistent, zero-valid and DTD coverage fail'
    function dotnet { $global:LASTEXITCODE = 1; 'simulated missing local tool' }
    $failed = $false
    try {
        Write-BackendCoverageHtml -CoveragePath $coveragePath -TargetDirectory (Join-Path $testRoot 'missing-tool') `
            -LogPath (Join-Path $testRoot 'missing-tool.log')
    } catch { $failed = $true }
    if (-not $failed) { throw 'Missing tool was accepted.' }
    Write-Host 'PASS missing tool fails'
    function dotnet { $global:LASTEXITCODE = 0; 'simulated success without output' }
    $failed = $false
    try {
        Write-BackendCoverageHtml -CoveragePath $coveragePath -TargetDirectory (Join-Path $testRoot 'no-output') `
            -LogPath (Join-Path $testRoot 'no-output.log')
    } catch { $failed = $true }
    if (-not $failed) { throw 'Missing report output was accepted.' }
    Write-Host 'PASS missing output fails'
    $subsetXml = Join-Path $testRoot 'subset.xml'
    Set-Content -LiteralPath $subsetXml -Value (
        '<coverage lines-covered="1" lines-valid="1" branches-covered="1" branches-valid="3">' +
        '<packages><package><classes><class><lines><line hits="1" branch="True" condition-coverage="50% (1/2)"/>' +
        '</lines></class></classes></package></packages></coverage>')
    function dotnet {
        $targetArg = @($args | Where-Object { $_ -like '-targetdir:*' })[0]
        $output = $targetArg.Substring('-targetdir:'.Length)
        [void][IO.Directory]::CreateDirectory($output)
        Set-Content -LiteralPath (Join-Path $output 'index.html') -Value (
            '<th>Covered lines:</th><td>1</td><th>Coverable lines:</th><td>1</td>' +
            '<th>Covered branches:</th><td>1</td><th>Total branches:</th><td>2</td>')
        $global:LASTEXITCODE = 0
    }
    $warnings = @()
    Write-BackendCoverageHtml -CoveragePath $subsetXml -TargetDirectory (Join-Path $testRoot 'subset') `
        -LogPath (Join-Path $testRoot 'subset.log') -WarningVariable warnings
    if ($warnings.Count -ne 1 -or $warnings[0].Message -notlike '*excludes branches*') {
        throw 'Line-attached subset was not reported explicitly.'
    }
    Write-Host 'PASS line-attached branch subset is reported explicitly'
    $validSubset = Get-Content -LiteralPath $subsetXml -Raw
    foreach ($invalidSubset in @(
        $validSubset.Replace('condition-coverage="50% (1/2)"', 'condition-coverage="invalid"'),
        $validSubset.Replace('condition-coverage="50% (1/2)"', 'condition-coverage="100% (2/4)"'),
        $validSubset.Replace('branch="True"', 'branch="unknown"'),
        $validSubset.Replace('hits="1"', 'hits="0"')
    )) {
        Set-Content -LiteralPath $invalid -Value $invalidSubset
        $failed = $false
        try {
            Write-BackendCoverageHtml -CoveragePath $invalid -TargetDirectory (Join-Path $testRoot 'invalid-subset') `
                -LogPath (Join-Path $testRoot 'invalid-subset.log')
        } catch { $failed = $true }
        if (-not $failed -or (Test-Path -LiteralPath (Join-Path $testRoot 'invalid-subset'))) {
            throw 'Invalid class-line coverage was accepted or emitted HTML.'
        }
    }
    Write-Host 'PASS invalid line-attached counts fail'
    function dotnet {
        $targetArg = @($args | Where-Object { $_ -like '-targetdir:*' })[0]
        $output = $targetArg.Substring('-targetdir:'.Length)
        [void][IO.Directory]::CreateDirectory($output)
        Set-Content -LiteralPath (Join-Path $output 'index.html') -Value (
            '<th>Covered lines:</th><td>0</td><th>Coverable lines:</th><td>1</td>' +
            '<th>Covered branches:</th><td>0</td><th>Total branches:</th><td>1</td>')
        $global:LASTEXITCODE = 0
    }
    $failed = $false
    try {
        Write-BackendCoverageHtml -CoveragePath $coveragePath -TargetDirectory (Join-Path $testRoot 'mismatched') `
            -LogPath (Join-Path $testRoot 'mismatched.log')
    } catch { $failed = $_.Exception.Message -like '*totals do not match*' }
    if (-not $failed) { throw 'Mismatched HTML totals were accepted.' }
    Write-Host 'PASS mismatched HTML totals fail'
} finally {
    Pop-Location
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
