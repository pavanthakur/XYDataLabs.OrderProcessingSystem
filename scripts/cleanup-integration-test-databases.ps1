# Recovery is deliberately separate from the test runner and requires review plus confirmation.
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param([Parameter(Mandatory)][string]$ManifestPath)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'integration-test-database.ps1')
$root = Split-Path -Parent $PSScriptRoot
$manifestFullPath = [IO.Path]::GetFullPath($ManifestPath)
$resultsRoot = [IO.Path]::GetFullPath((Join-Path $root 'TestResults')).TrimEnd('\') + '\'
if (-not $manifestFullPath.StartsWith($resultsRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Manifest must be under repository TestResults on Q:.' }
$manifest = Get-Content -LiteralPath $manifestFullPath -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.status -notin @('creation-failed-review-required', 'cleanup-failed-review-required')) {
    throw 'Only an interrupted run-owned database manifest can be recovered.'
}
if ($manifest.databases.Count -ne 2) { throw 'Recovery manifest must contain exactly the shared/dedicated database pair.' }
$shared = [string]$manifest.databases[0].name
$dedicated = [string]$manifest.databases[1].name
Assert-IntegrationTestDatabaseNames -SharedDatabase $shared -DedicatedDatabase $dedicated
$connectionString = [Environment]::GetEnvironmentVariable('PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING')
if ([string]::IsNullOrWhiteSpace($connectionString)) { throw 'Set PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING privately for the exact local SQL server; no credentials are accepted as parameters.' }
$builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new($connectionString)
if ($builder.DataSource -match '(?i)\.database\.windows\.net') { throw 'Azure SQL is forbidden for integration database recovery.' }
$builder['Initial Catalog'] = 'master'
if (-not $PSCmdlet.ShouldProcess("run $($manifest.runId) database pair", 'Review and remove only databases marked createdByRun')) { return }
$connection = [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
try {
    $connection.Open()
    $machineCommand = $connection.CreateCommand()
    $machineCommand.CommandText = "SELECT CAST(SERVERPROPERTY('MachineName') AS nvarchar(128));"
    $machine = [string]$machineCommand.ExecuteScalar()
    if ($machine -cne [string]$manifest.serverMachine) { throw 'Recovery SQL server identity does not match the recorded server; refusing cleanup.' }
    foreach ($database in @($manifest.databases | Sort-Object { if ($_.name -eq $dedicated) { 0 } else { 1 } })) {
        if (-not $database.createdByRun) { continue }
        if ($database.preExisting -or -not $database.name.StartsWith("OrderProcessingSystem_Integration_$($manifest.runId)", [StringComparison]::Ordinal)) {
            throw 'Manifest ownership validation failed; refusing cleanup.'
        }
        $check = $connection.CreateCommand()
        $check.CommandText = 'SELECT CASE WHEN DB_ID(@database) IS NULL THEN 0 ELSE 1 END;'
        [void]$check.Parameters.AddWithValue('@database', [string]$database.name)
        if ([Convert]::ToInt32($check.ExecuteScalar(), [Globalization.CultureInfo]::InvariantCulture) -eq 1) {
            $drop = $connection.CreateCommand()
            $drop.CommandText = "DROP DATABASE [$($database.name)];"
            [void]$drop.ExecuteNonQuery()
        }
        $database.createdByRun = $false
    }
    $manifest.status = 'recovered-and-cleaned'
    $manifest.cleanupPending = $false
    $temporaryManifest = "$manifestFullPath.tmp"
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporaryManifest -Encoding utf8
    Move-Item -LiteralPath $temporaryManifest -Destination $manifestFullPath -Force
}
finally { $connection.Dispose() }
