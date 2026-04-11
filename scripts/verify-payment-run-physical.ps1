#Requires -Version 7.0
<#!
.SYNOPSIS
    Verifies a local or Docker payment run end to end across physical log files and SQL databases.

.DESCRIPTION
    Reads today's API log for payment events plus browser-originated UI telemetry captured through
    /payment/client-event, resolves a logical run prefix, queries the shared and TenantC dedicated
    databases directly, and emits a consolidated pass/fail report.

    This script is the deterministic rerun path for the physical-log branch of the
    /XYDataLabs-verify-db-logs prompt flow.

.PARAMETER Environment
    Target environment. Supported values: dev, stg, prod.
    For Runtime=local, only dev is supported.

.PARAMETER Runtime
    Physical-log runtime. Supported values: local, docker.

.PARAMETER Profile
    Runtime profile. Supported values: http, https.

.PARAMETER RunPrefix
    Optional logical run prefix such as OR-1-9thApr. If omitted and exactly one
    prefix is found in today's API log, that prefix is used automatically.

.PARAMETER OutputFormat
    Human-readable table output or JSON.

.EXAMPLE
    .\scripts\verify-payment-run-physical.ps1 -Runtime docker -Environment dev -Profile http

.EXAMPLE
    .\scripts\verify-payment-run-physical.ps1 -Runtime local -Profile http -RunPrefix OR-1-9thApr

.EXAMPLE
    .\scripts\verify-payment-run-physical.ps1 -Runtime docker -Environment dev -Profile http -OutputFormat Json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('dev', 'stg', 'prod')]
    [string] $Environment = 'dev',

    [Parameter(Mandatory = $false)]
    [ValidateSet('local', 'docker')]
    [string] $Runtime = 'local',

    [Parameter(Mandatory = $false)]
    [ValidateSet('http', 'https')]
    [string] $Profile = 'http',

    [Parameter(Mandatory = $false)]
    [string] $RunPrefix,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Table', 'Json')]
    [string] $OutputFormat = 'Table'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Runtime -eq 'local' -and $Environment -ne 'dev') {
    throw 'Runtime=local supports only Environment=dev. Use Runtime=docker for dev/stg/prod physical-log verification.'
}

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$dateTag = (Get-Date).ToString('yyyyMMdd')
$envTag = if ($Runtime -eq 'local') { 'dev' } else { $Environment }
$runtimeTag = if ($Runtime -eq 'docker') { 'dock' } else { 'local' }
$apiLogPath = Join-Path $repoRoot "logs\webapi-$envTag-$runtimeTag-$Profile-$dateTag.log"
$envLocalPath = Join-Path $repoRoot 'Resources\Docker\.env.local'

$sharedDbName = if ($Runtime -eq 'local') {
    'OrderProcessingSystem_Local'
}
else {
    switch ($Environment) {
        'dev' { 'OrderProcessingSystem_Dev' }
        'stg' { 'OrderProcessingSystem_Stg' }
        'prod' { 'OrderProcessingSystem_Prod' }
    }
}

$tenantCDbName = if ($Runtime -eq 'local') {
    'OrderProcessingSystem_TenantC'
}
else {
    switch ($Environment) {
        'dev' { 'OrderProcessingSystem_TenantC_Dev' }
        'stg' { 'OrderProcessingSystem_TenantC_Stg' }
        'prod' { 'OrderProcessingSystem_TenantC_Prod' }
    }
}

function Write-Step {
    param([string] $Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
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

function Get-LogTimestamp {
    param([Parameter(Mandatory = $true)] [string] $Line)

    if ($Line -match '^(?<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} [+-]\d{2}:\d{2})') {
        return [datetimeoffset] $Matches.timestamp
    }

    throw "Unable to parse timestamp from log line: $Line"
}

function Get-TenantFromLine {
    param([Parameter(Mandatory = $true)] [string] $Line)

    if ($Line -match '\[Tenant:(?<tenant>[^\]]+)\]') {
        return [string] $Matches.tenant
    }

    if ($Line -match 'for tenant\s+(?<tenant>[^,\s]+)') {
        return [string] $Matches.tenant
    }

    return ''
}

function Get-RunPrefixFromCustomerOrder {
    param([Parameter(Mandatory = $false)] [string] $CustomerOrderId)

    if ([string]::IsNullOrWhiteSpace($CustomerOrderId)) {
        return ''
    }

    if ($CustomerOrderId -match '^(OR-\d+-[^-]+)') {
        return [string] $Matches[1]
    }

    return ''
}

function Get-MinimumTimeDeltaSeconds {
    param(
        [Parameter(Mandatory = $true)] [datetimeoffset] $CandidateTimestamp,
        [Parameter(Mandatory = $true)] [datetimeoffset[]] $ReferenceTimestamps
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

function Test-IsCallbackEvent {
    param([Parameter(Mandatory = $true)] [pscustomobject] $Event)

    return ($Event.Message -match 'OpenPay callback received' -or
        $Event.Message -match 'payment/callback responded' -or
        $Event.UiEventName -like 'ui_payment_callback*')
}

function Get-SqlPasswordFromEnvLocal {
    if (-not (Test-Path $envLocalPath)) {
        throw "Required Docker secrets file not found: $envLocalPath"
    }

    $password = Get-Content $envLocalPath |
        Select-String 'LOCAL_SQL_PASSWORD' |
        ForEach-Object { ($_ -split '=', 2)[1].Trim() } |
        Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($password)) {
        throw "LOCAL_SQL_PASSWORD was not found in $envLocalPath"
    }

    return [string] $password
}

function Invoke-PhysicalSqlQuery {
    param(
        [Parameter(Mandatory = $true)] [string] $Database,
        [Parameter(Mandatory = $true)] [string] $Query
    )

    $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source'] = 'localhost'
    $builder['Initial Catalog'] = $Database
    $builder['TrustServerCertificate'] = $true
    $builder['Connect Timeout'] = 30

    if ($Runtime -eq 'docker') {
        $builder['User ID'] = 'sa'
        $builder['Password'] = Get-SqlPasswordFromEnvLocal
        $builder['Integrated Security'] = $false
        $builder['Encrypt'] = $false
    }
    else {
        $builder['Integrated Security'] = $true
        $builder['Encrypt'] = $false
    }

    $connection = [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)

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

function Convert-ApiLogLinesToEvents {
    param([Parameter(Mandatory = $true)] [string[]] $Lines)

    $tenantState = @{}
    $events = [System.Collections.Generic.List[object]]::new()

    foreach ($line in $Lines) {
        $timestamp = Get-LogTimestamp -Line $line
        $tenant = Get-TenantFromLine -Line $line

        if ($line -match 'Generated payment attempt order id\s+(?<attemptOrderId>\S+)\s+and payment trace id\s+(?<traceId>\S+)\s+from customer order id\s+(?<customerOrderId>\S+)') {
            $customerOrderId = [string] $Matches.customerOrderId
            $runPrefix = Get-RunPrefixFromCustomerOrder -CustomerOrderId $customerOrderId

            if (-not [string]::IsNullOrWhiteSpace($tenant)) {
                $tenantState[$tenant] = [PSCustomObject] @{
                    CustomerOrderId = $customerOrderId
                    RunPrefix = $runPrefix
                }
            }

            $events.Add([PSCustomObject] @{
                    Timestamp = $timestamp
                    Tenant = $tenant
                    CustomerOrderId = $customerOrderId
                    ResolvedCustomerOrderId = $customerOrderId
                    RunPrefix = $runPrefix
                    ResolvedRunPrefix = $runPrefix
                    ChargeId = ''
                    Message = $line
                    EventType = 'generated'
                })
            continue
        }

        if ($line -match 'Charge created with ID:\s+(?<chargeId>\S+)') {
            $state = if ($tenantState.ContainsKey($tenant)) { $tenantState[$tenant] } else { $null }
            $events.Add([PSCustomObject] @{
                    Timestamp = $timestamp
                    Tenant = $tenant
                    CustomerOrderId = if ($null -ne $state) { $state.CustomerOrderId } else { '' }
                    ResolvedCustomerOrderId = if ($null -ne $state) { $state.CustomerOrderId } else { '' }
                    RunPrefix = if ($null -ne $state) { $state.RunPrefix } else { '' }
                    ResolvedRunPrefix = if ($null -ne $state) { $state.RunPrefix } else { '' }
                    ChargeId = [string] $Matches.chargeId
                    Message = $line
                    EventType = 'charge-created'
                })
            continue
        }

        if ($line -match 'Response:\s+200\s+Tenant:\s+(?<responseTenant>\S+)\s+Body:\s+(?<jsonBody>\{.+\})$') {
            try {
                $payload = $Matches.jsonBody | ConvertFrom-Json
                $data = $payload.data
                $customerOrderId = [string] $data.customerOrderId
                $chargeId = [string] $data.id
                $responseTenant = [string] $Matches.responseTenant
                $runPrefix = Get-RunPrefixFromCustomerOrder -CustomerOrderId $customerOrderId

                if (-not [string]::IsNullOrWhiteSpace($responseTenant) -and -not [string]::IsNullOrWhiteSpace($customerOrderId)) {
                    $tenantState[$responseTenant] = [PSCustomObject] @{
                        CustomerOrderId = $customerOrderId
                        RunPrefix = $runPrefix
                    }
                }

                $events.Add([PSCustomObject] @{
                        Timestamp = $timestamp
                        Tenant = $responseTenant
                        CustomerOrderId = $customerOrderId
                        ResolvedCustomerOrderId = $customerOrderId
                        RunPrefix = $runPrefix
                        ResolvedRunPrefix = $runPrefix
                        ChargeId = $chargeId
                        Message = $line
                        EventType = 'response'
                    })
            }
            catch {
            }

            continue
        }

        if ($line -match 'Payment callback reconciliation completed for payment\s+(?<chargeId>\S+)\.') {
            $state = if ($tenantState.ContainsKey($tenant)) { $tenantState[$tenant] } else { $null }
            $events.Add([PSCustomObject] @{
                    Timestamp = $timestamp
                    Tenant = $tenant
                    CustomerOrderId = if ($null -ne $state) { $state.CustomerOrderId } else { '' }
                    ResolvedCustomerOrderId = if ($null -ne $state) { $state.CustomerOrderId } else { '' }
                    RunPrefix = if ($null -ne $state) { $state.RunPrefix } else { '' }
                    ResolvedRunPrefix = if ($null -ne $state) { $state.RunPrefix } else { '' }
                    ChargeId = [string] $Matches.chargeId
                    Message = $line
                    EventType = 'callback-reconciled'
                })
            continue
        }
    }

    return @($events | Sort-Object Timestamp)
}

function Convert-UiLogLinesToEvents {
    param([Parameter(Mandatory = $true)] [string[]] $Lines)

    $events = [System.Collections.Generic.List[object]]::new()

    foreach ($line in $Lines) {
        $timestamp = Get-LogTimestamp -Line $line
        $tenant = Get-TenantFromLine -Line $line
        $customerOrderId = ''
        $uiEventName = ''
        $chargeId = ''
        $statusCode = ''

        if ($line -match 'customer order\s+(?<customerOrderId>\S+)') {
            $customerOrderId = [string] $Matches.customerOrderId
        }

        if ($line -match 'UI payment event\s+(?<uiEventName>\S+)\s+on') {
            $uiEventName = [string] $Matches.uiEventName
        }

        if ($line -match 'for payment\s+(?<chargeId>[^,\s]+)') {
            $chargeId = [string] $Matches.chargeId
        }
        elseif ($line -match 'payment\s+(?<chargeId>[^,\s]+)\s+status') {
            $chargeId = [string] $Matches.chargeId
        }

        if ($line -match 'payment/callback responded\s+(?<statusCode>\d+)') {
            $statusCode = [string] $Matches.statusCode
        }

        $events.Add([PSCustomObject] @{
                Timestamp = $timestamp
                Tenant = $tenant
                CustomerOrderId = $customerOrderId
                UiEventName = $uiEventName
                ChargeId = $chargeId
                StatusCode = $statusCode
                Message = $line
            EventKey = ('{0}|{1}|{2}|{3}|{4}|{5}' -f $timestamp.ToString('o'), $chargeId, $tenant, $customerOrderId, $uiEventName, $line)
            })
    }

    return @($events | Sort-Object Timestamp)
}

if (-not (Test-Path $apiLogPath)) {
    throw "API log file not found: $apiLogPath"
}

Write-Step "Reading API log from $apiLogPath"
$apiLogLines = Get-Content $apiLogPath |
    Select-String -Pattern 'Generated payment|created charge|charge created|callback reconciliation completed|confirm-status responded|Response: 200.*OR-' |
    ForEach-Object { $_.Line.Trim() }

$apiEvents = Convert-ApiLogLinesToEvents -Lines @($apiLogLines)
$availableRunPrefixes = @($apiEvents | Where-Object { -not [string]::IsNullOrWhiteSpace($_.ResolvedRunPrefix) } | Select-Object -ExpandProperty ResolvedRunPrefix -Unique)

$selectedRunPrefix = $RunPrefix
if ([string]::IsNullOrWhiteSpace($selectedRunPrefix)) {
    if ($availableRunPrefixes.Count -eq 1) {
        $selectedRunPrefix = $availableRunPrefixes[0]
    }
    elseif ($availableRunPrefixes.Count -gt 1) {
        $prefixDetails = @(
            $availableRunPrefixes | ForEach-Object {
                $firstEvent = $apiEvents | Where-Object ResolvedRunPrefix -eq $_ | Select-Object -First 1
                '{0} - first entry at {1}' -f $_, $firstEvent.Timestamp.ToString('HH:mm:ss')
            }
        )

        throw "Multiple payment run prefixes found today:`n- $($prefixDetails -join "`n- ")`nRe-run with -RunPrefix."
    }
    else {
        throw "No payment run prefixes were found in today's API log: $apiLogPath"
    }
}

if ($availableRunPrefixes.Count -gt 0 -and $availableRunPrefixes -notcontains $selectedRunPrefix) {
    $prefixList = ($availableRunPrefixes | ForEach-Object { '- ' + $_ }) -join "`n"
    throw "Run prefix '$selectedRunPrefix' was not found in today's API log.`n$prefixList"
}

$selectedApiEvents = @($apiEvents | Where-Object { $_.ResolvedRunPrefix -eq $selectedRunPrefix })
$apiChargeEvents = @(
    $selectedApiEvents |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.ChargeId) } |
        Group-Object ChargeId |
        ForEach-Object {
            $preferred = $_.Group | Where-Object EventType -eq 'charge-created' | Select-Object -First 1
            if ($null -ne $preferred) {
                return $preferred
            }

            $preferred = $_.Group | Where-Object EventType -eq 'response' | Select-Object -First 1
            if ($null -ne $preferred) {
                return $preferred
            }

            $_.Group | Select-Object -First 1
        } |
        Sort-Object Timestamp
)

$warnings = [System.Collections.Generic.List[string]]::new()
$uiEvents = @()
$selectedUiEvents = @()

Write-Step "Reading browser UI telemetry from $apiLogPath"
$uiEvidenceLines = Get-Content $apiLogPath |
    Select-String -Pattern $selectedRunPrefix |
    ForEach-Object { $_.Line.Trim() } |
    Where-Object {
        $_ -match 'UI payment event' -or
        $_ -match 'OpenPay callback received' -or
        $_ -match 'payment/callback responded'
    }

if (@($uiEvidenceLines).Count -gt 0) {
    $uiEvents = Convert-UiLogLinesToEvents -Lines @($uiEvidenceLines)
    $knownChargeIds = @($apiChargeEvents | Select-Object -ExpandProperty ChargeId -Unique)
    $selectedUiEvents = @(
        $uiEvents |
            Where-Object {
                ($_.CustomerOrderId -like "$selectedRunPrefix*") -or
                (-not [string]::IsNullOrWhiteSpace($_.ChargeId) -and ($knownChargeIds -contains $_.ChargeId))
            } |
            Sort-Object Timestamp
    )
}
else {
    $warnings.Add("No browser UI telemetry matched run prefix '$selectedRunPrefix' in API log: $apiLogPath")
}

Write-Step 'Querying SQL databases'
$preflightShared = Invoke-PhysicalSqlQuery -Database $sharedDbName -Query @"
SELECT t.Code AS Tenant, pp.Use3DSecure AS ThreeDSEnabled
FROM dbo.PaymentProviders pp
JOIN dbo.Tenants t ON t.Id = pp.TenantId
ORDER BY pp.TenantId;
"@

$preflightTenantC = Invoke-PhysicalSqlQuery -Database $tenantCDbName -Query @"
SELECT pp.TenantId, pp.Use3DSecure AS ThreeDSEnabled
FROM dbo.PaymentProviders pp;
"@

$q2Shared = Invoke-PhysicalSqlQuery -Database $sharedDbName -Query @"
SELECT t.Code AS Tenant, ct.CustomerOrderId, ct.TransactionId AS ChargeId,
       ct.TransactionStatus AS Status, ct.IsThreeDSecureEnabled AS ThreeDS,
       ct.ThreeDSecureStage, ct.TransactionReferenceId AS Ref,
       ct.IsTransactionSuccess AS OK, ct.CreatedDate
FROM dbo.CardTransactions ct
JOIN dbo.Tenants t ON t.Id = ct.TenantId
WHERE ct.CustomerOrderId LIKE '$selectedRunPrefix%'
ORDER BY ct.TenantId, ct.CustomerOrderId, ct.Id;
"@

$q5Shared = Invoke-PhysicalSqlQuery -Database $sharedDbName -Query @"
SELECT t.Code AS Tenant, ct.CustomerOrderId, tsh.Status,
       tsh.ThreeDSecureStage AS Stage, tsh.IsThreeDSecureEnabled AS ThreeDS,
       tsh.TransactionReferenceId AS Ref
FROM dbo.TransactionStatusHistories tsh
JOIN dbo.CardTransactions ct ON ct.Id = tsh.TransactionId
JOIN dbo.Tenants t ON t.Id = ct.TenantId
WHERE ct.CustomerOrderId LIKE '$selectedRunPrefix%'
ORDER BY ct.TenantId, ct.CustomerOrderId, ct.Id, tsh.Id;
"@

$q8Shared = Invoke-PhysicalSqlQuery -Database $sharedDbName -Query @"
SELECT ct.CustomerOrderId, ct.TenantId, t.Code
FROM dbo.CardTransactions ct
JOIN dbo.Tenants t ON t.Id = ct.TenantId
WHERE ct.CustomerOrderId LIKE '$selectedRunPrefix%'
  AND ((ct.CustomerOrderId LIKE '%-tA-%' AND ct.TenantId <> 1)
    OR (ct.CustomerOrderId LIKE '%-tB-%' AND ct.TenantId <> 2));
"@

$q2TenantC = Invoke-PhysicalSqlQuery -Database $tenantCDbName -Query @"
SELECT ct.CustomerOrderId, ct.TransactionId AS ChargeId,
       ct.TransactionStatus AS Status, ct.IsThreeDSecureEnabled AS ThreeDS,
       ct.ThreeDSecureStage, ct.TransactionReferenceId AS Ref,
       ct.IsTransactionSuccess AS OK, ct.CreatedDate
FROM dbo.CardTransactions ct
WHERE ct.TenantId = 3
  AND ct.CustomerOrderId LIKE '$selectedRunPrefix%'
ORDER BY ct.CustomerOrderId, ct.Id;
"@

$q5TenantC = Invoke-PhysicalSqlQuery -Database $tenantCDbName -Query @"
SELECT ct.CustomerOrderId, tsh.Status, tsh.ThreeDSecureStage AS Stage,
       tsh.IsThreeDSecureEnabled AS ThreeDS, tsh.TransactionReferenceId AS Ref
FROM dbo.TransactionStatusHistories tsh
JOIN dbo.CardTransactions ct ON ct.Id = tsh.TransactionId
WHERE ct.TenantId = 3
  AND ct.CustomerOrderId LIKE '$selectedRunPrefix%'
ORDER BY ct.CustomerOrderId, ct.Id, tsh.Id;
"@

$q9Shared = Invoke-PhysicalSqlQuery -Database $sharedDbName -Query @"
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
foreach ($tenantGroup in ($selectedApiEvents | Where-Object { -not [string]::IsNullOrWhiteSpace($_.ResolvedCustomerOrderId) -and $_.Tenant -in @('TenantA', 'TenantB', 'TenantC') } | Group-Object Tenant)) {
    $expectedOrdersByTenant[$tenantGroup.Name] = @($tenantGroup.Group | Select-Object -ExpandProperty ResolvedCustomerOrderId -Unique)
}

if ($expectedOrdersByTenant.Count -eq 0) {
    foreach ($tenantGroup in ($q2Shared | Group-Object Tenant)) {
        $expectedOrdersByTenant[$tenantGroup.Name] = @($tenantGroup.Group | Select-Object -ExpandProperty CustomerOrderId -Unique)
    }

    $tenantCOrders = @($q2TenantC | Select-Object -ExpandProperty CustomerOrderId -Unique)
    if ($tenantCOrders.Count -gt 0) {
        $expectedOrdersByTenant['TenantC'] = $tenantCOrders
    }
}

$allDbChargeIds = @(@($q2Shared | Select-Object -ExpandProperty ChargeId) + @($q2TenantC | Select-Object -ExpandProperty ChargeId))
$matchedUiEventKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$usedFallbackUiEventKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

$chargeCorrelation = @(
    foreach ($chargeEvent in $apiChargeEvents) {
        $callbackEvents = @($selectedUiEvents | Where-Object { Test-IsCallbackEvent -Event $_ })
        $uiMatches = @($callbackEvents | Where-Object { -not [string]::IsNullOrWhiteSpace($_.ChargeId) -and $_.ChargeId -eq $chargeEvent.ChargeId })
        $uiCorrelationMode = if ($uiMatches.Count -gt 0) { 'charge-id' } else { 'none' }

        if ($uiMatches.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($chargeEvent.ResolvedCustomerOrderId)) {
            $uiMatches = @($callbackEvents | Where-Object { $_.CustomerOrderId -eq $chargeEvent.ResolvedCustomerOrderId })
            if ($uiMatches.Count -gt 0) {
                $uiCorrelationMode = 'customer-order'
            }
        }

        if ($uiMatches.Count -eq 0 -and $threeDsByTenant[$chargeEvent.Tenant] -eq 1) {
            $fallbackMatch = @(
                $callbackEvents |
                    Where-Object {
                        $_.Tenant -eq $chargeEvent.Tenant -and
                        -not $usedFallbackUiEventKeys.Contains($_.EventKey)
                    } |
                    ForEach-Object {
                        [PSCustomObject] @{
                            UiEvent = $_
                            DeltaSeconds = Get-MinimumTimeDeltaSeconds -CandidateTimestamp $_.Timestamp -ReferenceTimestamps @($chargeEvent.Timestamp)
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
            }
        }

        foreach ($uiMatch in $uiMatches) {
            $null = $matchedUiEventKeys.Add($uiMatch.EventKey)
        }

        $uiStatusCodes = @($uiMatches | Where-Object { -not [string]::IsNullOrWhiteSpace($_.StatusCode) } | Select-Object -ExpandProperty StatusCode -Unique)
        $uiEventNames = @($uiMatches | Where-Object { -not [string]::IsNullOrWhiteSpace($_.UiEventName) } | Select-Object -ExpandProperty UiEventName -Unique)

        $dbRow = if ($chargeEvent.Tenant -eq 'TenantC') {
            $q2TenantC | Where-Object ChargeId -eq $chargeEvent.ChargeId | Select-Object -First 1
        }
        else {
            $q2Shared | Where-Object ChargeId -eq $chargeEvent.ChargeId | Select-Object -First 1
        }

        [PSCustomObject] @{
            ChargeId = $chargeEvent.ChargeId
            Tenant = $chargeEvent.Tenant
            CustomerOrderId = $chargeEvent.ResolvedCustomerOrderId
            InDb = ($allDbChargeIds -contains $chargeEvent.ChargeId)
            DbStatus = if ($null -ne $dbRow) { [string] $dbRow.Status } else { '' }
            DbStage = if ($null -ne $dbRow) { [string] $dbRow.ThreeDSecureStage } else { '' }
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
$checks['Q2 TenantA rows'] = Convert-CheckResult -Expected ([string] $expectedTenantARows) -Actual ([string] @($q2Shared | Where-Object Tenant -eq 'TenantA').Count) -Outcome $(if (@($q2Shared | Where-Object Tenant -eq 'TenantA').Count -eq $expectedTenantARows) { 'PASS' } else { 'FAIL' })
$checks['Q2 TenantB rows'] = Convert-CheckResult -Expected ([string] $expectedTenantBRows) -Actual ([string] @($q2Shared | Where-Object Tenant -eq 'TenantB').Count) -Outcome $(if (@($q2Shared | Where-Object Tenant -eq 'TenantB').Count -eq $expectedTenantBRows) { 'PASS' } else { 'FAIL' })
$checks['Q5 TenantA steps'] = Convert-CheckResult -Expected ([string] $expectedTenantASteps) -Actual ([string] @($q5Shared | Where-Object Tenant -eq 'TenantA').Count) -Outcome $(if (@($q5Shared | Where-Object Tenant -eq 'TenantA').Count -eq $expectedTenantASteps) { 'PASS' } else { 'FAIL' })
$checks['Q5 TenantB steps'] = Convert-CheckResult -Expected ([string] $expectedTenantBSteps) -Actual ([string] @($q5Shared | Where-Object Tenant -eq 'TenantB').Count) -Outcome $(if (@($q5Shared | Where-Object Tenant -eq 'TenantB').Count -eq $expectedTenantBSteps) { 'PASS' } else { 'FAIL' })
$checks['Q8 bleed'] = Convert-CheckResult -Expected '0' -Actual ([string] @($q8Shared).Count) -Outcome $(if (@($q8Shared).Count -eq 0) { 'PASS' } else { 'FAIL' })
$checks['Q2-B TenantC rows'] = Convert-CheckResult -Expected ([string] $expectedTenantCRows) -Actual ([string] @($q2TenantC).Count) -Outcome $(if (@($q2TenantC).Count -eq $expectedTenantCRows) { 'PASS' } else { 'FAIL' })
$checks['Q5-B TenantC steps'] = Convert-CheckResult -Expected ([string] $expectedTenantCSteps) -Actual ([string] @($q5TenantC).Count) -Outcome $(if (@($q5TenantC).Count -eq $expectedTenantCSteps) { 'PASS' } else { 'FAIL' })
$checks['Q9-B TenantC bleed'] = Convert-CheckResult -Expected '0' -Actual ([string] @($q9Shared).Count) -Outcome $(if (@($q9Shared).Count -eq 0) { 'PASS' } else { 'FAIL' })

if ($apiChargeEvents.Count -eq 0) {
    $checks['API log -> DB charge IDs'] = Convert-CheckResult -Expected 'API charge rows' -Actual 'No API charge rows returned for the selected run prefix' -Outcome 'INCONCLUSIVE'
}
else {
    $checks['API log -> DB charge IDs'] = Convert-CheckResult -Expected ([string] @($apiChargeEvents).Count) -Actual ([string] @($chargeCorrelation | Where-Object InDb).Count) -Outcome $(if (@($chargeCorrelation | Where-Object InDb).Count -eq @($apiChargeEvents).Count) { 'PASS' } else { 'FAIL' })
}

$expectedUiCallbacks = @($chargeCorrelation | Where-Object UiCallbackExpected).Count
$actualUiCallbacks = @($chargeCorrelation | Where-Object { $_.UiCallbackExpected -and $_.UiCallbackLogged }).Count
if ($expectedUiCallbacks -gt 0 -and $uiEvents.Count -eq 0) {
    $checks['UI telemetry -> callbacks present where expected'] = Convert-CheckResult -Expected ([string] $expectedUiCallbacks) -Actual 'No browser UI telemetry matched the selected run prefix' -Outcome 'FAIL'
}
else {
    $checks['UI telemetry -> callbacks present where expected'] = Convert-CheckResult -Expected ([string] $expectedUiCallbacks) -Actual ([string] $actualUiCallbacks) -Outcome $(if ($actualUiCallbacks -eq $expectedUiCallbacks) { 'PASS' } else { 'FAIL' })
}

$report = [PSCustomObject] @{
    Environment = $Environment
    Runtime = $Runtime
    Profile = $Profile
    RunPrefix = $selectedRunPrefix
    Warnings = @($warnings)
    Logs = [PSCustomObject] @{
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
Write-Host 'Physical payment verification' -ForegroundColor Cyan
Write-Host "Environment : $Environment"
Write-Host "Runtime     : $Runtime"
Write-Host "Profile     : $Profile"
Write-Host "RunPrefix   : $selectedRunPrefix"

if ($warnings.Count -gt 0) {
    Write-Host ''
    Write-Host 'Warnings' -ForegroundColor Yellow
    foreach ($warning in $warnings) {
        Write-Host "- $warning" -ForegroundColor Yellow
    }
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
if ($reportedUiEvents.Count -eq 0) {
    Write-Host 'No UI evidence rows matched the selected run prefix.' -ForegroundColor Yellow
}
else {
    $reportedUiEvents |
        Select-Object Timestamp, Tenant, CustomerOrderId, UiEventName, ChargeId, StatusCode, Message |
        Format-Table -AutoSize |
        Out-String -Width 500 |
        Write-Host
}

Write-Step 'Charge correlation'
if ($chargeCorrelation.Count -eq 0) {
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