$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Load only the production connection factory, not the Azure queries or SQL probe.
$scriptPath = Join-Path $PSScriptRoot 'Test-Phase10SqlBootstrapLogin.ps1'
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$parseErrors)
if ($parseErrors) { throw 'SQL bootstrap probe did not parse.' }
$factory = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'New-Phase10SqlBootstrapConnection'
}, $true)
if (-not $factory) { throw 'SQL bootstrap connection factory not found.' }
. ([scriptblock]::Create($factory.Extent.Text))

$fixturePassword = 'fixture-only;"quoted"'
$connection = New-Phase10SqlBootstrapConnection -ServerFqdn 'sql.example.invalid' -Username 'fixture' -Password $fixturePassword
try {
    $settings = [System.Data.SqlClient.SqlConnectionStringBuilder]::new($connection.ConnectionString)
    if ($connection.State -ne 'Closed' -or $settings.DataSource -cne 'tcp:sql.example.invalid,1433' -or
        $settings.InitialCatalog -cne 'master' -or $settings.UserID -cne 'fixture' -or
        $settings.Password -cne $fixturePassword -or -not $settings.Encrypt -or
        $settings.TrustServerCertificate -or $settings.ConnectTimeout -ne 15) {
        throw 'SQL bootstrap connection settings did not match the offline fixture.'
    }
} finally { $connection.Dispose() }
Write-Host 'SQL bootstrap connection regression passed (offline).'
