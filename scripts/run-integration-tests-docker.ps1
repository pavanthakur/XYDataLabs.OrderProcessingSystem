#Requires -Version 7.0

param(
    [Parameter(Mandatory = $false)]
    [string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$testProject = Join-Path $WorkspaceRoot 'tests\XYDataLabs.OrderProcessingSystem.Integration.Tests\XYDataLabs.OrderProcessingSystem.Integration.Tests.csproj'
$resultsRoot = Join-Path $WorkspaceRoot 'TestResults\Integration'
$runStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runDir = Join-Path $resultsRoot $runStamp
$trxName = 'integration-tests-docker.trx'
$logName = 'integration-tests-docker.log'
$envLocalPath = Join-Path $WorkspaceRoot 'Resources\Docker\.env.local'
$statusWriter = Join-Path $WorkspaceRoot 'scripts\write-playwright-run-status.ps1'
$istZone = [System.TimeZoneInfo]::FindSystemTimeZoneById('India Standard Time')

function Get-IstTimestamp {
    return [System.TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $istZone).ToString('o')
}

if (-not (Test-Path $envLocalPath)) {
    throw "Local Docker secrets file not found: $envLocalPath"
}

$sqlPasswordLine = Get-Content -LiteralPath $envLocalPath | Where-Object { $_ -match '^LOCAL_SQL_PASSWORD=' } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($sqlPasswordLine)) {
    throw "LOCAL_SQL_PASSWORD was not found in $envLocalPath"
}

$sqlPassword = $sqlPasswordLine.Split('=', 2)[1].Trim()
if ([string]::IsNullOrWhiteSpace($sqlPassword)) {
    throw "LOCAL_SQL_PASSWORD in $envLocalPath is empty."
}

$connectionString = "Server=localhost,1433;Database=OrderProcessingSystem_Dev;User Id=sa;Password=$sqlPassword;TrustServerCertificate=True;MultipleActiveResultSets=true;"

New-Item -ItemType Directory -Path $runDir -Force | Out-Null

$env:ORDERPROCESSING_TEST_CONNECTION_STRING = $connectionString

Push-Location $WorkspaceRoot
try {
    Write-Host "Using Docker SQL test connection: $connectionString"
    Add-Content -Path (Join-Path $runDir 'integration-tests-docker.log') -Value "[$(Get-IstTimestamp)] Integration test run started."
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey 'docker-http' -TaskName 'docker-http-integration' -Status started -Message "runDir=$runDir"
    dotnet restore $testProject --ignore-failed-sources 2>&1 | Tee-Object -FilePath (Join-Path $runDir 'restore.log')
    if ($LASTEXITCODE -ne 0) {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey 'docker-http' -TaskName 'docker-http-integration' -Status failed -Message "restore failed"
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
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey 'docker-http' -TaskName 'docker-http-integration' -Status passed -Message "trx=$trxName"
    } else {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey 'docker-http' -TaskName 'docker-http-integration' -Status failed -Message "exitCode=$exitCode"
    }
    exit $exitCode
}
finally {
    Pop-Location
}
