function Assert-DockerRuntimeSqlGuardrail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptName,

        [Parameter(Mandatory = $true)]
        [string]$ConnectionString,

        [Parameter(Mandatory = $false)]
        [string]$ExpectedDatabase,

        [Parameter(Mandatory = $false)]
        [string]$SourceDescription = '',

        [Parameter(Mandatory = $false)]
        [switch]$AllowHostMappedDockerSql
    )

    if ([string]::IsNullOrWhiteSpace($ConnectionString)) {
        throw "${ScriptName}: Docker SQL guardrail failed because no connection string was provided."
    }

    try {
        $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new($ConnectionString)
    }
    catch {
        throw "${ScriptName}: Docker SQL guardrail failed because the connection string is invalid. $($_.Exception.Message)"
    }

    $dataSource = [string]$builder.DataSource
    $database = [string]$builder.InitialCatalog
    $serverHost = ($dataSource -split ',', 2)[0].Trim().ToLowerInvariant()
    $normalizedSourceDescription = $SourceDescription.Trim().ToLowerInvariant()

    if ([string]::IsNullOrWhiteSpace($serverHost)) {
        throw "${ScriptName}: Docker SQL guardrail failed because the SQL server host could not be resolved from the connection string."
    }

    if ([string]::IsNullOrWhiteSpace($database)) {
        throw "${ScriptName}: Docker SQL guardrail failed because the SQL database name could not be resolved from the connection string."
    }

    if ($database -eq 'OrderProcessingSystem_Local' -or $database -like 'OrderProcessingSystem_*_Local') {
        throw "${ScriptName}: Docker SQL guardrail rejected local database '$database'. Runtime=docker must use the Docker environment database contract, not the local baseline."
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedDatabase) -and $database -ne $ExpectedDatabase) {
        throw "${ScriptName}: Docker SQL guardrail rejected database '$database'. Expected '$ExpectedDatabase' for this Docker runtime path."
    }

    if ($normalizedSourceDescription -like '*sharedsettings.local.json*') {
        throw "${ScriptName}: Docker SQL guardrail rejected SourceDescription '$SourceDescription'. Runtime=docker must not resolve SQL from sharedsettings.local.json."
    }

    $hostLocalAliases = @('localhost', '127.0.0.1', '.', '(local)', '(localdb)')
    if ($hostLocalAliases -contains $serverHost -and -not $AllowHostMappedDockerSql.IsPresent) {
        throw "${ScriptName}: Docker SQL guardrail rejected host-local SQL endpoint '$dataSource'. If this script intentionally uses the Docker SQL container through a host port mapping, it must opt in with -AllowHostMappedDockerSql."
    }
}
