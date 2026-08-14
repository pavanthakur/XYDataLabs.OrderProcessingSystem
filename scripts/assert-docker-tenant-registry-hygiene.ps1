function Get-DockerTenantRegistryRows {
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
WHERE [Status] = N'Active'
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

function Assert-DockerTenantRegistryHygiene {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptName,

        [Parameter(Mandatory = $true)]
        [string]$ConnectionString,

        [Parameter(Mandatory = $true)]
        [string]$SharedDatabaseName,

        [Parameter(Mandatory = $false)]
        [string[]]$SupportedTenantTiers = @('SharedPool', 'Dedicated'),

        [Parameter(Mandatory = $false)]
        [string[]]$SupportedProviders = @('OpenPay', 'Razorpay'),

        [Parameter(Mandatory = $false)]
        [string]$RepairHint = ''
    )

    try {
        $rows = @(Get-DockerTenantRegistryRows -ConnectionString $ConnectionString)
    }
    catch {
        throw "${ScriptName}: Docker tenant registry hygiene failed because '$SharedDatabaseName' could not be queried. $($_.Exception.Message)"
    }

    if ($rows.Count -eq 0) {
        throw "${ScriptName}: Docker tenant registry hygiene failed because '$SharedDatabaseName' returned no active tenants."
    }

    $seenTenants = @{}
    $issues = New-Object 'System.Collections.Generic.List[string]'
    $expectedTenantContracts = @{
        TenantA = [pscustomobject]@{ TenantTier = 'SharedPool'; PaymentProviderCode = 'Razorpay' }
        TenantB = [pscustomobject]@{ TenantTier = 'SharedPool'; PaymentProviderCode = 'Razorpay' }
        TenantC = [pscustomobject]@{ TenantTier = 'Dedicated'; PaymentProviderCode = 'OpenPay' }
    }

    foreach ($row in $rows) {
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
            continue
        }

        if ($expectedTenantContracts.ContainsKey($tenantCode)) {
            $expectedContract = $expectedTenantContracts[$tenantCode]
            if ($tenantTier -ne [string]$expectedContract.TenantTier) {
                $issues.Add("tenant '$tenantCode' has tenant-tier drift '$tenantTier' (expected '$($expectedContract.TenantTier)')")
            }

            if ($providerCode -ne [string]$expectedContract.PaymentProviderCode) {
                $issues.Add("tenant '$tenantCode' has payment-provider drift '$providerCode' (expected '$($expectedContract.PaymentProviderCode)')")
            }
        }
    }

    if ($issues.Count -gt 0) {
        $issuePreview = ($issues | Select-Object -First 8) -join '; '
        $remainingCount = $issues.Count - 8
        if ($remainingCount -gt 0) {
            $issuePreview = "$issuePreview; +$remainingCount more"
        }

        $repairSuffix = if ([string]::IsNullOrWhiteSpace($RepairHint)) { '' } else { " $RepairHint" }
        throw "${ScriptName}: Docker tenant registry hygiene failed for '$SharedDatabaseName'. $issuePreview.$repairSuffix"
    }

    return $rows
}
