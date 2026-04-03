#Requires -Version 7.0
<#!
.SYNOPSIS
    Verifies an Azure payment run end to end across App Insights and Azure SQL.

.DESCRIPTION
    Queries API and UI traces from Application Insights, resolves a logical run prefix,
    reads the payment state from the shared and TenantC dedicated Azure SQL databases,
    and emits a consolidated pass/fail report.

    This script is the deterministic Azure rerun path for the manual
    /XYDataLabs-verify-db-logs prompt flow.

.PARAMETER Environment
    Target environment. Supported values: dev, stg, prod.

.PARAMETER RunPrefix
    Optional logical run prefix such as OR-1-2ndApr. If omitted and exactly one
    prefix is found in today's API traces, that prefix is used automatically.

.PARAMETER OutputFormat
    Human-readable table output or JSON.

.PARAMETER SkipFirewallOpen
    Skip calling open-local-sql-firewall.ps1 before SQL queries.

.EXAMPLE
    .\scripts\verify-payment-run-azure.ps1 -Environment dev

.EXAMPLE
    .\scripts\verify-payment-run-azure.ps1 -Environment dev -RunPrefix OR-1-2ndApr

.EXAMPLE
    .\scripts\verify-payment-run-azure.ps1 -Environment dev -OutputFormat Json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('dev', 'stg', 'prod')]
    [string] $Environment = 'dev',

    [Parameter(Mandatory = $false)]
    [string] $RunPrefix,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Table', 'Json')]
    [string] $OutputFormat = 'Table',

    [Parameter(Mandatory = $false)]
    [switch] $SkipFirewallOpen
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$envSuffix = $Environment
$resourceGroup = "rg-orderprocessing-$envSuffix"
$appInsightsName = "ai-orderprocessing-$envSuffix"
$keyVaultName = "kv-orderprocessing-$envSuffix"
$sqlServerName = "orderprocessing-sql-$envSuffix"
$sqlServerFqdn = "$sqlServerName.database.windows.net"
$sharedDbName = switch ($Environment) {
    'dev' { 'OrderProcessingSystem_Dev' }
    'stg' { 'OrderProcessingSystem_Staging' }
    'prod' { 'OrderProcessingSystem_Prod' }
}
$tenantCDbName = switch ($Environment) {
    'dev' { 'OrderProcessingSystem_TenantC_Dev' }
    'stg' { 'OrderProcessingSystem_TenantC_Staging' }
    'prod' { 'OrderProcessingSystem_TenantC_Prod' }
}

function Write-Step {
    param([string] $Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Get-ObjectPropertyValue {
    param(
        [Parameter(Mandatory = $false)]
        [object] $Object,

        [Parameter(Mandatory = $true)]
        [string] $PropertyName
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$PropertyName]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Convert-DynamicJsonValue {
    param([Parameter(Mandatory = $false)] [object] $Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [string]) {
        try {
            return $Value | ConvertFrom-Json
        }
        catch {
            return $null
        }
    }

    return $Value
}

function Get-RegexValue {
    param(
        [Parameter(Mandatory = $true)]
        [string] $InputText,

        [Parameter(Mandatory = $true)]
        [string[]] $Patterns
    )

    foreach ($pattern in $Patterns) {
        if ($InputText -match $pattern) {
            return $Matches[1]
        }
    }

    return ''
}

function Convert-AppInsightsRows {
    param([Parameter(Mandatory = $true)] [object] $Response)

    if ($null -eq $Response.tables -or $Response.tables.Count -eq 0) {
        return @()
    }

    $table = $Response.tables[0]
    $columnNames = @($table.columns | ForEach-Object { [string] $_.name })
    $rows = @()

    foreach ($row in $table.rows) {
        $item = [ordered] @{}
        for ($index = 0; $index -lt $columnNames.Count; $index++) {
            $item[$columnNames[$index]] = if ($index -lt $row.Count) { $row[$index] } else { $null }
        }

        $rows += [PSCustomObject] $item
    }

    return $rows
}

function Invoke-AppInsightsQuery {
    param([Parameter(Mandatory = $true)] [string] $Query)

    # Collapse multi-line KQL to a single line before passing to az.
    # PowerShell 7.4+ 'Windows' native argument passing mode mangles
    # multi-line string arguments, causing az to ignore the KQL entirely.
    $normalizedQuery = ($Query -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ' '

    $raw = az monitor app-insights query `
        --app $appInsightsName `
        --resource-group $resourceGroup `
        --analytics-query $normalizedQuery `
        --output json

    if (-not $raw) {
        throw "App Insights query returned no response."
    }

    return $raw | ConvertFrom-Json
}

function Invoke-AzureSqlQuery {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Database,

        [Parameter(Mandatory = $true)]
        [string] $Query,

        [Parameter(Mandatory = $true)]
        [string] $UserName,

        [Parameter(Mandatory = $true)]
        [string] $Password
    )

    $connectionString = "Server=tcp:$sqlServerFqdn,1433;Initial Catalog=$Database;Persist Security Info=False;User ID=$UserName;Password=$Password;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
    $connection = [System.Data.SqlClient.SqlConnection]::new($connectionString)

    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        $command.CommandTimeout = 60

        $reader = $command.ExecuteReader()
        $table = [System.Data.DataTable]::new()
        $table.Load($reader)

        $results = foreach ($dataRow in $table.Rows) {
            $row = [ordered] @{}
            foreach ($column in $table.Columns) {
                $row[$column.ColumnName] = $dataRow[$column.ColumnName]
            }

            [PSCustomObject] $row
        }

        return @($results)
    }
    finally {
        if ($connection.State -ne [System.Data.ConnectionState]::Closed) {
            $connection.Close()
        }
        $connection.Dispose()
    }
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
                $value = [string] (Get-ObjectPropertyValue -Object $response -PropertyName 'ip')
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

function Get-KqlQuotedValues {
    param([Parameter(Mandatory = $false)] [string[]] $Values)

    $normalizedValues = @(
        $Values |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )

    if ($normalizedValues.Count -eq 0) {
        return ''
    }

    return ($normalizedValues | ForEach-Object { "'{0}'" -f $_.Replace("'", "''") }) -join ', '
}

function Ensure-AzureSqlFirewallAccess {
    $ruleName = "$Environment-machine"
    $publicIp = Get-PublicIpAddress

    az sql server firewall-rule create `
        --resource-group $resourceGroup `
        --server $sqlServerName `
        --name $ruleName `
        --start-ip-address $publicIp `
        --end-ip-address $publicIp | Out-Null

    Write-Host "Azure SQL firewall open for $publicIp via rule $ruleName." -ForegroundColor Green
}

function Get-MinimumTimeDeltaSeconds {
    param(
        [Parameter(Mandatory = $true)]
        [datetimeoffset] $CandidateTimestamp,

        [Parameter(Mandatory = $true)]
        [datetimeoffset[]] $ReferenceTimestamps
    )

    if ($ReferenceTimestamps.Count -eq 0) {
        return [double]::PositiveInfinity
    }

    $minimum = [double]::PositiveInfinity
    foreach ($referenceTimestamp in $ReferenceTimestamps) {
        $deltaSeconds = [math]::Abs(($CandidateTimestamp - $referenceTimestamp).TotalSeconds)
        if ($deltaSeconds -lt $minimum) {
            $minimum = $deltaSeconds
        }
    }

    return $minimum
}

function Get-ScopedUiEvents {
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]] $Events,

        [Parameter(Mandatory = $false)]
        [string[]] $KnownChargeIds = @(),

        [Parameter(Mandatory = $false)]
        [string[]] $KnownTenants = @(),

        [Parameter(Mandatory = $false)]
        [string[]] $KnownCustomerOrders = @()
    )

    if ($null -eq $Events -or $Events.Count -eq 0) {
        return @()
    }

    return @(
        $Events |
            Where-Object {
                ($_.ChargeId -and ($KnownChargeIds -contains $_.ChargeId)) -or
                ($_.Tenant -and ($KnownTenants -contains $_.Tenant)) -or
                ($_.CustomerOrderId -and ($KnownCustomerOrders -contains $_.CustomerOrderId))
            } |
            Sort-Object Timestamp
    )
}

function Convert-CheckResult {
    param(
        [Parameter(Mandatory = $true)] [string] $Expected,
        [Parameter(Mandatory = $true)] [string] $Actual,
        [Parameter(Mandatory = $true)]
        [ValidateSet('PASS', 'FAIL', 'INCONCLUSIVE')]
        [string] $Outcome
    )

    [PSCustomObject] @{
        Expected = $Expected
        Actual = $Actual
        Outcome = $Outcome
    }
}

Write-Step "Resolving Azure resources and credentials for $Environment"
$sqlAdminUser = az sql server show --name $sqlServerName --resource-group $resourceGroup --query administratorLogin -o tsv
$sqlAdminPassword = az keyvault secret show --vault-name $keyVaultName --name sql-admin-password --query value -o tsv

if ([string]::IsNullOrWhiteSpace($sqlAdminUser)) {
    throw "Failed to resolve SQL administrator login for $sqlServerName."
}

if ([string]::IsNullOrWhiteSpace($sqlAdminPassword)) {
    throw "Failed to resolve sql-admin-password from $keyVaultName."
}

if (-not $SkipFirewallOpen) {
    Write-Step "Opening Azure SQL firewall access"
    Ensure-AzureSqlFirewallAccess
}

Write-Step "Querying App Insights API traces"
$apiQuery = @"
traces
| where timestamp >= startofday(now() + 330m) - 330m
| where message has_any('Generated payment attempt order id',
                        'Charge created with ID',
                        'Payment callback reconciliation completed',
                        'confirm-status responded')
| extend application = tostring(customDimensions['Application'])
| extend tenant = tostring(customDimensions['TenantCode'])
| extend customerOrderId = coalesce(tostring(customDimensions['CustomerOrderId']), extract(@'customer order id\s+(\S+)', 1, message), extract(@'customer order\s+(\S+)', 1, message))
| extend runPrefix = extract(@'^(OR-\d+-[^-]+)', 1, customerOrderId)
| extend chargeId = coalesce(tostring(customDimensions['ChargeId']), extract(@'Charge created with ID:\s+(\S+)', 1, message), extract(@'payment\s+(\S+)\. Status', 1, message), extract(@'/payments/(\S+)/confirm-status', 1, message))
| where cloud_RoleName has 'api' or application == 'API'
| project timestamp, tenant, customerOrderId, runPrefix, chargeId, message
| order by timestamp asc
"@

$apiRows = Convert-AppInsightsRows -Response (Invoke-AppInsightsQuery -Query $apiQuery)
$apiEvents = foreach ($row in $apiRows) {
    [PSCustomObject] @{
        Timestamp = [datetimeoffset] $row.timestamp
        Tenant = [string] $row.tenant
        CustomerOrderId = [string] $row.customerOrderId
        RunPrefix = [string] $row.runPrefix
        ChargeId = [string] $row.chargeId
        Message = [string] $row.message
    }
}

$apiEvents = @($apiEvents | Sort-Object Timestamp)

$tenantState = @{}
$resolvedApiEvents = foreach ($event in $apiEvents) {
    $resolvedCustomerOrderId = $event.CustomerOrderId
    $resolvedRunPrefix = $event.RunPrefix

    if (-not [string]::IsNullOrWhiteSpace($event.Tenant)) {
        if (-not [string]::IsNullOrWhiteSpace($event.CustomerOrderId)) {
            $tenantState[$event.Tenant] = [PSCustomObject] @{
                CustomerOrderId = $event.CustomerOrderId
                RunPrefix = $event.RunPrefix
            }
        }
        elseif ($tenantState.ContainsKey($event.Tenant)) {
            $resolvedCustomerOrderId = $tenantState[$event.Tenant].CustomerOrderId
            $resolvedRunPrefix = $tenantState[$event.Tenant].RunPrefix
        }
    }

    [PSCustomObject] @{
        Timestamp = $event.Timestamp
        Tenant = $event.Tenant
        CustomerOrderId = $event.CustomerOrderId
        ResolvedCustomerOrderId = $resolvedCustomerOrderId
        RunPrefix = $event.RunPrefix
        ResolvedRunPrefix = $resolvedRunPrefix
        ChargeId = $event.ChargeId
        Message = $event.Message
    }
}

$availableRunPrefixes = @($resolvedApiEvents | Where-Object { -not [string]::IsNullOrWhiteSpace($_.ResolvedRunPrefix) } | Select-Object -ExpandProperty ResolvedRunPrefix -Unique)
$appInsightsAvailable = ($availableRunPrefixes.Count -gt 0)

$selectedRunPrefix = $RunPrefix
if ([string]::IsNullOrWhiteSpace($selectedRunPrefix)) {
    if ($availableRunPrefixes.Count -eq 1) {
        $selectedRunPrefix = $availableRunPrefixes[0]
    }
    elseif ($availableRunPrefixes.Count -gt 1) {
        $prefixList = ($availableRunPrefixes | ForEach-Object { "- $_" }) -join "`n"
        throw "Multiple run prefixes were found. Re-run with -RunPrefix.`n$prefixList"
    }
    else {
        throw "No payment run prefixes were found in today's API traces for $Environment. Re-run with -RunPrefix to force a DB-only verification pass."
    }
}

if ($availableRunPrefixes.Count -gt 0 -and $availableRunPrefixes -notcontains $selectedRunPrefix) {
    $prefixList = ($availableRunPrefixes | ForEach-Object { "- $_" }) -join "`n"
    throw "Run prefix '$selectedRunPrefix' was not found in today's API traces.`n$prefixList"
}

$selectedApiEvents = @($resolvedApiEvents | Where-Object { $_.ResolvedRunPrefix -eq $selectedRunPrefix })
$apiChargeEvents = @(
    $selectedApiEvents |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.ChargeId) } |
        Group-Object ChargeId |
        ForEach-Object {
            $preferred = $_.Group | Where-Object { $_.Message -match '^Charge created with ID:' } | Select-Object -First 1
            if ($null -ne $preferred) {
                return $preferred
            }

            $_.Group | Select-Object -First 1
        } |
        Sort-Object Timestamp
)

Write-Step "Querying App Insights UI traces"
$uiQuery = @"
traces
| where timestamp >= startofday(now() + 330m) - 330m
| where message has_any('OpenPay callback received',
                        'payment/callback responded',
                        'ui_payment_callback_confirmation_requested',
                        'ui_payment_callback_confirmed',
                        'ui_payment_callback_confirmation_failed')
| extend application = tostring(customDimensions['Application'])
| extend tenant = coalesce(tostring(customDimensions['TenantCode']), extract(@'for tenant\s+([^,\s]+)', 1, message))
| extend customerOrderId = tostring(customDimensions['CustomerOrderId'])
| extend uiEventName = coalesce(tostring(customDimensions['UiEventName']), extract(@'UI payment event\s+(\S+)\s+on', 1, message))
| extend chargeId = coalesce(tostring(customDimensions['ChargeId']), tostring(customDimensions['PaymentId']), extract(@'for payment\s+([^,\s]+)', 1, message), extract(@'payment\s+([^,\s]+)', 1, message))
| extend statusCode = tostring(customDimensions['StatusCode'])
| where cloud_RoleName has 'ui' or application == 'UI'
| project timestamp, tenant, customerOrderId, uiEventName, chargeId, statusCode, message
| order by timestamp asc
"@

$uiRows = Convert-AppInsightsRows -Response (Invoke-AppInsightsQuery -Query $uiQuery)
$uiEvents = @(
foreach ($row in $uiRows) {
    [PSCustomObject] @{
        Timestamp = [datetimeoffset] $row.timestamp
        Tenant = [string] $row.tenant
        CustomerOrderId = [string] $row.customerOrderId
        UiEventName = [string] $row.uiEventName
        ChargeId = [string] $row.chargeId
        StatusCode = [string] $row.statusCode
        Message = [string] $row.message
        EventKey = "{0}|{1}|{2}|{3}|{4}|{5}" -f [string] $row.timestamp, [string] $row.chargeId, [string] $row.tenant, [string] $row.customerOrderId, [string] $row.uiEventName, [string] $row.message
    }
}
)

Write-Step "Querying Azure SQL"
$preflightShared = Invoke-AzureSqlQuery -Database $sharedDbName -UserName $sqlAdminUser -Password $sqlAdminPassword -Query @"
SELECT t.Code AS Tenant, pp.Use3DSecure AS ThreeDSEnabled
FROM dbo.PaymentProviders pp
JOIN dbo.Tenants t ON t.Id = pp.TenantId
ORDER BY pp.TenantId;
"@

$preflightTenantC = Invoke-AzureSqlQuery -Database $tenantCDbName -UserName $sqlAdminUser -Password $sqlAdminPassword -Query @"
SELECT pp.TenantId, pp.Use3DSecure AS ThreeDSEnabled
FROM dbo.PaymentProviders pp;
"@

$q2Shared = Invoke-AzureSqlQuery -Database $sharedDbName -UserName $sqlAdminUser -Password $sqlAdminPassword -Query @"
SELECT t.Code AS Tenant, ct.CustomerOrderId, ct.TransactionId AS ChargeId,
       ct.TransactionStatus AS Status, ct.IsThreeDSecureEnabled AS ThreeDS,
       ct.ThreeDSecureStage, ct.TransactionReferenceId AS Ref,
       ct.IsTransactionSuccess AS OK, ct.CreatedDate
FROM dbo.CardTransactions ct
JOIN dbo.Tenants t ON t.Id = ct.TenantId
WHERE ct.CustomerOrderId LIKE '$selectedRunPrefix%'
ORDER BY ct.TenantId, ct.CustomerOrderId, ct.Id;
"@

$q5Shared = Invoke-AzureSqlQuery -Database $sharedDbName -UserName $sqlAdminUser -Password $sqlAdminPassword -Query @"
SELECT t.Code AS Tenant, ct.CustomerOrderId, tsh.Status,
       tsh.ThreeDSecureStage AS Stage, tsh.IsThreeDSecureEnabled AS ThreeDS,
       tsh.TransactionReferenceId AS Ref
FROM dbo.TransactionStatusHistories tsh
JOIN dbo.CardTransactions ct ON ct.Id = tsh.TransactionId
JOIN dbo.Tenants t ON t.Id = ct.TenantId
WHERE ct.CustomerOrderId LIKE '$selectedRunPrefix%'
ORDER BY ct.TenantId, ct.CustomerOrderId, ct.Id, tsh.Id;
"@

$q8Shared = Invoke-AzureSqlQuery -Database $sharedDbName -UserName $sqlAdminUser -Password $sqlAdminPassword -Query @"
SELECT ct.CustomerOrderId, ct.TenantId, t.Code
FROM dbo.CardTransactions ct
JOIN dbo.Tenants t ON t.Id = ct.TenantId
WHERE ct.CustomerOrderId LIKE '$selectedRunPrefix%'
  AND ((ct.CustomerOrderId LIKE '%-tA-%' AND ct.TenantId <> 1)
    OR (ct.CustomerOrderId LIKE '%-tB-%' AND ct.TenantId <> 2));
"@

$q2TenantC = Invoke-AzureSqlQuery -Database $tenantCDbName -UserName $sqlAdminUser -Password $sqlAdminPassword -Query @"
SELECT ct.CustomerOrderId, ct.TransactionId AS ChargeId,
       ct.TransactionStatus AS Status, ct.IsThreeDSecureEnabled AS ThreeDS,
       ct.ThreeDSecureStage, ct.TransactionReferenceId AS Ref,
       ct.IsTransactionSuccess AS OK, ct.CreatedDate
FROM dbo.CardTransactions ct
WHERE ct.TenantId = 3
  AND ct.CustomerOrderId LIKE '$selectedRunPrefix%'
ORDER BY ct.CustomerOrderId, ct.Id;
"@

$q5TenantC = Invoke-AzureSqlQuery -Database $tenantCDbName -UserName $sqlAdminUser -Password $sqlAdminPassword -Query @"
SELECT ct.CustomerOrderId, tsh.Status, tsh.ThreeDSecureStage AS Stage,
       tsh.IsThreeDSecureEnabled AS ThreeDS, tsh.TransactionReferenceId AS Ref
FROM dbo.TransactionStatusHistories tsh
JOIN dbo.CardTransactions ct ON ct.Id = tsh.TransactionId
WHERE ct.TenantId = 3
  AND ct.CustomerOrderId LIKE '$selectedRunPrefix%'
ORDER BY ct.CustomerOrderId, ct.Id, tsh.Id;
"@

$q9Shared = Invoke-AzureSqlQuery -Database $sharedDbName -UserName $sqlAdminUser -Password $sqlAdminPassword -Query @"
SELECT ct.CustomerOrderId, ct.TenantId
FROM dbo.CardTransactions ct
WHERE ct.TenantId = 3
  AND ct.CustomerOrderId LIKE '$selectedRunPrefix%';
"@

$threeDsByTenant = @{}
foreach ($row in $preflightShared) {
    $threeDsByTenant[[string] $row.Tenant] = [int] $row.ThreeDSEnabled
}
$threeDsByTenant['TenantC'] = [int] (($preflightTenantC | Select-Object -First 1).ThreeDSEnabled)

$expectedOrdersByTenant = @{}
foreach ($tenantGroup in ($selectedApiEvents | Where-Object { -not [string]::IsNullOrWhiteSpace($_.ResolvedCustomerOrderId) } | Group-Object Tenant)) {
    $expectedOrdersByTenant[$tenantGroup.Name] = @($tenantGroup.Group | Select-Object -ExpandProperty ResolvedCustomerOrderId -Unique)
}

if ($expectedOrdersByTenant.Count -eq 0) {
    $sharedOrdersByTenant = $q2Shared | Group-Object Tenant
    foreach ($tenantGroup in $sharedOrdersByTenant) {
        $expectedOrdersByTenant[$tenantGroup.Name] = @($tenantGroup.Group | Select-Object -ExpandProperty CustomerOrderId -Unique)
    }

    $tenantCOrders = @($q2TenantC | Select-Object -ExpandProperty CustomerOrderId -Unique)
    if ($tenantCOrders.Count -gt 0) {
        $expectedOrdersByTenant['TenantC'] = $tenantCOrders
    }
}

$sharedDbChargeIds = @($q2Shared | Select-Object -ExpandProperty ChargeId)
$tenantCDbChargeIds = @($q2TenantC | Select-Object -ExpandProperty ChargeId)
$allDbChargeIds = @($sharedDbChargeIds + $tenantCDbChargeIds)
$expectedUiTenants = @($expectedOrdersByTenant.Keys | Sort-Object -Unique)
$expectedUiCustomerOrders = @(
    foreach ($tenantName in $expectedOrdersByTenant.Keys) {
        foreach ($customerOrderId in @($expectedOrdersByTenant[$tenantName])) {
            [string] $customerOrderId
        }
    }
)
$expectedUiCustomerOrders = @($expectedUiCustomerOrders | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)

if (@($apiChargeEvents).Count -eq 0 -and @($allDbChargeIds).Count -gt 0) {
    $dbChargeIdList = Get-KqlQuotedValues -Values $allDbChargeIds
    if (-not [string]::IsNullOrWhiteSpace($dbChargeIdList)) {
        $fallbackApiQuery = @"
traces
| where timestamp >= ago(7d)
| where message has_any('Generated payment attempt order id',
                        'Charge created with ID',
                        'Payment callback reconciliation completed',
                        'confirm-status responded')
| extend application = tostring(customDimensions['Application'])
| extend tenant = tostring(customDimensions['TenantCode'])
| extend customerOrderId = coalesce(tostring(customDimensions['CustomerOrderId']), extract(@'customer order id\s+(\S+)', 1, message), extract(@'customer order\s+(\S+)', 1, message))
| extend runPrefix = extract(@'^(OR-\d+-[^-]+)', 1, customerOrderId)
| extend chargeId = coalesce(tostring(customDimensions['ChargeId']), extract(@'Charge created with ID:\s+(\S+)', 1, message), extract(@'payment\s+(\S+)\. Status', 1, message), extract(@'/payments/(\S+)/confirm-status', 1, message))
| where cloud_RoleName has 'api' or application == 'API'
| where chargeId in ($dbChargeIdList)
| project timestamp, tenant, customerOrderId, runPrefix, chargeId, message
| order by timestamp asc
"@

        $fallbackApiRows = Convert-AppInsightsRows -Response (Invoke-AppInsightsQuery -Query $fallbackApiQuery)
        $fallbackApiEvents = @(
            foreach ($row in $fallbackApiRows) {
                [PSCustomObject] @{
                    Timestamp = [datetimeoffset] $row.timestamp
                    Tenant = [string] $row.tenant
                    CustomerOrderId = [string] $row.customerOrderId
                    ResolvedCustomerOrderId = [string] $row.customerOrderId
                    RunPrefix = [string] $row.runPrefix
                    ResolvedRunPrefix = [string] $row.runPrefix
                    ChargeId = [string] $row.chargeId
                    Message = [string] $row.message
                }
            }
        )

        if ($fallbackApiEvents.Count -gt 0) {
            $selectedApiEvents = @(
                $fallbackApiEvents |
                    Where-Object {
                        $_.ResolvedRunPrefix -eq $selectedRunPrefix -or
                        $_.ResolvedCustomerOrderId -like "$selectedRunPrefix*" -or
                        ($allDbChargeIds -contains $_.ChargeId)
                    } |
                    Sort-Object Timestamp
            )

            if ($selectedApiEvents.Count -eq 0) {
                $selectedApiEvents = @($fallbackApiEvents | Sort-Object Timestamp)
            }

            $apiChargeEvents = @(
                $selectedApiEvents |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_.ChargeId) } |
                    Group-Object ChargeId |
                    ForEach-Object {
                        $preferred = $_.Group | Where-Object { $_.Message -match '^Charge created with ID:' } | Select-Object -First 1
                        if ($null -ne $preferred) {
                            return $preferred
                        }

                        $_.Group | Select-Object -First 1
                    } |
                    Sort-Object Timestamp
            )
        }
    }
}

$apiChargeIds = @($apiChargeEvents | Select-Object -ExpandProperty ChargeId -Unique)
$knownUiChargeIds = @($apiChargeIds + $allDbChargeIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
$selectedUiEvents = @(Get-ScopedUiEvents -Events @($uiEvents) -KnownChargeIds $knownUiChargeIds -KnownTenants $expectedUiTenants -KnownCustomerOrders $expectedUiCustomerOrders)

if ($selectedUiEvents.Count -eq 0) {
    $evidenceChargeIds = if ($apiChargeIds.Count -gt 0) { $apiChargeIds } else { @($allDbChargeIds | Sort-Object -Unique) }
    $evidenceChargeIdList = Get-KqlQuotedValues -Values $evidenceChargeIds
    if (-not [string]::IsNullOrWhiteSpace($evidenceChargeIdList)) {
        $fallbackUiQuery = @"
traces
| where timestamp >= ago(7d)
| where message has_any('OpenPay callback received',
                        'payment/callback responded',
                        'ui_payment_callback_confirmation_requested',
                        'ui_payment_callback_confirmed',
                        'ui_payment_callback_confirmation_failed')
| extend application = tostring(customDimensions['Application'])
| extend tenant = coalesce(tostring(customDimensions['TenantCode']), extract(@'for tenant\s+([^,\s]+)', 1, message))
| extend customerOrderId = tostring(customDimensions['CustomerOrderId'])
| extend uiEventName = coalesce(tostring(customDimensions['UiEventName']), extract(@'UI payment event\s+(\S+)\s+on', 1, message))
| extend chargeId = coalesce(tostring(customDimensions['ChargeId']), tostring(customDimensions['PaymentId']), extract(@'for payment\s+([^,\s]+)', 1, message), extract(@'payment\s+([^,\s]+)', 1, message))
| extend statusCode = tostring(customDimensions['StatusCode'])
| where cloud_RoleName has 'ui' or application == 'UI'
| where chargeId in ($evidenceChargeIdList)
   or tenant in ({0})
| project timestamp, tenant, customerOrderId, uiEventName, chargeId, statusCode, message
| order by timestamp asc
"@ -f (Get-KqlQuotedValues -Values $expectedUiTenants)

        $fallbackUiRows = Convert-AppInsightsRows -Response (Invoke-AppInsightsQuery -Query $fallbackUiQuery)
        $fallbackUiEvents = @(
            foreach ($row in $fallbackUiRows) {
                [PSCustomObject] @{
                    Timestamp = [datetimeoffset] $row.timestamp
                    Tenant = [string] $row.tenant
                    CustomerOrderId = [string] $row.customerOrderId
                    UiEventName = [string] $row.uiEventName
                    ChargeId = [string] $row.chargeId
                    StatusCode = [string] $row.statusCode
                    Message = [string] $row.message
                    EventKey = "{0}|{1}|{2}|{3}|{4}|{5}" -f [string] $row.timestamp, [string] $row.chargeId, [string] $row.tenant, [string] $row.customerOrderId, [string] $row.uiEventName, [string] $row.message
                }
            }
        )

        $selectedUiEvents = @(Get-ScopedUiEvents -Events @($fallbackUiEvents) -KnownChargeIds $knownUiChargeIds -KnownTenants $expectedUiTenants -KnownCustomerOrders $expectedUiCustomerOrders)
    }
}

if ($selectedApiEvents.Count -gt 0 -or $selectedUiEvents.Count -gt 0) {
    $appInsightsAvailable = $true
}

$globalUiStatusCodes = @($selectedUiEvents | Where-Object { -not [string]::IsNullOrWhiteSpace($_.StatusCode) } | Select-Object -ExpandProperty StatusCode -Unique)
$matchedUiEventKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$usedFallbackUiEventKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

$chargeCorrelation = @(
foreach ($chargeEvent in $apiChargeEvents) {
    $uiMatches = @($selectedUiEvents | Where-Object { $_.ChargeId -eq $chargeEvent.ChargeId })
    foreach ($uiMatch in $uiMatches) {
        $null = $matchedUiEventKeys.Add($uiMatch.EventKey)
    }

    $uiCorrelationMode = if ($uiMatches.Count -gt 0) { 'chargeId' } else { 'none' }

    if ($uiMatches.Count -eq 0 -and $threeDsByTenant[$chargeEvent.Tenant] -eq 1) {
        $candidateApiEvents = @(
            $selectedApiEvents |
                Where-Object {
                    ($_.ChargeId -eq $chargeEvent.ChargeId) -or
                    ($_.Tenant -eq $chargeEvent.Tenant -and $_.ResolvedCustomerOrderId -eq $chargeEvent.ResolvedCustomerOrderId)
                }
        )

        $referenceTimestamps = @(
            $candidateApiEvents |
                Where-Object { $_.Message -match 'Payment callback reconciliation completed|confirm-status responded' } |
                Select-Object -ExpandProperty Timestamp
        )

        if ($referenceTimestamps.Count -eq 0) {
            $referenceTimestamps = @($candidateApiEvents | Select-Object -ExpandProperty Timestamp)
        }

        if ($referenceTimestamps.Count -eq 0) {
            $referenceTimestamps = @($chargeEvent.Timestamp)
        }

        $fallbackMatch = @(
            $selectedUiEvents |
                Where-Object {
                    -not $usedFallbackUiEventKeys.Contains($_.EventKey) -and
                    [string]::IsNullOrWhiteSpace($_.ChargeId) -and
                    (
                        ($_.Tenant -eq $chargeEvent.Tenant) -or
                        (
                            -not [string]::IsNullOrWhiteSpace($_.CustomerOrderId) -and
                            $_.CustomerOrderId -eq $chargeEvent.ResolvedCustomerOrderId
                        )
                    )
                } |
                ForEach-Object {
                    [PSCustomObject] @{
                        UiEvent = $_
                        DeltaSeconds = Get-MinimumTimeDeltaSeconds -CandidateTimestamp $_.Timestamp -ReferenceTimestamps $referenceTimestamps
                    }
                } |
                Where-Object { $_.DeltaSeconds -le 600 } |
                Sort-Object DeltaSeconds, @{ Expression = { $_.UiEvent.Timestamp } } |
                Select-Object -First 1
            )

        if ($fallbackMatch.Count -gt 0 -and $null -ne $fallbackMatch[0]) {
            $uiMatches = @($fallbackMatch[0].UiEvent)
            $uiCorrelationMode = 'tenant+time'
            $null = $usedFallbackUiEventKeys.Add($fallbackMatch[0].UiEvent.EventKey)
            $null = $matchedUiEventKeys.Add($fallbackMatch[0].UiEvent.EventKey)
        }
    }

    $uiStatusCodes = @($uiMatches | Where-Object { -not [string]::IsNullOrWhiteSpace($_.StatusCode) } | Select-Object -ExpandProperty StatusCode -Unique)
    $uiEventNames = @($uiMatches | Where-Object { -not [string]::IsNullOrWhiteSpace($_.UiEventName) } | Select-Object -ExpandProperty UiEventName -Unique)

    if ($uiStatusCodes.Count -eq 0 -and $globalUiStatusCodes.Count -gt 0 -and $apiChargeEvents.Count -eq 1) {
        $uiStatusCodes = $globalUiStatusCodes
    }

    [PSCustomObject] @{
        ChargeId = $chargeEvent.ChargeId
        Tenant = $chargeEvent.Tenant
        CustomerOrderId = $chargeEvent.ResolvedCustomerOrderId
        InDb = ($allDbChargeIds -contains $chargeEvent.ChargeId)
        DbStatus = if ($chargeEvent.Tenant -eq 'TenantC') {
            (($q2TenantC | Where-Object { $_.ChargeId -eq $chargeEvent.ChargeId } | Select-Object -First 1).Status)
        }
        else {
            (($q2Shared | Where-Object { $_.ChargeId -eq $chargeEvent.ChargeId } | Select-Object -First 1).Status)
        }
        DbStage = if ($chargeEvent.Tenant -eq 'TenantC') {
            (($q2TenantC | Where-Object { $_.ChargeId -eq $chargeEvent.ChargeId } | Select-Object -First 1).ThreeDSecureStage)
        }
        else {
            (($q2Shared | Where-Object { $_.ChargeId -eq $chargeEvent.ChargeId } | Select-Object -First 1).ThreeDSecureStage)
        }
        ThreeDSEnabled = $threeDsByTenant[$chargeEvent.Tenant]
        UiCallbackExpected = ($threeDsByTenant[$chargeEvent.Tenant] -eq 1)
        UiCallbackLogged = ($uiMatches.Count -gt 0)
        UiCorrelationMode = $uiCorrelationMode
        UiEventNames = @($uiEventNames)
        UiStatusCodes = @($uiStatusCodes)
    }
}
)

$reportedUiEvents = if ($matchedUiEventKeys.Count -gt 0) {
    @($selectedUiEvents | Where-Object { $matchedUiEventKeys.Contains($_.EventKey) } | Sort-Object Timestamp)
}
else {
    @($selectedUiEvents)
}

$expectedTenantARows = if ($expectedOrdersByTenant.ContainsKey('TenantA')) { $expectedOrdersByTenant['TenantA'].Count * 2 } else { 0 }
$expectedTenantBRows = if ($expectedOrdersByTenant.ContainsKey('TenantB')) { $expectedOrdersByTenant['TenantB'].Count * 2 } else { 0 }
$expectedTenantCRows = if ($expectedOrdersByTenant.ContainsKey('TenantC')) { $expectedOrdersByTenant['TenantC'].Count * 2 } else { 0 }
$expectedTenantASteps = if ($expectedOrdersByTenant.ContainsKey('TenantA')) { $expectedOrdersByTenant['TenantA'].Count * ($(if ($threeDsByTenant['TenantA'] -eq 1) { 4 } else { 2 })) } else { 0 }
$expectedTenantBSteps = if ($expectedOrdersByTenant.ContainsKey('TenantB')) { $expectedOrdersByTenant['TenantB'].Count * ($(if ($threeDsByTenant['TenantB'] -eq 1) { 4 } else { 2 })) } else { 0 }
$expectedTenantCSteps = if ($expectedOrdersByTenant.ContainsKey('TenantC')) { $expectedOrdersByTenant['TenantC'].Count * ($(if ($threeDsByTenant['TenantC'] -eq 1) { 4 } else { 2 })) } else { 0 }

$checks = [ordered] @{}
$checks['Pre-flight TenantA 3DS'] = Convert-CheckResult -Expected 'configured' -Actual ([string] $threeDsByTenant['TenantA']) -Outcome $(if ($null -ne $threeDsByTenant['TenantA']) { 'PASS' } else { 'FAIL' })
$checks['Pre-flight TenantB 3DS'] = Convert-CheckResult -Expected 'configured' -Actual ([string] $threeDsByTenant['TenantB']) -Outcome $(if ($null -ne $threeDsByTenant['TenantB']) { 'PASS' } else { 'FAIL' })
$checks['Pre-flight TenantC 3DS'] = Convert-CheckResult -Expected 'configured' -Actual ([string] $threeDsByTenant['TenantC']) -Outcome $(if ($null -ne $threeDsByTenant['TenantC']) { 'PASS' } else { 'FAIL' })
$checks['Q2 TenantA rows'] = Convert-CheckResult -Expected ([string] $expectedTenantARows) -Actual ([string] (@($q2Shared | Where-Object Tenant -eq 'TenantA').Count)) -Outcome $(if (@($q2Shared | Where-Object Tenant -eq 'TenantA').Count -eq $expectedTenantARows) { 'PASS' } else { 'FAIL' })
$checks['Q2 TenantB rows'] = Convert-CheckResult -Expected ([string] $expectedTenantBRows) -Actual ([string] (@($q2Shared | Where-Object Tenant -eq 'TenantB').Count)) -Outcome $(if (@($q2Shared | Where-Object Tenant -eq 'TenantB').Count -eq $expectedTenantBRows) { 'PASS' } else { 'FAIL' })
$checks['Q5 TenantA steps'] = Convert-CheckResult -Expected ([string] $expectedTenantASteps) -Actual ([string] (@($q5Shared | Where-Object Tenant -eq 'TenantA').Count)) -Outcome $(if (@($q5Shared | Where-Object Tenant -eq 'TenantA').Count -eq $expectedTenantASteps) { 'PASS' } else { 'FAIL' })
$checks['Q5 TenantB steps'] = Convert-CheckResult -Expected ([string] $expectedTenantBSteps) -Actual ([string] (@($q5Shared | Where-Object Tenant -eq 'TenantB').Count)) -Outcome $(if (@($q5Shared | Where-Object Tenant -eq 'TenantB').Count -eq $expectedTenantBSteps) { 'PASS' } else { 'FAIL' })
$checks['Q8 bleed'] = Convert-CheckResult -Expected '0' -Actual ([string] @($q8Shared).Count) -Outcome $(if (@($q8Shared).Count -eq 0) { 'PASS' } else { 'FAIL' })
$checks['Q2-B TenantC rows'] = Convert-CheckResult -Expected ([string] $expectedTenantCRows) -Actual ([string] @($q2TenantC).Count) -Outcome $(if (@($q2TenantC).Count -eq $expectedTenantCRows) { 'PASS' } else { 'FAIL' })
$checks['Q5-B TenantC steps'] = Convert-CheckResult -Expected ([string] $expectedTenantCSteps) -Actual ([string] @($q5TenantC).Count) -Outcome $(if (@($q5TenantC).Count -eq $expectedTenantCSteps) { 'PASS' } else { 'FAIL' })
$checks['Q9-B TenantC bleed'] = Convert-CheckResult -Expected '0' -Actual ([string] @($q9Shared).Count) -Outcome $(if (@($q9Shared).Count -eq 0) { 'PASS' } else { 'FAIL' })

if ($apiChargeEvents.Count -eq 0) {
    $checks['API log -> DB charge IDs'] = Convert-CheckResult -Expected 'App Insights charge rows' -Actual 'No API charge rows returned for the selected run prefix' -Outcome 'INCONCLUSIVE'
}
else {
    $checks['API log -> DB charge IDs'] = Convert-CheckResult -Expected ([string] @($apiChargeEvents).Count) -Actual ([string] @($chargeCorrelation | Where-Object InDb).Count) -Outcome $(if (@($chargeCorrelation | Where-Object InDb).Count -eq @($apiChargeEvents).Count) { 'PASS' } else { 'FAIL' })
}

$expectedUiCallbacks = @($chargeCorrelation | Where-Object UiCallbackExpected).Count
$actualUiCallbacks = @($chargeCorrelation | Where-Object { $_.UiCallbackExpected -and $_.UiCallbackLogged }).Count
if ($apiChargeEvents.Count -eq 0 -and $selectedUiEvents.Count -eq 0) {
    $checks['UI log -> callbacks present where expected'] = Convert-CheckResult -Expected '3DS tenants only' -Actual 'No UI callback rows returned for the selected run prefix' -Outcome 'INCONCLUSIVE'
}
else {
    $checks['UI log -> callbacks present where expected'] = Convert-CheckResult -Expected ([string] $expectedUiCallbacks) -Actual ([string] $actualUiCallbacks) -Outcome $(if ($actualUiCallbacks -eq $expectedUiCallbacks) { 'PASS' } else { 'FAIL' })
}

$report = [PSCustomObject] @{
    Environment = $Environment
    Runtime = 'azure'
    RunPrefix = $selectedRunPrefix
    AppInsightsAvailable = $appInsightsAvailable
    AppInsights = [PSCustomObject] @{
        ApiEvidence = @($selectedApiEvents | Select-Object Timestamp, Tenant, ResolvedCustomerOrderId, ChargeId, Message)
        UiEvidence = @($reportedUiEvents | Select-Object Timestamp, Tenant, CustomerOrderId, UiEventName, ChargeId, StatusCode, Message)
    }
    Preflight = [PSCustomObject] @{
        TenantA = $threeDsByTenant['TenantA']
        TenantB = $threeDsByTenant['TenantB']
        TenantC = $threeDsByTenant['TenantC']
    }
    Checks = [PSCustomObject] $checks
    ChargeCorrelation = @($chargeCorrelation)
}

if ($OutputFormat -eq 'Json') {
    $report | ConvertTo-Json -Depth 8
    return
}

Write-Host ''
Write-Host "Azure payment verification" -ForegroundColor Cyan
Write-Host "Environment : $Environment"
Write-Host "RunPrefix   : $selectedRunPrefix"
if (-not $appInsightsAvailable) {
    Write-Host "AppInsights : no scoped payment rows returned; continuing with DB verification only" -ForegroundColor Yellow
}

Write-Step 'API evidence'
if ($selectedApiEvents.Count -eq 0) {
    Write-Host 'No API evidence rows matched the selected run prefix.' -ForegroundColor Yellow
}
else {
    $selectedApiEvents |
        Select-Object Timestamp, Tenant, ResolvedCustomerOrderId, ChargeId, Message |
        Format-Table -AutoSize |
        Out-String -Width 500 |
        Write-Host
}

Write-Step 'UI evidence'
if ($selectedUiEvents.Count -eq 0) {
    Write-Host 'No UI callback rows matched the selected charge IDs.' -ForegroundColor Yellow
}
else {
    $selectedUiEvents |
    Select-Object Timestamp, Tenant, CustomerOrderId, UiEventName, ChargeId, StatusCode, Message |
        Format-Table -AutoSize |
        Out-String -Width 500 |
        Write-Host
}

Write-Step 'Charge correlation'
if (@($chargeCorrelation).Count -eq 0) {
    Write-Host 'No API charge events were resolved for the selected run prefix.' -ForegroundColor Yellow
}
else {
    $chargeCorrelation |
    Select-Object ChargeId, Tenant, CustomerOrderId, InDb, DbStatus, DbStage, ThreeDSEnabled, UiCallbackExpected, UiCallbackLogged, UiCorrelationMode, @{ Name = 'UiEventNames'; Expression = { ($_.UiEventNames -join ',') } }, @{ Name = 'UiStatusCodes'; Expression = { ($_.UiStatusCodes -join ',') } } |
        Format-Table -AutoSize |
        Out-String -Width 500 |
        Write-Host
}

Write-Step 'Pass/fail summary'
$summaryRows = foreach ($name in $checks.Keys) {
    [PSCustomObject] @{
        Check = $name
        Expected = $checks[$name].Expected
        Actual = $checks[$name].Actual
        Outcome = $checks[$name].Outcome
    }
}

$summaryRows |
    Format-Table -AutoSize |
    Out-String -Width 500 |
    Write-Host