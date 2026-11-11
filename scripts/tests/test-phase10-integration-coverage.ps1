#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'scripts\phase10-integration-coverage.ps1')
function Protect-Phase10Log { process { $_ } }
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('phase10-integration-coverage-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$project = Join-Path $root 'tests\XYDataLabs.OrderProcessingSystem.Integration.Tests\XYDataLabs.OrderProcessingSystem.Integration.Tests.csproj'
$settings = Join-Path $root 'scripts\phase10-foundation-coverage.runsettings'
$dotnetPath = (Get-Command dotnet -CommandType Application).Source
function dotnet {
    & $dotnetPath @args --no-build --no-restore
    $global:LASTEXITCODE = $LASTEXITCODE
}
Push-Location $root
try {
    $code = Invoke-Phase10IntegrationCoverage -TestProject $project `
        -Filter 'FullyQualifiedName~Phase10ServiceHostTransportRegistrationTests' -ResultsDirectory $testRoot `
        -Index 1 -ConsoleVerbosity minimal -SettingsPath $settings
    if ($code -ne 0) { throw 'Isolated integration-project test failed.' }
    $trx = Join-Path $testRoot 'integration-1.trx'
    $coverageRoot = Join-Path $testRoot 'coverage-1'
    $coverage = @(Get-ChildItem -LiteralPath $coverageRoot -Directory | Where-Object {
        $_.Name -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    } | ForEach-Object { Get-Item -LiteralPath (Join-Path $_.FullName 'coverage.cobertura.xml') })
    if (-not (Test-Path -LiteralPath $trx -PathType Leaf) -or $coverage.Count -ne 1) {
        throw 'TRX or Coverlet output missing.'
    }
    [xml]$xml = Get-Content -LiteralPath $coverage[0].FullName -Raw
    if ([long]$xml.coverage.'lines-valid' -le 0 -or [long]$xml.coverage.'branches-valid' -le 0) {
        throw 'Real integration-project coverage has no valid lines or branches.'
    }
    Write-Host 'PASS isolated integration-project collector and TRX'
    $original = Get-FileHash -LiteralPath $trx
    $failed = $false
    try {
        Invoke-Phase10IntegrationCoverage -TestProject $project -Filter 'ignored' -ResultsDirectory $testRoot `
            -Index 1 -ConsoleVerbosity minimal -SettingsPath $settings
    } catch { $failed = $true }
    if (-not $failed -or (Get-FileHash -LiteralPath $trx).Hash -ne $original.Hash) {
        throw 'Existing evidence was not preserved.'
    }
    Write-Host 'PASS existing coverage and TRX preserved'
    function dotnet { $global:LASTEXITCODE = 17 }
    $code = Invoke-Phase10IntegrationCoverage -TestProject $project -Filter 'ignored' -ResultsDirectory $testRoot `
        -Index 2 -ConsoleVerbosity minimal -SettingsPath $settings
    if ($code -ne 17) { throw 'Test failure was not propagated.' }
    function dotnet { $global:LASTEXITCODE = 0; [void][IO.Directory]::CreateDirectory((Join-Path $testRoot 'coverage-3')) }
    $failed = $false
    try {
        Invoke-Phase10IntegrationCoverage -TestProject $project -Filter 'ignored' -ResultsDirectory $testRoot `
            -Index 3 -ConsoleVerbosity minimal -SettingsPath $settings
    } catch { $failed = $true }
    if (-not $failed) { throw 'Missing coverage was accepted.' }
    Write-Host 'PASS failed test and missing coverage propagate'
    function dotnet {
        $folder = Join-Path $testRoot 'coverage-4'
        [void][IO.Directory]::CreateDirectory($folder)
        Set-Content -LiteralPath (Join-Path $folder 'integration-4.trx') -Value 'test'
        foreach ($id in @('01234567-89ab-cdef-0123-456789abcdef', '11234567-89ab-cdef-0123-456789abcdef')) {
            $child = Join-Path $folder $id
            [void][IO.Directory]::CreateDirectory($child)
            Set-Content -LiteralPath (Join-Path $child 'coverage.cobertura.xml') -Value '<coverage/>'
        }
        $global:LASTEXITCODE = 0
    }
    $failed = $false
    try {
        Invoke-Phase10IntegrationCoverage -TestProject $project -Filter 'ignored' -ResultsDirectory $testRoot `
            -Index 4 -ConsoleVerbosity minimal -SettingsPath $settings
    } catch { $failed = $true }
    if (-not $failed) { throw 'Duplicate collector outputs were accepted.' }
    Write-Host 'PASS duplicate collector output rejected'
} finally {
    Pop-Location
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
