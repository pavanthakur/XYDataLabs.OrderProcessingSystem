#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'scripts\phase10-dotnet-inventory.ps1')
$temp = Join-Path ([IO.Path]::GetTempPath()) ("phase10-dotnet-inventory-{0}" -f [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$names = @(
    'XYDataLabs.OrderProcessingSystem.Integration.Tests.ScenarioTests.FirstCase',
    'XYDataLabs.OrderProcessingSystem.Integration.Tests.ScenarioTests.ParameterizedCase(value: 7)'
)
function dotnet {
    if ($args -contains '--list-tests') {
        'The following Tests are available:'
        foreach ($name in $script:names) { "    $name" }
        $global:LASTEXITCODE = 0
        return
    }
    $global:LASTEXITCODE = 0
}
function New-TestTrx([string[]]$TestNames, [string]$Suffix = 'Passed') {
    $results = for ($index = 0; $index -lt $TestNames.Count; $index++) {
        $execution = '01234567-89ab-cdef-0123-{0:D12}' -f ($index + 1)
        '<UnitTestResult executionId="{0}" testName="{1}" outcome="{2}" />' -f $execution, [Security.SecurityElement]::Escape($TestNames[$index]), $Suffix
    }
    '<TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010"><Results>{0}</Results></TestRun>' -f ($results -join '')
}
try {
    $script:names = $names
    $discovered = Get-Phase10DiscoveredDotnetTests -TestProject 'fixture.csproj' -Filter 'Category=Integration'
    if ($discovered.Count -ne 2 -or $discovered[1] -ne $names[1]) { throw 'Discovery did not retain exact parameterized test identities.' }

    $assembly = Join-Path $temp 'Integration.Tests.dll'
    [IO.File]::WriteAllText($assembly, 'synthetic candidate assembly')
    $assemblyHash = (Get-FileHash -LiteralPath $assembly -Algorithm SHA256).Hash.ToLowerInvariant()
    $trx = Join-Path $temp 'passed.trx'
    [IO.File]::WriteAllText($trx, (New-TestTrx $names))
    $validPath = Join-Path $temp 'valid.json'
    Write-Phase10DiscoveredDotnetResults -SuiteId Integration -DiscoveredNames $discovered -AssemblyPath $assembly `
        -AssemblyHashBefore $assemblyHash -TrxPath $trx -RunnerExitCode 0 -StartedUtc '2026-11-10T00:00:00Z' `
        -FinishedUtc '2026-11-10T00:00:05Z' -OutputPath $validPath
    $valid = Get-Content -LiteralPath $validPath -Raw | ConvertFrom-Json
    if (-not $valid.complete -or $valid.expectedCount -ne 2 -or $valid.tests.Count -ne 2) { throw 'Valid discovery/TRX result did not reconcile.' }
    $serialized = Get-Content -LiteralPath $validPath -Raw
    if ($serialized.Contains($names[0]) -or $serialized.Contains('ParameterizedCase')) { throw 'Raw test names leaked into structured evidence.' }
    Write-Host 'PASS exact sanitized discovery and TRX reconciliation'

    $mismatch = Join-Path $temp 'mismatch.trx'
    [IO.File]::WriteAllText($mismatch, (New-TestTrx @($names[0], 'Unexpected.Test.Identity')))
    $mismatchPath = Join-Path $temp 'mismatch.json'
    $failed = $false
    try {
        Write-Phase10DiscoveredDotnetResults -SuiteId Integration -DiscoveredNames $discovered -AssemblyPath $assembly `
            -AssemblyHashBefore $assemblyHash -TrxPath $mismatch -RunnerExitCode 0 -StartedUtc '2026-11-10T00:00:00Z' `
            -FinishedUtc '2026-11-10T00:00:05Z' -OutputPath $mismatchPath
    } catch { $failed = $true }
    $mismatchEvidence = Get-Content -LiteralPath $mismatchPath -Raw | ConvertFrom-Json
    if (-not $failed -or $mismatchEvidence.complete -or $mismatchEvidence.missingCount -ne 1 -or $mismatchEvidence.unexpectedCount -ne 1) {
        throw 'Same-count identity mismatch was not preserved as incomplete evidence.'
    }
    Write-Host 'PASS same-count unexpected identity remains incomplete'

    $failedTrx = Join-Path $temp 'failed.trx'
    [IO.File]::WriteAllText($failedTrx, (New-TestTrx $names 'Failed'))
    $failedPath = Join-Path $temp 'failed.json'
    $failed = $false
    try {
        Write-Phase10DiscoveredDotnetResults -SuiteId Integration -DiscoveredNames $discovered -AssemblyPath $assembly `
            -AssemblyHashBefore $assemblyHash -TrxPath $failedTrx -RunnerExitCode 1 -StartedUtc '2026-11-10T00:00:00Z' `
            -FinishedUtc '2026-11-10T00:00:05Z' -OutputPath $failedPath
    } catch { $failed = $true }
    $failedEvidence = Get-Content -LiteralPath $failedPath -Raw | ConvertFrom-Json
    if (-not $failed -or $failedEvidence.complete -or $failedEvidence.runnerExitCode -ne 1) { throw 'Failed runner was reported as complete.' }
    Write-Host 'PASS failed runner status preserved'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
