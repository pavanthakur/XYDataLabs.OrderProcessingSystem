#Requires -Version 7.0
function Invoke-Phase10IntegrationCoverage {
    param(
        [Parameter(Mandatory)][string]$TestProject,
        [Parameter(Mandatory)][string]$Filter,
        [Parameter(Mandatory)][string]$ResultsDirectory,
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)][string]$ConsoleVerbosity,
        [Parameter(Mandatory)][string]$SettingsPath
    )
    $coverageRoot = Join-Path $ResultsDirectory "coverage-$Index"
    $trxName = "integration-$Index.trx"
    $destination = Join-Path $ResultsDirectory $trxName
    if ((Test-Path -LiteralPath $coverageRoot) -or (Test-Path -LiteralPath $destination)) {
        throw 'Integration coverage or TRX output already exists; refusing to overwrite evidence.'
    }
    & dotnet test $TestProject --no-build --no-restore --filter $Filter --results-directory $coverageRoot `
        --logger "trx;LogFileName=$trxName" --logger "console;verbosity=$ConsoleVerbosity" `
        --settings $SettingsPath --collect 'XPlat Code Coverage' 2>&1 |
        Protect-Phase10Log | Tee-Object -FilePath (Join-Path $ResultsDirectory "integration-$Index.log") | Out-Host
    $code = $LASTEXITCODE
    $trx = Join-Path $coverageRoot $trxName
    if (Test-Path -LiteralPath $trx -PathType Leaf) {
        [IO.File]::Copy($trx, $destination, $false)
    }
    if ($code -ne 0) { return $code }
    $coverage = @(Get-ChildItem -LiteralPath $coverageRoot -Directory | Where-Object {
        $_.Name -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' -and
        -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
    } | ForEach-Object {
        $candidate = Join-Path $_.FullName 'coverage.cobertura.xml'
        if (Test-Path -LiteralPath $candidate) { Get-Item -LiteralPath $candidate -Force }
    })
    if (-not (Test-Path -LiteralPath $destination -PathType Leaf) -or $coverage.Count -ne 1 -or
        $coverage[0].PSIsContainer -or ($coverage[0].Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        $coverage[0].Length -gt 2MB) {
        throw 'Integration TRX or bounded coverage evidence was missing or duplicated.'
    }
    return 0
}
