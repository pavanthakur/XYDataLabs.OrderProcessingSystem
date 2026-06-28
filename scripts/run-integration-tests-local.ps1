#Requires -Version 7.0

param(
    [string] $WorkspaceRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$testProject = Join-Path $WorkspaceRoot 'tests\XYDataLabs.OrderProcessingSystem.Integration.Tests\XYDataLabs.OrderProcessingSystem.Integration.Tests.csproj'
$resultsRoot = Join-Path $WorkspaceRoot 'TestResults\Integration'
$runStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runDir = Join-Path $resultsRoot $runStamp
$statusWriter = Join-Path $WorkspaceRoot 'scripts\write-playwright-run-status.ps1'
$istZone = [System.TimeZoneInfo]::FindSystemTimeZoneById('India Standard Time')

function Get-IstTimestamp {
    return [System.TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $istZone).ToString('o')
}
$databaseName = "OrderProcessingSystem_Integration_$runStamp"
$trxName = 'integration-tests.trx'
$logName = 'integration-tests.log'
$envLocalPath = Join-Path $WorkspaceRoot 'Resources\Docker\.env.local'

if (-not (Test-Path $envLocalPath)) {
    throw "Local SQL secrets file not found: $envLocalPath"
}

$sqlPassword = (Get-Content -LiteralPath $envLocalPath | Where-Object { $_ -match '^LOCAL_SQL_PASSWORD=' } | Select-Object -First 1)
if ([string]::IsNullOrWhiteSpace($sqlPassword)) {
    throw "LOCAL_SQL_PASSWORD was not found in $envLocalPath"
}

$sqlPassword = $sqlPassword.Split('=', 2)[1].Trim()

New-Item -ItemType Directory -Path $runDir -Force | Out-Null
& pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey 'local-http' -TaskName 'local-http-integration' -Status started -Message "runDir=$runDir"

$env:ORDERPROCESSING_TEST_CONNECTION_STRING = "Server=localhost,1433;Database=$databaseName;User Id=sa;Password=$sqlPassword;TrustServerCertificate=True;MultipleActiveResultSets=true;"

Push-Location $WorkspaceRoot
try {
    Write-Host "Using test database: $databaseName"
    Add-Content -Path (Join-Path $runDir 'integration-tests.log') -Value "[$(Get-IstTimestamp)] Integration test run started."
    dotnet restore $testProject --ignore-failed-sources 2>&1 | Tee-Object -FilePath (Join-Path $runDir 'restore.log')
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    dotnet test $testProject `
        --no-restore `
        --filter Category=Integration `
        --results-directory $runDir `
        --logger "trx;LogFileName=$trxName" `
        --logger "console;verbosity=minimal" 2>&1 | Tee-Object -FilePath (Join-Path $runDir $logName)
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0) {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey 'local-http' -TaskName 'local-http-integration' -Status passed -Message "trx=$trxName"
    } else {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey 'local-http' -TaskName 'local-http-integration' -Status failed -Message "exitCode=$exitCode"
    }
    exit $exitCode
}
finally {
    Pop-Location
}
