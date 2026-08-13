function Get-LocalTenantRegistryRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConnectionString
    )

    $query = @"
SELECT
    [Code] AS TenantCode,
    [Status] AS TenantStatus,
    [TenantTier] AS TenantTier,
    [PaymentProviderCode] AS PaymentProviderCode
FROM [dbo].[Tenants]
ORDER BY [Code];
"@

    $connection = [System.Data.SqlClient.SqlConnection]::new($ConnectionString)
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = $query
        $command.CommandTimeout = 30

        $reader = $command.ExecuteReader()
        $rows = New-Object 'System.Collections.Generic.List[object]'
        while ($reader.Read()) {
            $rows.Add([pscustomobject]@{
                    TenantCode = [string]$reader['TenantCode']
                    TenantStatus = [string]$reader['TenantStatus']
                    TenantTier = [string]$reader['TenantTier']
                    PaymentProviderCode = [string]$reader['PaymentProviderCode']
                })
        }

        return $rows.ToArray()
    }
    finally {
        if ($null -ne $connection) {
            $connection.Dispose()
        }
    }
}

function Invoke-LocalTenantRegistryNonQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConnectionString,

        [Parameter(Mandatory = $true)]
        [string]$Query
    )

    $connection = [System.Data.SqlClient.SqlConnection]::new($ConnectionString)
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        $command.CommandTimeout = 30
        [void]$command.ExecuteNonQuery()
    }
    finally {
        if ($null -ne $connection) {
            $connection.Dispose()
        }
    }
}

function Escape-LocalTenantRegistrySqlLiteral {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    return $Value.Replace("'", "''")
}

function Repair-LocalTenantRegistryBaseline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConnectionString,

        [Parameter(Mandatory = $false)]
        [string]$DatabaseName = 'OrderProcessingSystem_Local'
    )

    $baselineContracts = @(
        [pscustomobject]@{
            TenantCode = 'TenantA'
            Status = 'Active'
            TenantTier = 'SharedPool'
            PaymentProviderCode = 'Razorpay'
        }
        [pscustomobject]@{
            TenantCode = 'TenantB'
            Status = 'Active'
            TenantTier = 'SharedPool'
            PaymentProviderCode = 'Razorpay'
        }
        [pscustomobject]@{
            TenantCode = 'TenantC'
            Status = 'Active'
            TenantTier = 'Dedicated'
            PaymentProviderCode = 'OpenPay'
        }
    )

    $baselineTenantCodesSql = (($baselineContracts | ForEach-Object {
        "N'$((Escape-LocalTenantRegistrySqlLiteral -Value $_.TenantCode))'"
    }) -join ', ')

    $deactivateQuery = @"
UPDATE [dbo].[Tenants]
SET [Status] = N'Decommissioned'
WHERE [Code] NOT IN ($baselineTenantCodesSql)
  AND ISNULL([Status], N'') = N'Active';
"@

    Invoke-LocalTenantRegistryNonQuery -ConnectionString $ConnectionString -Query $deactivateQuery

    foreach ($baselineTenant in $baselineContracts) {
        $tenantCodeSql = Escape-LocalTenantRegistrySqlLiteral -Value $baselineTenant.TenantCode
        $statusSql = Escape-LocalTenantRegistrySqlLiteral -Value $baselineTenant.Status
        $tierSql = Escape-LocalTenantRegistrySqlLiteral -Value $baselineTenant.TenantTier
        $providerSql = Escape-LocalTenantRegistrySqlLiteral -Value $baselineTenant.PaymentProviderCode
        $baselineQuery = @"
UPDATE [dbo].[Tenants]
SET [Status] = N'$statusSql',
    [TenantTier] = N'$tierSql',
    [PaymentProviderCode] = N'$providerSql'
WHERE [Code] = N'$tenantCodeSql';

IF @@ROWCOUNT = 0
BEGIN
    THROW 51000, N'Baseline tenant row missing for $tenantCodeSql in $DatabaseName.', 1;
END;
"@

        Invoke-LocalTenantRegistryNonQuery -ConnectionString $ConnectionString -Query $baselineQuery
    }
}

function Assert-LocalTenantRegistryHygiene {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptName,

        [Parameter(Mandatory = $true)]
        [string]$ConnectionString,

        [Parameter(Mandatory = $false)]
        [string]$DatabaseName = 'OrderProcessingSystem_Local',

        [Parameter(Mandatory = $false)]
        [string[]]$SupportedTenantTiers = @('SharedPool', 'Dedicated'),

        [Parameter(Mandatory = $false)]
        [string[]]$SupportedProviders = @('OpenPay', 'Razorpay'),

        [Parameter(Mandatory = $false)]
        [string]$RepairHint = ''
    )

    try {
        $rows = @(Get-LocalTenantRegistryRows -ConnectionString $ConnectionString)
    }
    catch {
        throw "${ScriptName}: Local tenant registry hygiene failed because '$DatabaseName' could not be queried. $($_.Exception.Message)"
    }

    if ($rows.Count -eq 0) {
        throw "${ScriptName}: Local tenant registry hygiene failed because '$DatabaseName' returned no tenant rows."
    }

    $activeRows = @($rows | Where-Object { $_.TenantStatus -eq 'Active' })
    if ($activeRows.Count -eq 0) {
        throw "${ScriptName}: Local tenant registry hygiene failed because '$DatabaseName' returned no active tenants."
    }

    $seenTenants = @{}
    $issues = New-Object 'System.Collections.Generic.List[string]'

    foreach ($row in $activeRows) {
        $tenantCode = [string]$row.TenantCode
        $tenantStatus = [string]$row.TenantStatus
        $tenantTier = [string]$row.TenantTier
        $providerCode = [string]$row.PaymentProviderCode

        if ([string]::IsNullOrWhiteSpace($tenantCode)) {
            $issues.Add('an active tenant row is missing TenantCode')
            continue
        }

        if ($seenTenants.ContainsKey($tenantCode)) {
            $issues.Add("duplicate active tenant '$tenantCode'")
            continue
        }
        $seenTenants[$tenantCode] = $true

        if ($tenantStatus -ne 'Active') {
            $issues.Add("inactive tenant '$tenantCode' appeared in the active registry result")
        }

        if ([string]::IsNullOrWhiteSpace($tenantTier) -or $SupportedTenantTiers -notcontains $tenantTier) {
            $issues.Add("tenant '$tenantCode' has unsupported TenantTier '$tenantTier'")
        }

        if ([string]::IsNullOrWhiteSpace($providerCode)) {
            $issues.Add("tenant '$tenantCode' has missing paymentProviderCode")
            continue
        }

        if ($SupportedProviders -notcontains $providerCode) {
            $issues.Add("tenant '$tenantCode' has unsupported paymentProviderCode '$providerCode'")
        }
    }

    if ($issues.Count -gt 0) {
        $issuePreview = ($issues | Select-Object -First 8) -join '; '
        $remainingCount = $issues.Count - 8
        if ($remainingCount -gt 0) {
            $issuePreview = "$issuePreview; +$remainingCount more"
        }

        $repairSuffix = if ([string]::IsNullOrWhiteSpace($RepairHint)) { '' } else { " $RepairHint" }
        throw "${ScriptName}: Local tenant registry hygiene failed for '$DatabaseName'. $issuePreview.$repairSuffix"
    }

    return $activeRows
}
