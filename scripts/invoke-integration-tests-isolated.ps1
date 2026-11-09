# Run integration tests only against uniquely owned databases; never the application database.
# PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING is inherited privately and never logged.
#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('docker-phase10', 'local')][string]$Runtime,
    [Parameter(Mandatory)][string[]]$TestFilter,
    [Parameter(Mandatory)][string]$ResultsDirectory,
    [ValidateSet('minimal', 'normal', 'detailed', 'quiet')][string]$ConsoleVerbosity = 'minimal'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'phase10-docker-safety.ps1')
. (Join-Path $PSScriptRoot 'integration-test-database.ps1')
Assert-Phase10ComposeProject
$connectionString = [Environment]::GetEnvironmentVariable('PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING')
if ([string]::IsNullOrWhiteSpace($connectionString)) { throw 'Integration provisioning endpoint is not configured; credentials omitted.' }
$builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new($connectionString)
if ($Runtime -eq 'docker-phase10') {
    if ($builder.InitialCatalog -cne 'OrderProcessingSystem_Dev') { throw 'Docker integration provisioning requires the configured shared application SQL endpoint.' }
    Assert-Phase10HostSqlIdentity -ConnectionString $connectionString
} elseif ($builder.DataSource -match '(?i)\.database\.windows\.net') {
    throw 'Local integration tests cannot target Azure SQL.'
}
$reportPath = [IO.Path]::GetFullPath($ResultsDirectory)
$null = New-Item -ItemType Directory -Path $reportPath -Force
$lease = $null
$exitCode = 1
$previousTestConnection = [Environment]::GetEnvironmentVariable('ORDERPROCESSING_TEST_CONNECTION_STRING')
$providerMetadataFingerprints = $null
$activeMarker = $null
if ($Runtime -eq 'docker-phase10') {
    $activeMarker = Join-Path $root ("TestResults/integration-active-{0}.lock" -f [guid]::NewGuid().ToString('N'))
    $handle = [IO.File]::Open($activeMarker,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $handle.Dispose()
}

function Get-ProviderMetadataFingerprint {
    param([Parameter(Mandatory)][string]$ConnectionString)
    $connectionBuilder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new($ConnectionString)
    $connection = [System.Data.SqlClient.SqlConnection]::new($connectionBuilder.ConnectionString)
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = @'
SELECT t.Code, t.Status, t.TenantTier, ISNULL(t.PaymentProviderCode, ''), p.ProviderType, p.IsActive,
       p.IsProduction, p.Use3DSecure, ISNULL(p.APIUrl, ''), ISNULL(p.MerchantId, ''), ISNULL(p.PublicKey, ''),
       ISNULL(p.PrivateKeyConfigurationKey, '')
FROM dbo.Tenants AS t
LEFT JOIN payments.PaymentProviders AS p ON p.TenantId = t.Id
ORDER BY t.Code, p.ProviderType;
'@
        $reader = $command.ExecuteReader()
        $rows = [Collections.Generic.List[string]]::new()
        while ($reader.Read()) {
            $fields = for ($index = 0; $index -lt $reader.FieldCount; $index++) { [string]$reader.GetValue($index) }
            $rows.Add(($fields -join "`u{001f}"))
        }
        $reader.Dispose()
        $bytes = [Text.Encoding]::UTF8.GetBytes(($rows -join "`n"))
        return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    }
    finally { $connection.Dispose() }
}

try {
    if ($Runtime -eq 'docker-phase10' -and (Test-Path (Join-Path $root 'TestResults/local-payment-test-state.lock'))) { throw 'A payment fixture is active; isolated integration metadata comparisons require a stable baseline.' }
    $settingsPath = Join-Path $root 'Resources/Docker/.env.local'
    $settings = if (Test-Path -LiteralPath $settingsPath) { Get-Phase10LocalSettings -Path $settingsPath } else { @{} }
    Initialize-Phase10LogRedaction -Settings $settings
    $script:phase10LogSecrets += @($builder.Password, $connectionString) | Where-Object { $_.Length -ge 4 }
    if ($Runtime -eq 'docker-phase10') {
        $dedicatedApplicationBuilder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new($connectionString)
        $dedicatedApplicationBuilder['Initial Catalog'] = 'OrderProcessingSystem_TenantC_Dev'
        $providerMetadataFingerprints = [ordered]@{
            shared = Get-ProviderMetadataFingerprint -ConnectionString $connectionString
            dedicated = Get-ProviderMetadataFingerprint -ConnectionString $dedicatedApplicationBuilder.ConnectionString
        }
    }
    $lease = Initialize-IntegrationTestDatabasePair -ConnectionString $connectionString -ResultsDirectory $reportPath -Runtime $Runtime
    $env:ORDERPROCESSING_TEST_CONNECTION_STRING = $lease.SharedConnectionString
    $testProject = Join-Path $root 'tests/XYDataLabs.OrderProcessingSystem.Integration.Tests/XYDataLabs.OrderProcessingSystem.Integration.Tests.csproj'
    $exitCode = 0
    $index = 0
    foreach ($filter in $TestFilter) {
        $index++
        $trxName = 'integration-{0}.trx' -f $index
        dotnet test $testProject --filter $filter --results-directory $reportPath `
            --logger "trx;LogFileName=$trxName" --logger "console;verbosity=$ConsoleVerbosity" 2>&1 |
            Protect-Phase10Log | Tee-Object -FilePath (Join-Path $reportPath ("integration-{0}.log" -f $index))
        if ($LASTEXITCODE -ne 0) { $exitCode = $LASTEXITCODE; break }
    }
    if ($Runtime -eq 'docker-phase10') {
        $afterDedicatedApplicationBuilder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new($connectionString)
        $afterDedicatedApplicationBuilder['Initial Catalog'] = 'OrderProcessingSystem_TenantC_Dev'
        $sharedUnchanged = $providerMetadataFingerprints.shared -ceq (Get-ProviderMetadataFingerprint -ConnectionString $connectionString)
        $dedicatedUnchanged = $providerMetadataFingerprints.dedicated -ceq (Get-ProviderMetadataFingerprint -ConnectionString $afterDedicatedApplicationBuilder.ConnectionString)
        $metadataUnchanged = $sharedUnchanged -and $dedicatedUnchanged
        Set-Content -LiteralPath (Join-Path $reportPath 'application-provider-metadata-check.json') `
            -Value (@{ sharedUnchanged = $sharedUnchanged; dedicatedUnchanged = $dedicatedUnchanged; unchanged = $metadataUnchanged; comparedUtc = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json) -Encoding utf8
        if (-not $metadataUnchanged) { throw 'Application tenant/provider settings changed during isolated integration execution.' }
    }
} catch {
    [string]$message = $_.Exception.Message
    foreach ($secret in $script:phase10LogSecrets) { $message = $message.Replace($secret, '[REDACTED]') }
    Write-Host $message -ForegroundColor Red
    $exitCode = 1
} finally {
    if ($activeMarker) { Remove-Item -LiteralPath $activeMarker -ErrorAction SilentlyContinue }
    if ($null -eq $previousTestConnection) { Remove-Item Env:ORDERPROCESSING_TEST_CONNECTION_STRING -ErrorAction SilentlyContinue }
    else { $env:ORDERPROCESSING_TEST_CONNECTION_STRING = $previousTestConnection }
    if ($null -ne $lease) {
        try { Complete-IntegrationTestDatabasePair -Lease $lease }
        catch { Write-Error $_; $exitCode = 1 }
    }
}
exit $exitCode
