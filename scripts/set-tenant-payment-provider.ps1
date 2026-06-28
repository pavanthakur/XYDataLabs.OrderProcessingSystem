[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('local', 'docker', 'azure')]
    [string]$Runtime,

    [Parameter(Mandatory = $true)]
    [ValidateSet('dev', 'stg', 'prod')]
    [string]$Environment,

    [Parameter(Mandatory = $true)]
    [ValidateSet('TenantA', 'TenantB', 'TenantC')]
    [string]$TenantCode,

    [Parameter(Mandatory = $true)]
    [ValidateSet('OpenPay', 'Razorpay')]
    [string]$ProviderType,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Json', 'Text')]
    [string]$OutputFormat = 'Json'
)

$ErrorActionPreference = 'Stop'

$script:AzureSqlContext = $null
$script:AzureSqlFirewallOpened = $false
$script:LocalSqlPassword = $null

function Get-DatabaseName {
    param(
        [Parameter(Mandatory = $true)] [string] $CurrentRuntime,
        [Parameter(Mandatory = $true)] [string] $CurrentEnvironment
    )

    # PaymentProviderCode is a Tenant Registry field. TenantRegistryDbContext always reads it from
    # the central/shared registry database (OrderProcessingSystem_Dev/_Stg/_Prod), regardless of
    # whether the tenant is SharedPool or Dedicated tier. TenantC's dedicated database
    # (OrderProcessingSystem_TenantC_*) is scoped to business operations only — updating it here
    # would not affect what TenantPaymentProviderResolver sees. Always target the registry DB.
    if ($CurrentRuntime -eq 'local') {
        return 'OrderProcessingSystem_Local'
    }

    if ($CurrentRuntime -eq 'azure') {
        $azureEnvironmentDescriptor = Get-AzureEnvironmentDescriptor -CurrentEnvironment $CurrentEnvironment
        $environmentSuffix = $azureEnvironmentDescriptor.AzureSqlDatabaseSuffix
    }
    else {
        $environmentSuffix = switch ($CurrentEnvironment) {
            'dev' { 'Dev' }
            'stg' { 'Stg' }
            'prod' { 'Prod' }
            default { throw "Unsupported environment: $CurrentEnvironment" }
        }
    }

    return "OrderProcessingSystem_$environmentSuffix"
}

function Escape-SqlLiteral {
    param([Parameter(Mandatory = $true)] [string] $Value)

    return $Value.Replace("'", "''")
}

function Normalize-SqlOutputLines {
    param([string[]] $Lines)

    if ($null -eq $Lines -or $Lines.Count -eq 0) {
        return @()
    }

    return @(
        $Lines |
            ForEach-Object { $_.Trim() } |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and
                $_ -notmatch '^[-\s]+$' -and
                $_ -notmatch '^\(\d+ rows affected\)$' -and
                $_ -ne 'PaymentProviderCode'
            }
    )
}

function Get-AzureEnvironmentDescriptor {
    param(
        [Parameter(Mandatory = $true)] [string] $CurrentEnvironment
    )

    $branchPolicyScriptPath = Join-Path $PSScriptRoot '..\Resources\Azure-Deployment\branch-policy.ps1'
    . $branchPolicyScriptPath

    $branchPolicy = Get-GitHubBranchPolicy
    return Get-GitHubEnvironmentDescriptor -Policy $branchPolicy -EnvironmentKey $CurrentEnvironment
}

function Invoke-AzureCliText {
    param(
        [Parameter(Mandatory = $true)] [scriptblock] $Command,
        [Parameter(Mandatory = $true)] [string] $Operation,
        [Parameter(Mandatory = $false)] [int] $MaxAttempts = 3
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $result = & $Command 2>&1
        if ($LASTEXITCODE -eq 0) {
            $text = ((@($result | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)).Trim()
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                return $text
            }
        }

        if ($attempt -ge $MaxAttempts) {
            throw "${Operation} failed. $((@($result | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine).Trim())"
        }
    }

    throw "$Operation returned no response."
}

function Get-PublicIpAddress {
    $candidates = @(
        'https://api.ipify.org?format=json',
        'https://ifconfig.me/ip'
    )

    foreach ($endpoint in $candidates) {
        try {
            $response = Invoke-RestMethod -Uri $endpoint -Method Get -TimeoutSec 10
            if ($response -is [string]) {
                $value = $response.Trim()
            }
            else {
                $value = [string] $response.ip
            }

            if ($value -match '^(?:\d{1,3}\.){3}\d{1,3}$') {
                return $value
            }
        }
        catch {
        }
    }

    throw 'Failed to determine the current public IP address for the Azure SQL firewall rule.'
}

function Get-AzureSqlContext {
    if ($null -ne $script:AzureSqlContext) {
        return $script:AzureSqlContext
    }

    $environmentDescriptor = Get-AzureEnvironmentDescriptor -CurrentEnvironment $Environment
    $resourceSuffix = $environmentDescriptor.ResourceSuffix
    $resourceGroup = "rg-orderprocessing-$resourceSuffix"
    $keyVaultName = "kv-orderprocessing-$resourceSuffix"
    $sqlServerName = "orderprocessing-sql-$resourceSuffix"
    $sqlServerFqdn = "$sqlServerName.database.windows.net"
    $sqlAdminUser = Invoke-AzureCliText -Operation 'Resolve SQL administrator login' -Command {
        az sql server show --name $sqlServerName --resource-group $resourceGroup --query administratorLogin -o tsv
    }
    $sqlAdminPassword = Invoke-AzureCliText -Operation 'Resolve sql-admin-password from Key Vault' -Command {
        az keyvault secret show --vault-name $keyVaultName --name sql-admin-password --query value -o tsv
    }

    $script:AzureSqlContext = [PSCustomObject]@{
        ResourceGroup = $resourceGroup
        SqlServerName = $sqlServerName
        SqlServerFqdn = $sqlServerFqdn
        SqlAdminUser = $sqlAdminUser
        SqlAdminPassword = $sqlAdminPassword
        RuleName = "$($environmentDescriptor.GitHubEnvironment)-payment-automation"
    }

    return $script:AzureSqlContext
}

function Ensure-AzureSqlFirewallAccess {
    if ($script:AzureSqlFirewallOpened) {
        return
    }

    $azureSqlContext = Get-AzureSqlContext
    $publicIp = Get-PublicIpAddress

    $createResult = az sql server firewall-rule create `
        --resource-group $azureSqlContext.ResourceGroup `
        --server $azureSqlContext.SqlServerName `
        --name $azureSqlContext.RuleName `
        --start-ip-address $publicIp `
        --end-ip-address $publicIp 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "Open Azure SQL firewall access failed. $((@($createResult | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine).Trim())"
    }

    $script:AzureSqlFirewallOpened = $true
}

function Invoke-LocalSqlTextQuery {
    param(
        [Parameter(Mandatory = $true)] [string] $Database,
        [Parameter(Mandatory = $true)] [string] $Query
    )

    $normalizedQuery = ($Query -replace "`r?`n", ' ').Trim()
    $localSqlPassword = Get-LocalSqlPassword
    $connectionString = "Server=localhost,1433;Initial Catalog=$Database;User Id=sa;Password=$localSqlPassword;Encrypt=False;TrustServerCertificate=True;MultipleActiveResultSets=True;Connection Timeout=30;"
    $connection = [System.Data.SqlClient.SqlConnection]::new($connectionString)

    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = "SET NOCOUNT ON; $normalizedQuery"
        $command.CommandTimeout = 60

        $reader = $command.ExecuteReader()
        try {
            if ($reader.FieldCount -le 0) {
                return @()
            }

            $table = [System.Data.DataTable]::new()
            $table.Load($reader)
            return Normalize-SqlOutputLines -Lines @(
                $table.Rows | ForEach-Object {
                    if ($table.Columns.Count -gt 0) {
                        [string] $_[$table.Columns[0].ColumnName]
                    }
                }
            )
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        if ($connection.State -ne [System.Data.ConnectionState]::Closed) {
            $connection.Close()
        }

        $connection.Dispose()
    }
}

function Get-LocalSqlPassword {
    if (-not [string]::IsNullOrWhiteSpace($script:LocalSqlPassword)) {
        return $script:LocalSqlPassword
    }

    $envLocalPath = Join-Path $PSScriptRoot '..\Resources\Docker\.env.local'
    if (-not (Test-Path $envLocalPath)) {
        throw "Local SQL secrets file not found: $envLocalPath"
    }

    $sqlPasswordLine = Get-Content -LiteralPath $envLocalPath | Where-Object { $_ -match '^LOCAL_SQL_PASSWORD=' } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($sqlPasswordLine)) {
        throw "LOCAL_SQL_PASSWORD was not found in $envLocalPath"
    }

    $sqlPassword = $sqlPasswordLine.Split('=', 2)[1].Trim()
    if ([string]::IsNullOrWhiteSpace($sqlPassword)) {
        throw "LOCAL_SQL_PASSWORD in $envLocalPath is empty."
    }

    $script:LocalSqlPassword = $sqlPassword
    return $script:LocalSqlPassword
}

function Invoke-DockerSqlTextQuery {
    param(
        [Parameter(Mandatory = $true)] [string] $Database,
        [Parameter(Mandatory = $true)] [string] $Query
    )

    $normalizedQuery = ($Query -replace "`r?`n", ' ').Trim()
    $escapedQuery = $normalizedQuery.Replace('"', '\"')
    $shellCommand = [string]::Format(
        'if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then SQLCMD=/opt/mssql-tools18/bin/sqlcmd; else SQLCMD=/opt/mssql-tools/bin/sqlcmd; fi; "$SQLCMD" -C -S localhost -U sa -P "$SA_PASSWORD" -d "{0}" -w 65535 -y 0 -Y 0 -Q "SET NOCOUNT ON; {1}"',
        $Database,
        $escapedQuery)

    $output = docker exec orderprocessing-sqlserver /bin/sh -lc $shellCommand 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ([string]::Join([Environment]::NewLine, @($output | ForEach-Object { $_.ToString() }))).Trim()
    }

    return Normalize-SqlOutputLines -Lines @($output | ForEach-Object { $_.ToString() })
}

function Invoke-AzureSqlTextQuery {
    param(
        [Parameter(Mandatory = $true)] [string] $Database,
        [Parameter(Mandatory = $true)] [string] $Query
    )

    Ensure-AzureSqlFirewallAccess
    $azureSqlContext = Get-AzureSqlContext
    $normalizedQuery = ($Query -replace "`r?`n", ' ').Trim()
    $connectionString = "Server=tcp:$($azureSqlContext.SqlServerFqdn),1433;Initial Catalog=$Database;Persist Security Info=False;User ID=$($azureSqlContext.SqlAdminUser);Password=$($azureSqlContext.SqlAdminPassword);Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
    $connection = [System.Data.SqlClient.SqlConnection]::new($connectionString)

    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = "SET NOCOUNT ON; $normalizedQuery"
        $command.CommandTimeout = 60

        $reader = $command.ExecuteReader()
        try {
            if ($reader.FieldCount -le 0) {
                return @()
            }

            $table = [System.Data.DataTable]::new()
            $table.Load($reader)
            return Normalize-SqlOutputLines -Lines @(
                $table.Rows | ForEach-Object {
                    if ($table.Columns.Count -gt 0) {
                        [string] $_[$table.Columns[0].ColumnName]
                    }
                }
            )
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        if ($connection.State -ne [System.Data.ConnectionState]::Closed) {
            $connection.Close()
        }

        $connection.Dispose()
    }
}

function Invoke-SqlTextQuery {
    param(
        [Parameter(Mandatory = $true)] [string] $Database,
        [Parameter(Mandatory = $true)] [string] $Query
    )

    if ($Runtime -eq 'azure') {
        return Invoke-AzureSqlTextQuery -Database $Database -Query $Query
    }

    if ($Runtime -eq 'docker') {
        return Invoke-DockerSqlTextQuery -Database $Database -Query $Query
    }

    return Invoke-LocalSqlTextQuery -Database $Database -Query $Query
}

function Get-ActiveProvider {
    param(
        [Parameter(Mandatory = $true)] [string] $Database,
        [Parameter(Mandatory = $true)] [string] $CurrentTenantCode
    )

    $escapedTenantCode = Escape-SqlLiteral -Value $CurrentTenantCode
    # Phase 8.6 / ADR-019: PaymentProviderCode on Tenants is the authoritative routing field.
    # PaymentProviders.IsActive is no longer used for provider selection.
    $query = @"
SELECT TOP 1 t.PaymentProviderCode
FROM Tenants t
WHERE t.Code = '$escapedTenantCode';
"@

    $rows = @(Invoke-SqlTextQuery -Database $Database -Query $query)
    if ($rows.Count -eq 0 -or [string]::IsNullOrWhiteSpace($rows[0])) {
        return $null
    }

    return [string] $rows[0]
}

function Set-ActiveProvider {
    param(
        [Parameter(Mandatory = $true)] [string] $Database,
        [Parameter(Mandatory = $true)] [string] $CurrentTenantCode,
        [Parameter(Mandatory = $true)] [string] $CurrentProviderType
    )

    $escapedTenantCode = Escape-SqlLiteral -Value $CurrentTenantCode
    $escapedProviderType = Escape-SqlLiteral -Value $CurrentProviderType
    # Phase 8.6 / ADR-019: Update Tenants.PaymentProviderCode — the authoritative routing field.
    # PaymentProviders.IsActive is no longer the switching mechanism.
    $updateQuery = @"
UPDATE Tenants
SET PaymentProviderCode = '$escapedProviderType'
WHERE Code = '$escapedTenantCode';
"@

    [void](Invoke-SqlTextQuery -Database $Database -Query $updateQuery)
}

$database = Get-DatabaseName -CurrentRuntime $Runtime -CurrentEnvironment $Environment
$previousProviderType = Get-ActiveProvider -Database $database -CurrentTenantCode $TenantCode

if ([string]::IsNullOrWhiteSpace($previousProviderType)) {
    throw "No PaymentProviderCode value found for tenant $TenantCode in database $database. Ensure the AddTenantPaymentProviderCode migration has been applied."
}

if ($previousProviderType -ne $ProviderType) {
    Set-ActiveProvider -Database $database -CurrentTenantCode $TenantCode -CurrentProviderType $ProviderType
}

$currentProviderType = Get-ActiveProvider -Database $database -CurrentTenantCode $TenantCode
if ($currentProviderType -ne $ProviderType) {
    throw "Failed to activate provider $ProviderType for tenant $TenantCode in database $database. Current provider is $currentProviderType."
}

$result = [PSCustomObject]@{
    tenantCode = $TenantCode
    database = $database
    previousProviderType = $previousProviderType
    currentProviderType = $currentProviderType
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 5
}
else {
    Write-Output "$TenantCode -> $currentProviderType (previous: $previousProviderType) in $database"
}
