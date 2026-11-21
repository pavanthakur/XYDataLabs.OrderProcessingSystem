param([switch]$VerifyVault)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$password = $env:SQL_ADMIN_PASSWORD
if ([string]::IsNullOrWhiteSpace($password) -or [string]::IsNullOrWhiteSpace($env:SQL_ADMIN_USERNAME)) {
    throw 'SQL bootstrap credentials were not supplied by the deployment workflow.'
}

if ($VerifyVault) {
    $stored = az keyvault secret show --vault-name $env:SQL_KEY_VAULT --name sql-admin-password --query value -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or $stored -cne $password) {
        throw 'The deployed Key Vault SQL bootstrap credential could not be read or did not match. Migrations are blocked.'
    }
}

$fqdn = az sql server show --resource-group $env:SQL_RESOURCE_GROUP --name $env:SQL_SERVER_NAME --query fullyQualifiedDomainName -o tsv
if ($LASTEXITCODE -ne 0 -or $fqdn -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]+$') {
    throw 'Could not resolve the expected Azure SQL server hostname.'
}

$builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
$builder['Data Source'] = "tcp:$fqdn,1433"
$builder['Initial Catalog'] = 'master'
$builder['User ID'] = $env:SQL_ADMIN_USERNAME
$builder['Password'] = $password
$builder['Encrypt'] = $true
$builder['Trust Server Certificate'] = $false
$builder['Connect Timeout'] = 15
$connection = [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
try {
    $connection.Open()
    $command = $connection.CreateCommand()
    try {
        $command.CommandText = 'SELECT 1'
        $command.CommandTimeout = 10
        if ($command.ExecuteScalar() -ne 1) { throw 'SQL bootstrap probe returned an unexpected result.' }
    } finally { $command.Dispose() }
} catch [System.Data.SqlClient.SqlException] {
    $code = $_.Exception.Number
    throw "SQL bootstrap login/read probe failed (SQL error $code). Check the existing credential, SQL authentication mode and runner network access; no automatic reset is performed."
} finally { $connection.Dispose() }

Write-Host 'SQL bootstrap login verified with a read-only query.'
