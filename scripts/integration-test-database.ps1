# Run-owned disposable SQL databases for integration tests. Dot-source this file.
function Get-IntegrationTestDatabaseNames {
    param([Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{32}$')][string]$RunId)
    [ordered]@{
        shared = "OrderProcessingSystem_Integration_$RunId"
        dedicated = "OrderProcessingSystem_Integration_${RunId}_TenantC"
    }
}

function Assert-IntegrationTestDatabaseNames {
    param([Parameter(Mandatory)][string]$SharedDatabase, [Parameter(Mandatory)][string]$DedicatedDatabase)
    if ($SharedDatabase -notmatch '^OrderProcessingSystem_Integration_[0-9a-f]{32}$' -or
        $DedicatedDatabase -cne "${SharedDatabase}_TenantC") {
        throw 'Integration database names do not match the run-owned shared/dedicated contract.'
    }
}

function Test-IntegrationSqlDatabaseExists {
    param([Parameter(Mandatory)][System.Data.SqlClient.SqlConnection]$Connection, [Parameter(Mandatory)][string]$Name)
    $command = $Connection.CreateCommand()
    $command.CommandText = 'SELECT CASE WHEN DB_ID(@database) IS NULL THEN 0 ELSE 1 END;'
    [void]$command.Parameters.AddWithValue('@database', $Name)
    return [Convert]::ToInt32($command.ExecuteScalar(), [Globalization.CultureInfo]::InvariantCulture) -eq 1
}

function Write-IntegrationDatabaseManifest {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Manifest, [Parameter(Mandatory)][string]$Path)
    $temporaryPath = "$Path.tmp"
    $Manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporaryPath -Encoding utf8
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Initialize-IntegrationTestDatabasePair {
    param(
        [Parameter(Mandatory)][string]$ConnectionString,
        [Parameter(Mandatory)][string]$ResultsDirectory,
        [ValidateSet('docker-phase10', 'local')][string]$Runtime = 'local'
    )

    $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new($ConnectionString)
    if ([string]::IsNullOrWhiteSpace($builder.DataSource) -or $builder.DataSource -match '(?i)\.database\.windows\.net') {
        throw 'Integration tests require an explicitly selected local SQL test endpoint; Azure SQL is forbidden.'
    }
    $runId = [Guid]::NewGuid().ToString('N')
    $names = Get-IntegrationTestDatabaseNames -RunId $runId
    Assert-IntegrationTestDatabaseNames -SharedDatabase $names.shared -DedicatedDatabase $names.dedicated

    $resultsRoot = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $PSScriptRoot) 'TestResults')).TrimEnd('\') + '\'
    $resolvedResults = [IO.Path]::GetFullPath($ResultsDirectory)
    if (-not $resolvedResults.StartsWith($resultsRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Integration database manifests must stay under repository TestResults on Q:.'
    }
    [void][IO.Directory]::CreateDirectory($resolvedResults)
    $manifestPath = Join-Path $resolvedResults "integration-databases-$runId.json"
    if (Test-Path -LiteralPath $manifestPath) { throw 'Unique integration manifest already exists; refusing to overwrite.' }

    $masterBuilder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new($builder.ConnectionString)
    $masterBuilder['Initial Catalog'] = 'master'
    $connection = [System.Data.SqlClient.SqlConnection]::new($masterBuilder.ConnectionString)
    $manifest = [ordered]@{
        schemaVersion = 1; runId = $runId; runtime = $Runtime; createdUtc = [DateTime]::UtcNow.ToString('o')
        serverAddress = $builder.DataSource; serverMachine = $null; status = 'creating'; cleanupPending = $false
        databases = @(
            [ordered]@{ name = $names.shared; preExisting = $false; createPending = $false; createdByRun = $false },
            [ordered]@{ name = $names.dedicated; preExisting = $false; createPending = $false; createdByRun = $false }
        )
    }
    Write-IntegrationDatabaseManifest -Manifest $manifest -Path $manifestPath
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = "SELECT CAST(SERVERPROPERTY('MachineName') AS nvarchar(128));"
        $manifest.serverMachine = [string]$command.ExecuteScalar()
        if ([string]::IsNullOrWhiteSpace($manifest.serverMachine)) { throw 'Cannot establish SQL server identity for integration database ownership.' }
        Write-IntegrationDatabaseManifest -Manifest $manifest -Path $manifestPath

        foreach ($database in $manifest.databases) {
            if (Test-IntegrationSqlDatabaseExists -Connection $connection -Name $database.name) {
                throw 'Generated integration database unexpectedly exists; refusing to adopt or delete it.'
            }

            $database.createPending = $true
            Write-IntegrationDatabaseManifest -Manifest $manifest -Path $manifestPath
            $command = $connection.CreateCommand()
            $command.CommandText = "CREATE DATABASE [$($database.name)];"
            [void]$command.ExecuteNonQuery()
            $database.createPending = $false
            $database.createdByRun = $true
            Write-IntegrationDatabaseManifest -Manifest $manifest -Path $manifestPath
        }
        $manifest.status = 'created'
        Write-IntegrationDatabaseManifest -Manifest $manifest -Path $manifestPath

        $sharedBuilder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new($builder.ConnectionString)
        $sharedBuilder['Initial Catalog'] = $names.shared
        $dedicatedBuilder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new($builder.ConnectionString)
        $dedicatedBuilder['Initial Catalog'] = $names.dedicated
        return [pscustomobject]@{
            RunId = $runId; ManifestPath = $manifestPath; SharedDatabase = $names.shared; DedicatedDatabase = $names.dedicated
            SharedConnectionString = $sharedBuilder.ConnectionString; DedicatedConnectionString = $dedicatedBuilder.ConnectionString
            MasterConnectionString = $masterBuilder.ConnectionString; Manifest = $manifest
        }
    }
    catch {
        $failureType = $_.Exception.GetType().Name
        $manifest.status = 'creation-failed-review-required'
        $manifest.failureType = $failureType
        Write-IntegrationDatabaseManifest -Manifest $manifest -Path $manifestPath
        $partialLease = [pscustomobject]@{
            SharedDatabase = $names.shared; DedicatedDatabase = $names.dedicated
            MasterConnectionString = $masterBuilder.ConnectionString; ManifestPath = $manifestPath; Manifest = $manifest
        }
        try {
            Complete-IntegrationTestDatabasePair -Lease $partialLease
            $manifest.status = 'setup-failed-and-cleaned'
            $manifest.failureType = $failureType
            Write-IntegrationDatabaseManifest -Manifest $manifest -Path $manifestPath
            throw "Integration database setup failed ($failureType); run-owned databases were cleaned. Manifest: $manifestPath"
        }
        catch {
            if ($manifest.status -eq 'setup-failed-and-cleaned') { throw }
            $manifest.status = 'creation-failed-review-required'
            $manifest.failureType = $failureType
            $manifest.cleanupFailureType = $_.Exception.GetType().Name
            Write-IntegrationDatabaseManifest -Manifest $manifest -Path $manifestPath
            throw "Integration database setup/cleanup failed. Review the run-owned manifest: $manifestPath"
        }
    }
    finally { $connection.Dispose() }
}

function Complete-IntegrationTestDatabasePair {
    param([Parameter(Mandatory)]$Lease)
    $manifest = $Lease.Manifest
    Assert-IntegrationTestDatabaseNames -SharedDatabase $Lease.SharedDatabase -DedicatedDatabase $Lease.DedicatedDatabase
    $connection = [System.Data.SqlClient.SqlConnection]::new($Lease.MasterConnectionString)
    try {
        $connection.Open()
        foreach ($database in @($manifest.databases | Sort-Object { if ($_.name -eq $Lease.DedicatedDatabase) { 0 } else { 1 } })) {
            if (-not $database.createdByRun) { continue }
            $manifest.cleanupPending = $true
            $database.cleanupPending = $true
            Write-IntegrationDatabaseManifest -Manifest $manifest -Path $Lease.ManifestPath
            if (Test-IntegrationSqlDatabaseExists -Connection $connection -Name $database.name) {
                $command = $connection.CreateCommand()
                $command.CommandText = "DROP DATABASE [$($database.name)];"
                [void]$command.ExecuteNonQuery() # Never force-disconnect external users.
            }
            $database.createdByRun = $false
            $database.cleanupPending = $false
            Write-IntegrationDatabaseManifest -Manifest $manifest -Path $Lease.ManifestPath
        }
        $manifest.cleanupPending = $false
        $manifest.status = 'completed-and-cleaned'
        $manifest.completedUtc = [DateTime]::UtcNow.ToString('o')
        Write-IntegrationDatabaseManifest -Manifest $manifest -Path $Lease.ManifestPath
    }
    catch {
        $manifest.status = 'cleanup-failed-review-required'
        Write-IntegrationDatabaseManifest -Manifest $manifest -Path $Lease.ManifestPath
        throw "Run-owned integration database cleanup is incomplete. Review manifest: $($Lease.ManifestPath)"
    }
    finally { $connection.Dispose() }
}
