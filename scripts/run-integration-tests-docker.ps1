#Requires -Version 7.0

param(
    [Parameter(Mandatory = $false)]
    [string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [ValidateSet('minimal', 'normal', 'detailed', 'quiet')]
    [string]$ConsoleVerbosity = 'minimal',

    [switch]$CollectCoverage
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'phase10-docker-safety.ps1')

$testProject = Join-Path $WorkspaceRoot 'tests\XYDataLabs.OrderProcessingSystem.Integration.Tests\XYDataLabs.OrderProcessingSystem.Integration.Tests.csproj'
$resultsRoot = Join-Path $WorkspaceRoot 'TestResults\Integration'
$dockerSqlGuardrailScript = Join-Path $WorkspaceRoot 'scripts\assert-docker-runtime-sql-guardrail.ps1'
$runDir = if ([string]::IsNullOrWhiteSpace($env:PHASE10_RUN_ROOT)) {
    Join-Path $resultsRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
}
else {
    Join-Path $env:PHASE10_RUN_ROOT 'integration'
}
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

if (-not (Test-Path -LiteralPath $dockerSqlGuardrailScript)) {
    throw "Docker SQL guardrail script not found: $dockerSqlGuardrailScript"
}

. $dockerSqlGuardrailScript

$effectiveSettings = Get-Phase10LocalSettings -Path $envLocalPath
$sqlPassword = $effectiveSettings.LOCAL_SQL_PASSWORD
if ([string]::IsNullOrWhiteSpace($sqlPassword) -or $sqlPassword -match '^<.*>$') {
    throw 'LOCAL_SQL_PASSWORD is missing or a placeholder; credentials omitted.'
}

$connectionString = New-Phase10HostSqlConnectionString -Database 'OrderProcessingSystem_Dev' -Password $sqlPassword
Assert-Phase10HostSqlIdentity -ConnectionString $connectionString
Initialize-Phase10LogRedaction -Settings (Get-Phase10LocalSettings -Path $envLocalPath)
Assert-DockerRuntimeSqlGuardrail `
    -ScriptName (Split-Path -Leaf $PSCommandPath) `
    -ConnectionString $connectionString `
    -ExpectedDatabase 'OrderProcessingSystem_Dev' `
    -SourceDescription 'Resources/Docker/.env.local + docker sql host port mapping' `
    -AllowHostMappedDockerSql

New-Item -ItemType Directory -Path $runDir -Force | Out-Null

$previousProvisioningConnection = $env:PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING
$env:PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING = $connectionString

Push-Location $WorkspaceRoot
try {
    Write-Host "Using verified Docker SQL host endpoint tcp:127.0.0.1,$(Get-Phase10SqlHostPort); credentials omitted."
    Add-Content -Path (Join-Path $runDir 'integration-tests-docker.log') -Value "[$(Get-IstTimestamp)] Integration test run started."
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey 'docker-http' -TaskName 'docker-http-integration' -Status started -Message "runDir=$runDir"
    dotnet restore $testProject --ignore-failed-sources 2>&1 | Protect-Phase10Log | Tee-Object -FilePath (Join-Path $runDir 'restore.log')
    if ($LASTEXITCODE -ne 0) {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey 'docker-http' -TaskName 'docker-http-integration' -Status failed -Message "restore failed"
        exit $LASTEXITCODE
    }

    & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $WorkspaceRoot 'scripts\invoke-integration-tests-isolated.ps1') `
        -Runtime docker-phase10 -TestFilter 'Category=Integration' -ResultsDirectory $runDir -ConsoleVerbosity $ConsoleVerbosity -CollectCoverage:$CollectCoverage 2>&1 |
        Protect-Phase10Log | Tee-Object -FilePath (Join-Path $runDir $logName)
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0) {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey 'docker-http' -TaskName 'docker-http-integration' -Status passed -Message "results=$runDir"
    } else {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey 'docker-http' -TaskName 'docker-http-integration' -Status failed -Message "exitCode=$exitCode"
    }
    exit $exitCode
}
finally {
    Pop-Location
    if ($null -eq $previousProvisioningConnection) { Remove-Item Env:PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING -ErrorAction SilentlyContinue }
    else { $env:PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING = $previousProvisioningConnection }
}
