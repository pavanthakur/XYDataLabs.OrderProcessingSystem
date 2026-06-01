[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('local', 'docker')]
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

function Get-DatabaseName {
    param(
        [Parameter(Mandatory = $true)] [string] $CurrentRuntime,
        [Parameter(Mandatory = $true)] [string] $CurrentEnvironment,
        [Parameter(Mandatory = $true)] [string] $CurrentTenantCode
    )

    if ($CurrentRuntime -eq 'local') {
        if ($CurrentTenantCode -eq 'TenantC') {
            return 'OrderProcessingSystem_TenantC'
        }

        return 'OrderProcessingSystem_Local'
    }

    $environmentSuffix = switch ($CurrentEnvironment) {
        'dev' { 'Dev' }
        'stg' { 'Stg' }
        'prod' { 'Prod' }
        default { throw "Unsupported environment: $CurrentEnvironment" }
    }

    if ($CurrentTenantCode -eq 'TenantC') {
        return "OrderProcessingSystem_TenantC_$environmentSuffix"
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
                $_ -ne 'ProviderType'
            }
    )
}

function Invoke-LocalSqlTextQuery {
    param(
        [Parameter(Mandatory = $true)] [string] $Database,
        [Parameter(Mandatory = $true)] [string] $Query
    )

    $sqlcmdPath = (Get-Command sqlcmd -ErrorAction Stop).Source
    $normalizedQuery = ($Query -replace "`r?`n", ' ').Trim()
    $output = & $sqlcmdPath -S localhost -E -d $Database -w 65535 -y 0 -Y 0 -Q "SET NOCOUNT ON; $normalizedQuery" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ([string]::Join([Environment]::NewLine, @($output | ForEach-Object { $_.ToString() }))).Trim()
    }

    return Normalize-SqlOutputLines -Lines @($output | ForEach-Object { $_.ToString() })
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

function Invoke-SqlTextQuery {
    param(
        [Parameter(Mandatory = $true)] [string] $Database,
        [Parameter(Mandatory = $true)] [string] $Query
    )

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
    $query = @"
SELECT TOP 1 pp.ProviderType
FROM PaymentProviders pp
INNER JOIN Tenants t ON t.Id = pp.TenantId
WHERE t.Code = '$escapedTenantCode' AND pp.IsActive = 1
ORDER BY pp.ProviderType;
"@

    $rows = @(Invoke-SqlTextQuery -Database $Database -Query $query)
    if ($rows.Count -eq 0) {
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
    $updateQuery = @"
UPDATE pp
SET pp.IsActive = CASE WHEN pp.ProviderType = '$escapedProviderType' THEN 1 ELSE 0 END
FROM PaymentProviders pp
INNER JOIN Tenants t ON t.Id = pp.TenantId
WHERE t.Code = '$escapedTenantCode';
"@

    [void](Invoke-SqlTextQuery -Database $Database -Query $updateQuery)
}

$database = Get-DatabaseName -CurrentRuntime $Runtime -CurrentEnvironment $Environment -CurrentTenantCode $TenantCode
$previousProviderType = Get-ActiveProvider -Database $database -CurrentTenantCode $TenantCode

if ([string]::IsNullOrWhiteSpace($previousProviderType)) {
    throw "No active payment provider row was found for tenant $TenantCode in database $database."
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