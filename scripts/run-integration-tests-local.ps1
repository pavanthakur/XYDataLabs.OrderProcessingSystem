#Requires -Version 7.0

param(
    [string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),

    [ValidateSet('minimal', 'normal', 'detailed', 'quiet')]
    [string]$ConsoleVerbosity = 'minimal'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'phase10-docker-safety.ps1')

$testProject = Join-Path $WorkspaceRoot 'tests\XYDataLabs.OrderProcessingSystem.Integration.Tests\XYDataLabs.OrderProcessingSystem.Integration.Tests.csproj'
$resultsRoot = Join-Path $WorkspaceRoot 'TestResults\Integration'
$runStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runDir = Join-Path $resultsRoot $runStamp
$statusWriter = Join-Path $WorkspaceRoot 'scripts\write-playwright-run-status.ps1'
$istZone = [System.TimeZoneInfo]::FindSystemTimeZoneById('India Standard Time')

function Get-IstTimestamp {
    return [System.TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $istZone).ToString('o')
}
$logName = 'integration-tests.log'
$envLocalPath = Join-Path $WorkspaceRoot 'Resources\Docker\.env.local'

if (-not (Test-Path $envLocalPath)) {
    throw "Local SQL secrets file not found: $envLocalPath"
}

$sqlPasswordLine = (Get-Content -LiteralPath $envLocalPath | Where-Object { $_ -match '^LOCAL_SQL_PASSWORD=' } | Select-Object -First 1)
if ([string]::IsNullOrWhiteSpace($sqlPasswordLine)) {
    throw "LOCAL_SQL_PASSWORD was not found in $envLocalPath"
}

$sqlPassword = $sqlPasswordLine.Split('=', 2)[1].Trim().Trim('"', "'")
if ([string]::IsNullOrWhiteSpace($sqlPassword) -or $sqlPassword -match '^<.*>$') { throw 'LOCAL_SQL_PASSWORD is missing or a placeholder; credentials omitted.' }
$localSqlBuilder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
$localSqlBuilder['Data Source'] = 'tcp:127.0.0.1,1433'
$localSqlBuilder['Initial Catalog'] = 'master'
$localSqlBuilder['User ID'] = 'sa'
$localSqlBuilder['Password'] = $sqlPassword
$localSqlBuilder['Trust Server Certificate'] = $true
$localSqlBuilder['Encrypt'] = $false
Initialize-Phase10LogRedaction -Settings (Get-Phase10LocalSettings -Path $envLocalPath)

New-Item -ItemType Directory -Path $runDir -Force | Out-Null
& pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey 'local-http' -TaskName 'local-http-integration' -Status started -Message "runDir=$runDir"

$previousProvisioningConnection = $env:PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING
$env:PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING = $localSqlBuilder.ConnectionString

Push-Location $WorkspaceRoot
try {
    Write-Host 'Using a run-owned local integration database pair; credentials omitted.'
    Add-Content -Path (Join-Path $runDir 'integration-tests.log') -Value "[$(Get-IstTimestamp)] Integration test run started."
    dotnet restore $testProject --ignore-failed-sources 2>&1 | Tee-Object -FilePath (Join-Path $runDir 'restore.log')
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $WorkspaceRoot 'scripts\invoke-integration-tests-isolated.ps1') `
        -Runtime local -TestFilter 'Category=Integration' -ResultsDirectory $runDir -ConsoleVerbosity $ConsoleVerbosity 2>&1 |
        Protect-Phase10Log | Tee-Object -FilePath (Join-Path $runDir $logName)
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0) {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey 'local-http' -TaskName 'local-http-integration' -Status passed -Message "results=$runDir"
    } else {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey 'local-http' -TaskName 'local-http-integration' -Status failed -Message "exitCode=$exitCode"
    }
    exit $exitCode
}
finally {
    Pop-Location
    if ($null -eq $previousProvisioningConnection) { Remove-Item Env:PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING -ErrorAction SilentlyContinue }
    else { $env:PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING = $previousProvisioningConnection }
}
