#Requires -Version 7.0
<#!
.SYNOPSIS
    Verifies an Azure payment run end to end across App Insights and Azure SQL.

.DESCRIPTION
    Queries API and UI traces from Application Insights, resolves a logical run prefix,
    discovers active tenant topology from the deployed registry and Key Vault contracts,
    reads the payment state from the shared and resolved dedicated Azure SQL databases,
    and emits a consolidated pass/fail report.

    This script is the deterministic Azure rerun path for the manual
    /XYDataLabs-verify-db-logs prompt flow.

.PARAMETER Environment
    Target environment. Supported values: dev, staging, stg, prod.

.PARAMETER RunPrefix
    Optional logical run prefix such as OR-1-2ndApr. If omitted and exactly one
    prefix is found in today's API traces, that prefix is used automatically.

.PARAMETER CustomerOrderId
    Optional persisted customer order ID for an individual automation journey.
    SQL evidence is scoped to this exact ID when supplied.

.PARAMETER TenantCode
    Optional tenant code for an individual automation journey. When supplied,
    same-number customer orders belonging to other tenants are excluded.

.PARAMETER ProviderPaymentId
    Optional payment ID observed in the browser callback. This is the primary
    request/dependency correlation key when the provider stores a different
    transaction identifier in the database (for example Razorpay pay_* vs order_*).

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
    [ValidateSet('dev', 'staging', 'stg', 'prod')]
    [string] $Environment = 'dev',

    [Parameter(Mandatory = $false)]
    [string] $RunPrefix,

    [Parameter(Mandatory = $false)]
    [string] $CustomerOrderId,

    [Parameter(Mandatory = $false)]
    [string] $TenantCode,

    [Parameter(Mandatory = $false)]
    [string] $ProviderPaymentId,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Table', 'Json')]
    [string] $OutputFormat = 'Table',

    [Parameter(Mandatory = $false)]
    [switch] $SkipFirewallOpen,

    [Parameter(Mandatory = $false)]
    [int] $PreQueryDelaySeconds = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resourceEnvironment = switch ($Environment) {
    'staging' { 'stg' }
    default { $Environment }
}
$logicalEnvironment = switch ($Environment) {
    'stg' { 'staging' }
    default { $Environment }
}

$envSuffix = $resourceEnvironment
$resourceGroup = "rg-orderprocessing-$envSuffix"
$appInsightsName = "ai-orderprocessing-$envSuffix"
$keyVaultName = "kv-orderprocessing-$envSuffix"
$sqlServerName = "orderprocessing-sql-$envSuffix"
$sqlServerFqdn = "$sqlServerName.database.windows.net"
$supportedTenantTiers = @('SharedPool', 'Dedicated')
$supportedProviders = @('OpenPay', 'Razorpay')
$sharedDbName = switch ($logicalEnvironment) {
    'dev' { 'OrderProcessingSystem_Dev' }
    'staging' { 'OrderProcessingSystem_Staging' }
    'prod' { 'OrderProcessingSystem_Prod' }
}

function Assert-AzureRuntimeDbContract {
    param(
        [Parameter(Mandatory = $true)][string]$Environment,
        [Parameter(Mandatory = $true)][string]$SharedDbName
    )

    $expectedShared = switch ($Environment) {
        'dev' { 'OrderProcessingSystem_Dev' }
        'staging' { 'OrderProcessingSystem_Staging' }
        'prod' { 'OrderProcessingSystem_Prod' }
    }

    if ($SharedDbName -ne $expectedShared) {
        throw "Azure runtime/db-name mismatch. Environment=$Environment SharedDbName=$SharedDbName ExpectedShared=$expectedShared"
    }
}

Assert-AzureRuntimeDbContract -Environment $logicalEnvironment -SharedDbName $sharedDbName

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

    if ($null -eq $Response -or $null -eq $Response.tables -or @($Response.tables).Count -eq 0) {
        return @()
    }

    $table = $Response.tables[0]
    $columnNames = @($table.columns | ForEach-Object { [string] $_.name })
    $rows = @()

    foreach ($row in $table.rows) {
        $item = [ordered] @{}
        $rowArray = @($row)
        for ($index = 0; $index -lt $columnNames.Count; $index++) {
            $item[$columnNames[$index]] = if ($index -lt $rowArray.Count) { $rowArray[$index] } else { $null }
        }

        $rows += [PSCustomObject] $item
    }

    return $rows
}

function Invoke-AppInsightsQuery {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Query,

        [Parameter(Mandatory = $false)]
        [int] $MaxAttempts = 3
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            # Collapse multi-line KQL to a single line before passing to az.
            # PowerShell 7.4+ 'Windows' native argument passing mode mangles
            # multi-line string arguments, causing az to ignore the KQL entirely.
            $normalizedQuery = ($Query -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ' '

            $raw = az monitor app-insights query `
                --app $appInsightsName `
                --resource-group $resourceGroup `
                --analytics-query $normalizedQuery `
                --offset 7d `
                --output json `
                --only-show-errors

            if (-not $raw) {
                throw "App Insights query returned no response."
            }

            return $raw | ConvertFrom-Json
        }
        catch {
            if ($attempt -ge $MaxAttempts) {
                throw
            }

            Write-Host "App Insights query attempt $attempt of $MaxAttempts failed: $($_.Exception.Message)" -ForegroundColor Yellow
            Start-Sleep -Seconds $attempt
        }
    }

    throw 'App Insights query failed unexpectedly.'
}

function Invoke-AzureCliText {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock] $Command,

        [Parameter(Mandatory = $true)]
        [string] $Operation,

        [Parameter(Mandatory = $false)]
        [int] $MaxAttempts = 3
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            $result = & $Command 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw (($result | ForEach-Object { [string] $_ }) -join [Environment]::NewLine)
            }

            $text = (($result | ForEach-Object { [string] $_ }) -join [Environment]::NewLine).Trim()
            if ([string]::IsNullOrWhiteSpace($text)) {
                throw "$Operation returned no response."
            }

            return $text
        }
        catch {
            if ($attempt -ge $MaxAttempts) {
                throw "${Operation} failed after $MaxAttempts attempt(s). $($_.Exception.Message)"
            }

            Write-Host "$Operation attempt $attempt of $MaxAttempts failed: $($_.Exception.Message)" -ForegroundColor Yellow
            Start-Sleep -Seconds $attempt
        }
    }

    throw "$Operation failed unexpectedly."
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

        $resultRows = [System.Collections.Generic.List[object]]::new()
        foreach ($dataRow in $table.Rows) {
            $row = [ordered] @{}
            foreach ($column in $table.Columns) {
                $row[$column.ColumnName] = $dataRow[$column.ColumnName]
            }

            $resultRows.Add([PSCustomObject] $row)
        }

        return @($resultRows.ToArray())
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

function ConvertTo-SqlStringLiteral {
    param([Parameter(Mandatory = $true)][string]$Value)

    return $Value.Replace("'", "''")
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

function Test-IsCallbackEvent {
    param([Parameter(Mandatory = $true)] [pscustomobject] $Event)

    return ($Event.Message -match 'OpenPay callback received' -or
        $Event.Message -match 'payment/callback responded' -or
        $Event.UiEventName -like 'ui_payment_callback*')
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

    $directMatches = @(
        $Events |
            Where-Object {
                ($_.ChargeId -and ($KnownChargeIds -contains $_.ChargeId)) -or
                ($_.CustomerOrderId -and ($KnownCustomerOrders -contains $_.CustomerOrderId))
            } |
            Sort-Object Timestamp
    )

    if ($directMatches.Count -gt 0) {
        return $directMatches
    }

    return @(
        $Events |
            Where-Object {
                $_.Tenant -and ($KnownTenants -contains $_.Tenant)
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

function Resolve-DatabaseNameFromConnectionString {
    param([Parameter(Mandatory = $true)][string]$ConnectionString)

    $match = [regex]::Match($ConnectionString, '(?i)(?:Initial\s+Catalog|Database)\s*=\s*([^;]+)')
    if (-not $match.Success) {
        throw "Connection string does not contain an Initial Catalog/Database segment."
    }

    return $match.Groups[1].Value.Trim()
}

function Convert-HashtableToObject {
    param([Parameter(Mandatory = $true)][hashtable]$Table)

    $ordered = [ordered]@{}
    foreach ($key in ($Table.Keys | Sort-Object)) {
        $ordered[$key] = $Table[$key]
    }

    return [PSCustomObject]$ordered
}

function Get-AzureTenantTopology {
    param(
        [Parameter(Mandatory = $true)][string]$SqlAdminUser,
        [Parameter(Mandatory = $true)][string]$SqlAdminPassword
    )

    $registryRows = @(Invoke-AzureSqlQuery -Database $sharedDbName -UserName $SqlAdminUser -Password $SqlAdminPassword -Query @"
SELECT
    [Id] AS TenantId,
    [Code] AS TenantCode,
    [Name] AS TenantName,
    [Status] AS TenantStatus,
    [TenantTier] AS TenantTier,
    [PaymentProviderCode] AS PaymentProviderCode
FROM [dbo].[Tenants]
WHERE [Status] = 'Active'
ORDER BY [Code];
"@)

    if ($registryRows.Count -eq 0) {
        throw "The Azure tenant registry in '$sharedDbName' returned no active tenants."
    }

    $topology = New-Object 'System.Collections.Generic.List[object]'
    $seenTenants = @{}
    foreach ($row in $registryRows) {
        $tenantCode = [string](Get-ObjectPropertyValue -Object $row -PropertyName 'TenantCode')
        $tenantStatus = [string](Get-ObjectPropertyValue -Object $row -PropertyName 'TenantStatus')
        $tenantTier = [string](Get-ObjectPropertyValue -Object $row -PropertyName 'TenantTier')
        $providerCode = [string](Get-ObjectPropertyValue -Object $row -PropertyName 'PaymentProviderCode')
        $tenantId = [int](Get-ObjectPropertyValue -Object $row -PropertyName 'TenantId')

        if ([string]::IsNullOrWhiteSpace($tenantCode)) {
            Write-Warning "Tenant registry data integrity warning: a row in [dbo].[Tenants] with Status='Active' has a null or empty Code column (TenantId=$tenantId). This row is excluded from the verification topology. Investigate the Tenants table and correct the missing Code value."
            continue
        }

        if ($seenTenants.ContainsKey($tenantCode)) {
            throw "Tenant registry contract failure: duplicate active tenant '$tenantCode' was returned."
        }
        $seenTenants[$tenantCode] = $true

        if ($tenantStatus -ne 'Active') {
            throw "Tenant registry contract failure: inactive tenant '$tenantCode' appeared in the execution catalog."
        }

        if ([string]::IsNullOrWhiteSpace($tenantTier) -or $supportedTenantTiers -notcontains $tenantTier) {
            throw "Tenant registry contract failure: tenant '$tenantCode' has unsupported TenantTier '$tenantTier'."
        }

        if ([string]::IsNullOrWhiteSpace($providerCode)) {
            throw "Tenant registry contract failure: tenant '$tenantCode' has missing paymentProviderCode."
        }

        if ($supportedProviders -notcontains $providerCode) {
            throw "Tenant registry contract failure: tenant '$tenantCode' has unsupported paymentProviderCode '$providerCode'."
        }

        $dedicatedSecretName = $null
        $dedicatedDatabaseName = $null
        if ($tenantTier -eq 'Dedicated') {
            $dedicatedSecretName = "DedicatedTenantConnectionStrings--$tenantCode"
            $dedicatedConnectionString = Invoke-AzureCliText -Operation "Resolve $dedicatedSecretName from Key Vault" -Command {
                az keyvault secret show --vault-name $keyVaultName --name $dedicatedSecretName --query value -o tsv
            }

            if ([string]::IsNullOrWhiteSpace($dedicatedConnectionString)) {
                throw "Tenant registry contract failure: dedicated tenant '$tenantCode' is missing Key Vault secret '$dedicatedSecretName'."
            }

            $dedicatedDatabaseName = Resolve-DatabaseNameFromConnectionString -ConnectionString $dedicatedConnectionString
        }

        $providerPrivateKeyAlias = "PaymentProviders--$tenantCode--$providerCode--PrivateKey"
        $providerPrivateKeyValue = Invoke-AzureCliText -Operation "Resolve $providerPrivateKeyAlias from Key Vault" -Command {
            az keyvault secret show --vault-name $keyVaultName --name $providerPrivateKeyAlias --query value -o tsv
        }

        if ([string]::IsNullOrWhiteSpace($providerPrivateKeyValue)) {
            throw "Tenant registry contract failure: active tenant/provider mapping '$tenantCode/$providerCode' is missing Key Vault secret '$providerPrivateKeyAlias'."
        }

        $topology.Add([PSCustomObject]@{
                TenantId = $tenantId
                TenantCode = $tenantCode
                Active = $true
                TenantTier = $tenantTier
                PaymentProviderCode = $providerCode
                DedicatedDatabaseName = $dedicatedDatabaseName
                DedicatedConnectionSecret = $dedicatedSecretName
                ProviderPrivateKeyAlias = $providerPrivateKeyAlias
                ContractStatus = 'validated'
            })
    }

    return $topology.ToArray()
}

Write-Step "Resolving Azure resources and credentials for $Environment"
$sqlAdminUser = Invoke-AzureCliText -Operation 'Resolve SQL administrator login' -Command {
    az sql server show --name $sqlServerName --resource-group $resourceGroup --query administratorLogin -o tsv
}

$sqlAdminPassword = Invoke-AzureCliText -Operation 'Resolve sql-admin-password from Key Vault' -Command {
    az keyvault secret show --vault-name $keyVaultName --name sql-admin-password --query value -o tsv
}

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

if ($PreQueryDelaySeconds -gt 0) {
    Write-Step "Waiting $PreQueryDelaySeconds seconds for App Insights telemetry ingestion..."
    Start-Sleep -Seconds $PreQueryDelaySeconds
}

$tenantTopology = @(Get-AzureTenantTopology -SqlAdminUser $sqlAdminUser -SqlAdminPassword $sqlAdminPassword)
$sharedTenants = @($tenantTopology | Where-Object TenantTier -eq 'SharedPool')
$dedicatedTenants = @($tenantTopology | Where-Object TenantTier -eq 'Dedicated')
$sharedTenantCodes = @($sharedTenants | ForEach-Object { $_.TenantCode })
$dedicatedTenantCodes = @($dedicatedTenants | ForEach-Object { $_.TenantCode })

Write-Step "Querying App Insights API telemetry"
$apiQuery = @"
union isfuzzy=true
(
customEvents
| where timestamp >= startofday(now() + 330m) - 330m
| where name in ('payment_validation_attempt_created',
                 'payment_validation_charge_created',
                 'payment_validation_callback_reconciled')
| extend application = tostring(customDimensions['Application'])
| extend tenant = tostring(customDimensions['TenantCode'])
| extend customerOrderId = tostring(customDimensions['CustomerOrderId'])
| extend runPrefix = coalesce(tostring(customDimensions['RunPrefix']), extract(@'^(OR-\d+-[^-]+)', 1, customerOrderId))
| extend chargeId = tostring(customDimensions['PaymentId'])
| extend message = case(
    name == 'payment_validation_attempt_created', strcat('Generated payment attempt order id ', tostring(customDimensions['AttemptOrderId']), ' and payment trace id ', tostring(customDimensions['PaymentTraceId']), ' from customer order id ', customerOrderId),
    name == 'payment_validation_charge_created', strcat('Charge created with ID: ', tostring(customDimensions['PaymentId'])),
    name == 'payment_validation_callback_reconciled', strcat('Payment callback reconciliation completed for payment ', tostring(customDimensions['PaymentId']), '. Status ', tostring(customDimensions['PaymentStatus']), ', remote confirmed: ', tostring(customDimensions['RemoteStatusConfirmed']), ', callback recorded: ', tostring(customDimensions['CallbackRecorded'])),
    name)
| where application == 'API' or cloud_RoleName has 'api'
| project timestamp, tenant, customerOrderId, runPrefix, chargeId, message
),
(
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
)
| order by timestamp asc
"@

$appInsightsWarnings = @()
$apiRows = @()
$uiRows = @()
$apiQueryFailed = $false
$uiQueryFailed = $false

try {
    $apiRows = Convert-AppInsightsRows -Response (Invoke-AppInsightsQuery -Query $apiQuery)
}
catch {
    $apiQueryFailed = $true
    $appInsightsWarnings += "API telemetry query failed: $($_.Exception.Message)"
    if ([string]::IsNullOrWhiteSpace($RunPrefix)) {
        throw "API telemetry query failed and -RunPrefix was not supplied. $($_.Exception.Message)"
    }

    Write-Host "App Insights API telemetry query failed; continuing with DB-only verification for run prefix $RunPrefix." -ForegroundColor Yellow
}

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
$resolvedApiEvents = foreach ($apiEvent in $apiEvents) {
    $resolvedCustomerOrderId = $apiEvent.CustomerOrderId
    $resolvedRunPrefix = $apiEvent.RunPrefix

    if (-not [string]::IsNullOrWhiteSpace($apiEvent.Tenant)) {
        if (-not [string]::IsNullOrWhiteSpace($apiEvent.CustomerOrderId)) {
            $tenantState[$apiEvent.Tenant] = [PSCustomObject] @{
                CustomerOrderId = $apiEvent.CustomerOrderId
                RunPrefix = $apiEvent.RunPrefix
            }
        }
        elseif ($tenantState.ContainsKey($apiEvent.Tenant)) {
            $resolvedCustomerOrderId = $tenantState[$apiEvent.Tenant].CustomerOrderId
            $resolvedRunPrefix = $tenantState[$apiEvent.Tenant].RunPrefix
        }
    }

    [PSCustomObject] @{
        Timestamp = $apiEvent.Timestamp
        Tenant = $apiEvent.Tenant
        CustomerOrderId = $apiEvent.CustomerOrderId
        ResolvedCustomerOrderId = $resolvedCustomerOrderId
        RunPrefix = $apiEvent.RunPrefix
        ResolvedRunPrefix = $resolvedRunPrefix
        ChargeId = $apiEvent.ChargeId
        Message = $apiEvent.Message
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
        throw "No payment run prefixes were found in today's API telemetry for $Environment. Re-run with -RunPrefix to force a DB-only verification pass."
    }
}

if ($availableRunPrefixes.Count -gt 0 -and $availableRunPrefixes -notcontains $selectedRunPrefix) {
    if ([string]::IsNullOrWhiteSpace($RunPrefix)) {
        $prefixList = ($availableRunPrefixes | ForEach-Object { "- $_" }) -join "`n"
        throw "Run prefix '$selectedRunPrefix' was not found in today's API telemetry.`n$prefixList"
    }

    $appInsightsWarnings += "Run prefix '$selectedRunPrefix' was not found in today's API telemetry yet; continuing with DB-backed verification."
    $appInsightsAvailable = $false
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

Write-Step "Querying App Insights browser/UI telemetry"
$uiQuery = @"
union isfuzzy=true
(
customEvents
| where timestamp >= startofday(now() + 330m) - 330m
| where name in ('ui_payment_callback_received',
                 'ui_payment_callback_reconciled',
                 'ui_payment_callback_pending_retry_scheduled',
                 'ui_payment_callback_failed',
                 'ui_payment_callback_confirmation_requested',
                 'ui_payment_callback_confirmed',
                 'ui_payment_callback_confirmation_failed')
| extend application = tostring(customDimensions['Application'])
| extend tenant = tostring(customDimensions['TenantCode'])
| extend customerOrderId = tostring(customDimensions['CustomerOrderId'])
| extend uiEventName = name
| extend chargeId = tostring(customDimensions['PaymentId'])
| extend statusCode = tostring(customDimensions['HttpStatus'])
| extend message = coalesce(tostring(customDimensions['ErrorMessage']), tostring(customDimensions['PaymentStatus']), name)
| where application == 'UI' or cloud_RoleName has 'api' or cloud_RoleName has 'ui'
| project timestamp, tenant, customerOrderId, uiEventName, chargeId, statusCode, message
),
(
traces
| where timestamp >= startofday(now() + 330m) - 330m
| where message has_any('OpenPay callback received',
                        'payment/callback responded',
                        'ui_payment_callback_received',
                        'ui_payment_callback_reconciled',
                        'ui_payment_callback_pending_retry_scheduled',
                        'ui_payment_callback_failed',
                        'ui_payment_callback_confirmation_requested',
                        'ui_payment_callback_confirmed',
                        'ui_payment_callback_confirmation_failed')
| extend application = tostring(customDimensions['Application'])
| extend tenant = coalesce(tostring(customDimensions['TenantCode']), extract(@'for tenant\s+([^,\s]+)', 1, message))
| extend customerOrderId = tostring(customDimensions['CustomerOrderId'])
| extend uiEventName = coalesce(tostring(customDimensions['UiEventName']), extract(@'UI payment event\s+(\S+)\s+on', 1, message))
| extend chargeId = coalesce(tostring(customDimensions['ChargeId']), tostring(customDimensions['PaymentId']), extract(@'for payment\s+([^,\s]+)', 1, message), extract(@'payment\s+([^,\s]+)', 1, message))
| extend statusCode = tostring(customDimensions['StatusCode'])
| where cloud_RoleName has 'api' or cloud_RoleName has 'ui' or application == 'API' or application == 'UI'
| project timestamp, tenant, customerOrderId, uiEventName, chargeId, statusCode, message
)
| order by timestamp asc
"@

try {
    $uiRows = Convert-AppInsightsRows -Response (Invoke-AppInsightsQuery -Query $uiQuery)
}
catch {
    $uiQueryFailed = $true
    $appInsightsWarnings += "UI telemetry query failed: $($_.Exception.Message)"
    Write-Host 'App Insights browser/UI telemetry query failed; continuing with DB-only verification for UI evidence.' -ForegroundColor Yellow
}

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
$preflightShared = @(Invoke-AzureSqlQuery -Database $sharedDbName -UserName $sqlAdminUser -Password $sqlAdminPassword -Query @"
SELECT t.Code AS Tenant, pp.Use3DSecure AS ThreeDSEnabled
FROM payments.PaymentProviders pp
JOIN dbo.Tenants t ON t.Id = pp.TenantId
WHERE pp.ProviderType = t.PaymentProviderCode
  AND t.Status = 'Active'
ORDER BY pp.TenantId;
"@)

$preflightTenantC = @(
    foreach ($tenant in $dedicatedTenants) {
        $assignedProviderCode = ConvertTo-SqlStringLiteral -Value $tenant.PaymentProviderCode
        Invoke-AzureSqlQuery -Database $tenant.DedicatedDatabaseName -UserName $sqlAdminUser -Password $sqlAdminPassword -Query @"
SELECT '$($tenant.TenantCode)' AS Tenant, pp.Use3DSecure AS ThreeDSEnabled
FROM payments.PaymentProviders pp
WHERE pp.ProviderType = N'$assignedProviderCode';
"@
    }
)

$customerOrderSqlPredicate = if (-not [string]::IsNullOrWhiteSpace($CustomerOrderId)) {
    $escapedCustomerOrderId = ConvertTo-SqlStringLiteral -Value $CustomerOrderId.Trim()
    "ct.CustomerOrderId = N'$escapedCustomerOrderId'"
}
else {
    $escapedRunPrefix = ConvertTo-SqlStringLiteral -Value $selectedRunPrefix
    "ct.CustomerOrderId LIKE N'$escapedRunPrefix%'"
}

$q2Shared = @(Invoke-AzureSqlQuery -Database $sharedDbName -UserName $sqlAdminUser -Password $sqlAdminPassword -Query @"
SELECT t.Code AS Tenant, ct.CustomerOrderId, ct.TransactionId AS ChargeId,
       ct.TransactionType, ct.TransactionStatus AS Status, ct.IsThreeDSecureEnabled AS ThreeDS,
       ct.ThreeDSecureStage, ct.TransactionReferenceId AS Ref,
       ct.IsTransactionSuccess AS OK, ct.CreatedDate
FROM payments.CardTransactions ct
JOIN dbo.Tenants t ON t.Id = ct.TenantId
WHERE $customerOrderSqlPredicate
ORDER BY ct.TenantId, ct.CustomerOrderId, ct.Id;
"@)

$q5Shared = @(Invoke-AzureSqlQuery -Database $sharedDbName -UserName $sqlAdminUser -Password $sqlAdminPassword -Query @"
SELECT t.Code AS Tenant, ct.CustomerOrderId, tsh.Status,
       tsh.ThreeDSecureStage AS Stage, tsh.IsThreeDSecureEnabled AS ThreeDS,
       tsh.TransactionReferenceId AS Ref
FROM payments.TransactionStatusHistories tsh
JOIN payments.CardTransactions ct ON ct.Id = tsh.TransactionId
JOIN dbo.Tenants t ON t.Id = ct.TenantId
WHERE $customerOrderSqlPredicate
ORDER BY ct.TenantId, ct.CustomerOrderId, ct.Id, tsh.Id;
"@)

$q8Shared = @()

$q2TenantC = @(
    foreach ($tenant in $dedicatedTenants) {
        Invoke-AzureSqlQuery -Database $tenant.DedicatedDatabaseName -UserName $sqlAdminUser -Password $sqlAdminPassword -Query @"
SELECT '$($tenant.TenantCode)' AS Tenant, ct.CustomerOrderId, ct.TransactionId AS ChargeId,
       ct.TransactionType, ct.TransactionStatus AS Status, ct.IsThreeDSecureEnabled AS ThreeDS,
       ct.ThreeDSecureStage, ct.TransactionReferenceId AS Ref,
       ct.IsTransactionSuccess AS OK, ct.CreatedDate
FROM payments.CardTransactions ct
WHERE $customerOrderSqlPredicate
ORDER BY ct.CustomerOrderId, ct.Id;
"@
    }
)

$q5TenantC = @(
    foreach ($tenant in $dedicatedTenants) {
        Invoke-AzureSqlQuery -Database $tenant.DedicatedDatabaseName -UserName $sqlAdminUser -Password $sqlAdminPassword -Query @"
SELECT '$($tenant.TenantCode)' AS Tenant, ct.CustomerOrderId, tsh.Status, tsh.ThreeDSecureStage AS Stage,
       tsh.IsThreeDSecureEnabled AS ThreeDS, tsh.TransactionReferenceId AS Ref
FROM payments.TransactionStatusHistories tsh
JOIN payments.CardTransactions ct ON ct.Id = tsh.TransactionId
WHERE $customerOrderSqlPredicate
ORDER BY ct.CustomerOrderId, ct.Id, tsh.Id;
"@
    }
)

$q9Shared = @(
    $q2Shared |
        Where-Object {
            $tenantCode = [string](Get-ObjectPropertyValue -Object $_ -PropertyName 'Tenant')
            $dedicatedTenantCodes -contains $tenantCode
        }
)

$q8Shared = @(
    $q2Shared |
        Where-Object {
            $tenantCode = [string](Get-ObjectPropertyValue -Object $_ -PropertyName 'Tenant')
            $sharedTenantCodes.Count -gt 0 -and ($sharedTenantCodes -notcontains $tenantCode)
        }
)

if (-not [string]::IsNullOrWhiteSpace($TenantCode)) {
    $scopedTenantCode = $TenantCode.Trim()
    $q2Shared = @($q2Shared | Where-Object Tenant -eq $scopedTenantCode)
    $q5Shared = @($q5Shared | Where-Object Tenant -eq $scopedTenantCode)
    $q2TenantC = @($q2TenantC | Where-Object Tenant -eq $scopedTenantCode)
    $q5TenantC = @($q5TenantC | Where-Object Tenant -eq $scopedTenantCode)
}

$threeDsByTenant = @{}
foreach ($row in $preflightShared) {
    $tenantCode = [string] (Get-ObjectPropertyValue -Object $row -PropertyName 'Tenant')
    $threeDsValue = Get-ObjectPropertyValue -Object $row -PropertyName 'ThreeDSEnabled'

    if ([string]::IsNullOrWhiteSpace($tenantCode) -or $null -eq $threeDsValue) {
        throw "Shared payment-provider preflight returned an invalid row. Expected columns: Tenant, ThreeDSEnabled."
    }

    $threeDsByTenant[$tenantCode] = [int] $threeDsValue
}

foreach ($tenantRow in $preflightTenantC) {
    $tenantCode = [string](Get-ObjectPropertyValue -Object $tenantRow -PropertyName 'Tenant')
    $threeDsValue = Get-ObjectPropertyValue -Object $tenantRow -PropertyName 'ThreeDSEnabled'
    if ([string]::IsNullOrWhiteSpace($tenantCode) -or $null -eq $threeDsValue) {
        throw 'Dedicated payment-provider preflight returned an invalid row. Expected columns: Tenant, ThreeDSEnabled.'
    }

    $threeDsByTenant[$tenantCode] = [int]$threeDsValue
}

foreach ($tenant in $tenantTopology) {
    if (-not $threeDsByTenant.ContainsKey($tenant.TenantCode)) {
        throw "Payment-provider baseline is missing for active tenant '$($tenant.TenantCode)' in its resolved database contract."
    }
}

$expectedOrdersByTenant = @{}
foreach ($tenantGroup in ($selectedApiEvents | Where-Object { -not [string]::IsNullOrWhiteSpace($_.ResolvedCustomerOrderId) } | Group-Object Tenant)) {
    $expectedOrdersByTenant[$tenantGroup.Name] = @($tenantGroup.Group | Select-Object -ExpandProperty ResolvedCustomerOrderId -Unique)
}

if ($expectedOrdersByTenant.Count -eq 0) {
    $sharedOrdersByTenant = $q2Shared | Group-Object Tenant
    foreach ($tenantGroup in $sharedOrdersByTenant) {
        $expectedOrdersByTenant[$tenantGroup.Name] = @($tenantGroup.Group | Select-Object -ExpandProperty CustomerOrderId -Unique)
    }

    foreach ($tenantGroup in ($q2TenantC | Group-Object Tenant)) {
        $expectedOrdersByTenant[$tenantGroup.Name] = @($tenantGroup.Group | Select-Object -ExpandProperty CustomerOrderId -Unique)
    }
}

$sharedDbChargeIds = @($q2Shared | Select-Object -ExpandProperty ChargeId)
$tenantCDbChargeIds = @($q2TenantC | Select-Object -ExpandProperty ChargeId)
$allDbChargeIds = @($sharedDbChargeIds + $tenantCDbChargeIds)
$allDbChargeRows = @(@($q2Shared) + @($q2TenantC))
$providerDbChargeRows = @(
    $allDbChargeRows |
        Where-Object {
            $chargeId = [string](Get-ObjectPropertyValue -Object $_ -PropertyName 'ChargeId')
            $transactionType = [string](Get-ObjectPropertyValue -Object $_ -PropertyName 'TransactionType')
            -not [string]::IsNullOrWhiteSpace($chargeId) -and
                $transactionType -eq 'charge'
        }
)

$providerDbChargeIds = @($providerDbChargeRows | Select-Object -ExpandProperty ChargeId -Unique)
$providerCorrelationIds = if (-not [string]::IsNullOrWhiteSpace($ProviderPaymentId)) {
    @($ProviderPaymentId.Trim())
}
else {
    @($providerDbChargeIds)
}
$transportEvidence = @()

if ($providerCorrelationIds.Count -gt 0) {
    $providerChargeIdList = Get-KqlQuotedValues -Values $providerCorrelationIds
    $transportQuery = @"
union isfuzzy=true
(
requests
| where timestamp >= ago(7d)
| extend telemetryType = 'request'
| extend detail = strcat(name, ' ', url)
| where detail has_any ($providerChargeIdList)
| where success == true
| project timestamp, telemetryType, operation_Id, cloud_RoleName, name, resultCode, success, target='', detail
),
(
dependencies
| where timestamp >= ago(7d)
| extend telemetryType = 'dependency'
| extend detail = strcat(name, ' ', data, ' ', target)
| where detail has_any ($providerChargeIdList)
| where success == true
| project timestamp, telemetryType, operation_Id, cloud_RoleName, name, resultCode, success, target, detail
)
| order by timestamp asc
"@

    try {
        $transportRows = @(Convert-AppInsightsRows -Response (Invoke-AppInsightsQuery -Query $transportQuery))
        $transportEvidence = @(
            foreach ($providerChargeId in $providerCorrelationIds) {
                $matchingRows = @(
                    $transportRows |
                        Where-Object {
                            ([string]$_.detail).IndexOf($providerChargeId, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
                        }
                )
                $requestOperationIds = @(
                    $matchingRows |
                        Where-Object telemetryType -eq 'request' |
                        Select-Object -ExpandProperty operation_Id -Unique
                )
                $dependencyOperationIds = @(
                    $matchingRows |
                        Where-Object telemetryType -eq 'dependency' |
                        Select-Object -ExpandProperty operation_Id -Unique
                )
                $correlatedOperationIds = @(
                    $requestOperationIds |
                        Where-Object { $dependencyOperationIds -contains $_ } |
                        Sort-Object -Unique
                )

                [PSCustomObject]@{
                    ChargeId = $providerChargeId
                    RequestCount = @($matchingRows | Where-Object telemetryType -eq 'request').Count
                    DependencyCount = @($matchingRows | Where-Object telemetryType -eq 'dependency').Count
                    CorrelatedOperationIds = $correlatedOperationIds
                    Correlated = ($correlatedOperationIds.Count -gt 0)
                    Rows = @($matchingRows | Select-Object timestamp, telemetryType, operation_Id, cloud_RoleName, name, resultCode, target, detail)
                }
            }
        )
    }
    catch {
        $appInsightsWarnings += "Provider payment transport query failed: $($_.Exception.Message)"
        Write-Host 'App Insights request/dependency correlation query failed.' -ForegroundColor Yellow
    }
}
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
    union isfuzzy=true
    (
    customEvents
| where timestamp >= ago(7d)
    | where name in ('payment_validation_attempt_created',
             'payment_validation_charge_created',
             'payment_validation_callback_reconciled')
| extend application = tostring(customDimensions['Application'])
| extend tenant = tostring(customDimensions['TenantCode'])
    | extend customerOrderId = tostring(customDimensions['CustomerOrderId'])
    | extend runPrefix = coalesce(tostring(customDimensions['RunPrefix']), extract(@'^(OR-\d+-[^-]+)', 1, customerOrderId))
    | extend chargeId = tostring(customDimensions['PaymentId'])
    | extend message = case(
        name == 'payment_validation_attempt_created', strcat('Generated payment attempt order id ', tostring(customDimensions['AttemptOrderId']), ' and payment trace id ', tostring(customDimensions['PaymentTraceId']), ' from customer order id ', customerOrderId),
        name == 'payment_validation_charge_created', strcat('Charge created with ID: ', tostring(customDimensions['PaymentId'])),
        name == 'payment_validation_callback_reconciled', strcat('Payment callback reconciliation completed for payment ', tostring(customDimensions['PaymentId']), '. Status ', tostring(customDimensions['PaymentStatus']), ', remote confirmed: ', tostring(customDimensions['RemoteStatusConfirmed']), ', callback recorded: ', tostring(customDimensions['CallbackRecorded'])),
        name)
    | where application == 'API' or cloud_RoleName has 'api'
| where chargeId in ($dbChargeIdList)
| project timestamp, tenant, customerOrderId, runPrefix, chargeId, message
    ),
    (
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
    )
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

$transportApiEvents = @(
    foreach ($evidence in ($transportEvidence | Where-Object Correlated)) {
        if (@($apiChargeEvents | Where-Object ChargeId -eq $evidence.ChargeId).Count -gt 0) {
            continue
        }

        $dbRow = $providerDbChargeRows | Where-Object ChargeId -eq $evidence.ChargeId | Select-Object -First 1
        if ($null -eq $dbRow -and $providerDbChargeRows.Count -eq 1) {
            $dbRow = $providerDbChargeRows | Select-Object -First 1
        }
        if ($null -eq $dbRow) {
            continue
        }

        $evidenceRows = @($evidence.Rows)
        $timestamp = if ($evidenceRows.Count -gt 0) {
            [datetimeoffset]($evidenceRows | Sort-Object timestamp | Select-Object -First 1).timestamp
        }
        else {
            [datetimeoffset](Get-ObjectPropertyValue -Object $dbRow -PropertyName 'CreatedDate')
        }
        $tenant = [string](Get-ObjectPropertyValue -Object $dbRow -PropertyName 'Tenant')
        $customerOrderId = [string](Get-ObjectPropertyValue -Object $dbRow -PropertyName 'CustomerOrderId')

        [PSCustomObject]@{
            Timestamp = $timestamp
            Tenant = $tenant
            CustomerOrderId = $customerOrderId
            ResolvedCustomerOrderId = $customerOrderId
            RunPrefix = $selectedRunPrefix
            ResolvedRunPrefix = $selectedRunPrefix
            ChargeId = [string]$evidence.ChargeId
            Message = "Provider payment ID correlated through successful requests and dependencies."
        }
    }
)

if ($transportApiEvents.Count -gt 0) {
    $selectedApiEvents = @($selectedApiEvents + $transportApiEvents | Sort-Object Timestamp)
    $apiChargeEvents = @($apiChargeEvents + $transportApiEvents | Sort-Object Timestamp)
    $appInsightsAvailable = $true
}

$apiChargeIds = @($apiChargeEvents | Select-Object -ExpandProperty ChargeId -Unique)
$knownUiChargeIds = @($apiChargeIds + $allDbChargeIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
$selectedUiEvents = @(Get-ScopedUiEvents -Events @($uiEvents) -KnownChargeIds $knownUiChargeIds -KnownTenants $expectedUiTenants -KnownCustomerOrders $expectedUiCustomerOrders)

if ($selectedUiEvents.Count -eq 0) {
    $evidenceChargeIds = if ($apiChargeIds.Count -gt 0) { $apiChargeIds } else { @($allDbChargeIds | Sort-Object -Unique) }
    $evidenceChargeIdList = Get-KqlQuotedValues -Values $evidenceChargeIds
    if (-not [string]::IsNullOrWhiteSpace($evidenceChargeIdList)) {
        $fallbackUiQuery = @"
    union isfuzzy=true
    (
    customEvents
| where timestamp >= ago(7d)
    | where name in ('ui_payment_callback_received',
             'ui_payment_callback_reconciled',
             'ui_payment_callback_pending_retry_scheduled',
             'ui_payment_callback_failed',
             'ui_payment_callback_confirmation_requested',
             'ui_payment_callback_confirmed',
             'ui_payment_callback_confirmation_failed')
| extend application = tostring(customDimensions['Application'])
    | extend tenant = tostring(customDimensions['TenantCode'])
| extend customerOrderId = tostring(customDimensions['CustomerOrderId'])
    | extend uiEventName = name
    | extend chargeId = tostring(customDimensions['PaymentId'])
    | extend statusCode = tostring(customDimensions['HttpStatus'])
    | extend message = coalesce(tostring(customDimensions['ErrorMessage']), tostring(customDimensions['PaymentStatus']), name)
    | where application == 'UI' or cloud_RoleName has 'api' or cloud_RoleName has 'ui'
| where chargeId in ($evidenceChargeIdList)
   or tenant in ({0})
| project timestamp, tenant, customerOrderId, uiEventName, chargeId, statusCode, message
    ),
    (
    traces
    | where timestamp >= ago(7d)
    | where message has_any('OpenPay callback received',
                'payment/callback responded',
            'ui_payment_callback_received',
            'ui_payment_callback_reconciled',
            'ui_payment_callback_pending_retry_scheduled',
            'ui_payment_callback_failed',
                'ui_payment_callback_confirmation_requested',
                'ui_payment_callback_confirmed',
                'ui_payment_callback_confirmation_failed')
    | extend application = tostring(customDimensions['Application'])
    | extend tenant = coalesce(tostring(customDimensions['TenantCode']), extract(@'for tenant\s+([^,\s]+)', 1, message))
    | extend customerOrderId = tostring(customDimensions['CustomerOrderId'])
    | extend uiEventName = coalesce(tostring(customDimensions['UiEventName']), extract(@'UI payment event\s+(\S+)\s+on', 1, message))
    | extend chargeId = coalesce(tostring(customDimensions['ChargeId']), tostring(customDimensions['PaymentId']), extract(@'for payment\s+([^,\s]+)', 1, message), extract(@'payment\s+([^,\s]+)', 1, message))
    | extend statusCode = tostring(customDimensions['StatusCode'])
    | where cloud_RoleName has 'api' or cloud_RoleName has 'ui' or application == 'API' or application == 'UI'
    | where chargeId in ($evidenceChargeIdList)
       or tenant in ({0})
    | project timestamp, tenant, customerOrderId, uiEventName, chargeId, statusCode, message
    )
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

if (($apiQueryFailed -or $uiQueryFailed) -and $selectedApiEvents.Count -eq 0 -and $selectedUiEvents.Count -eq 0) {
    $appInsightsAvailable = $false
}

$globalUiStatusCodes = @($selectedUiEvents | Where-Object { -not [string]::IsNullOrWhiteSpace($_.StatusCode) } | Select-Object -ExpandProperty StatusCode -Unique)
$matchedUiEventKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$usedFallbackUiEventKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$callbackUiEvents = @($selectedUiEvents | Where-Object { Test-IsCallbackEvent -Event $_ })

$chargeCorrelation = @(
foreach ($chargeEvent in $apiChargeEvents) {
    $uiMatches = @($callbackUiEvents | Where-Object { $_.ChargeId -eq $chargeEvent.ChargeId })
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
            $callbackUiEvents |
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

    $dbCandidates = @($q2Shared) + @($q2TenantC)
    $dbRow = $dbCandidates | Where-Object ChargeId -eq $chargeEvent.ChargeId | Select-Object -First 1

    if ($null -eq $dbRow -and -not [string]::IsNullOrWhiteSpace($chargeEvent.ResolvedCustomerOrderId)) {
        $dbRow = $dbCandidates |
            Where-Object {
                $_.Tenant -eq $chargeEvent.Tenant -and
                $_.CustomerOrderId -eq $chargeEvent.ResolvedCustomerOrderId
            } |
            Select-Object -First 1
    }

    $chargeThreeDsEnabled = if ($null -ne $dbRow) {
        [int](Get-ObjectPropertyValue -Object $dbRow -PropertyName 'ThreeDS')
    }
    else {
        [int]$threeDsByTenant[$chargeEvent.Tenant]
    }

    [PSCustomObject] @{
        ChargeId = $chargeEvent.ChargeId
        Tenant = $chargeEvent.Tenant
        CustomerOrderId = $chargeEvent.ResolvedCustomerOrderId
        InDb = ($null -ne $dbRow)
        DbStatus = if ($null -ne $dbRow) { [string] (Get-ObjectPropertyValue -Object $dbRow -PropertyName 'Status') } else { '' }
        DbStage = if ($null -ne $dbRow) { [string] (Get-ObjectPropertyValue -Object $dbRow -PropertyName 'ThreeDSecureStage') } else { '' }
        ThreeDSEnabled = $chargeThreeDsEnabled
        UiCallbackExpected = ($chargeThreeDsEnabled -eq 1) -and (-not ($chargeEvent.ChargeId -match '^order_'))
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

function Get-ExpectedHistoryStepsForTenant {
    param(
        [Parameter(Mandatory = $true)] [string] $TenantCode,
        [Parameter(Mandatory = $true)] [string[]] $CustomerOrderIds,
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [object[]] $RunApiEvents,
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [object[]] $RunChargeEvents,
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [object[]] $TransactionRows,
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [object[]] $HistoryRows,
        [Parameter(Mandatory = $true)] [hashtable] $TenantThreeDsByTenant
    )

    $expectedSteps = 0

    foreach ($customerOrderId in $CustomerOrderIds) {
        $orderApiEvents = @(
            $RunApiEvents |
                Where-Object {
                    $_.Tenant -eq $TenantCode -and
                    $_.ResolvedCustomerOrderId -eq $customerOrderId
                }
        )

        $orderChargeEvents = @(
            $RunChargeEvents |
                Where-Object {
                    $_.Tenant -eq $TenantCode -and
                    $_.ResolvedCustomerOrderId -eq $customerOrderId
                }
        )

        $orderTransactionRows = @(
            $TransactionRows |
                Where-Object {
                    $_.CustomerOrderId -eq $customerOrderId -and
                    $_.Tenant -eq $TenantCode
                }
        )

        $orderHistoryRows = @(
            $HistoryRows |
                Where-Object {
                    $_.CustomerOrderId -eq $customerOrderId -and
                    $_.Tenant -eq $TenantCode
                }
        )

        $runtimeThreeDsEnabled = $false
        $hasOrderLevelRuntimeEvidence = ($orderApiEvents.Count -gt 0) -or ($orderTransactionRows.Count -gt 0) -or ($orderHistoryRows.Count -gt 0)

        if (@($orderApiEvents | Where-Object { $_.PSObject.Properties.Name -contains 'IsThreeDSecureEnabled' -and $_.IsThreeDSecureEnabled }).Count -gt 0) {
            $runtimeThreeDsEnabled = $true
        }
        elseif (@($orderTransactionRows | Where-Object { $_.ThreeDS -eq 1 -or [string] $_.ThreeDSecureStage -match 'redirect|challenge|authenticated' }).Count -gt 0) {
            $runtimeThreeDsEnabled = $true
        }
        elseif (@($orderHistoryRows | Where-Object { $_.ThreeDS -eq 1 -or [string] $_.Stage -match 'redirect|challenge|authenticated' }).Count -gt 0) {
            $runtimeThreeDsEnabled = $true
        }
        elseif (-not $hasOrderLevelRuntimeEvidence -and $TenantThreeDsByTenant.ContainsKey($TenantCode) -and $TenantThreeDsByTenant[$TenantCode] -eq 1) {
            $runtimeThreeDsEnabled = $true
        }

        $uniqueChargeIds = @(
            $orderChargeEvents |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_.ChargeId) } |
                Select-Object -ExpandProperty ChargeId -Unique
        )

        $expectedSteps += $(if ($runtimeThreeDsEnabled) { 4 } else { 2 })

        if (-not $runtimeThreeDsEnabled -and $uniqueChargeIds.Count -gt 1) {
            $expectedSteps += ($uniqueChargeIds.Count - 1)
        }
        elseif (
            -not $runtimeThreeDsEnabled -and
            @($orderHistoryRows | Where-Object { [string] $_.Stage -eq 'tokenization_completed' }).Count -gt 0
        ) {
            $expectedSteps += 1
        }
    }

    return $expectedSteps
}

$checks = [ordered] @{}
$expectedStepsByTenant = @{}
$transactionRowsForHistory = @(@($q2Shared) + @($q2TenantC))
$historyRowsForHistory = @(@($q5Shared) + @($q5TenantC))
foreach ($tenantCode in $expectedOrdersByTenant.Keys) {
    $expectedStepsByTenant[$tenantCode] = Get-ExpectedHistoryStepsForTenant -TenantCode $tenantCode -CustomerOrderIds $expectedOrdersByTenant[$tenantCode] -RunApiEvents $selectedApiEvents -RunChargeEvents $apiChargeEvents -TransactionRows $transactionRowsForHistory -HistoryRows $historyRowsForHistory -TenantThreeDsByTenant $threeDsByTenant
}

$allRows = @(@($q2Shared) + @($q2TenantC))
$allHistoryRows = @(@($q5Shared) + @($q5TenantC))
foreach ($tenantCode in ($expectedOrdersByTenant.Keys | Sort-Object)) {
    $checks["Pre-flight 3DS [$tenantCode]"] = Convert-CheckResult -Expected 'configured' -Actual ([string] $threeDsByTenant[$tenantCode]) -Outcome $(if ($threeDsByTenant.ContainsKey($tenantCode)) { 'PASS' } else { 'FAIL' })
    $tenantRows = @($allRows | Where-Object { $_.Tenant -eq $tenantCode })
    $tenantHistoryRows = @($allHistoryRows | Where-Object { $_.Tenant -eq $tenantCode })
    $checks["Q2 rows [$tenantCode]"] = Convert-CheckResult -Expected ([string] ($expectedOrdersByTenant[$tenantCode].Count * 2)) -Actual ([string] $tenantRows.Count) -Outcome $(if ($tenantRows.Count -eq ($expectedOrdersByTenant[$tenantCode].Count * 2)) { 'PASS' } else { 'FAIL' })
    $checks["Q5 steps [$tenantCode]"] = Convert-CheckResult -Expected ([string] $expectedStepsByTenant[$tenantCode]) -Actual ([string] $tenantHistoryRows.Count) -Outcome $(if ($tenantHistoryRows.Count -eq $expectedStepsByTenant[$tenantCode]) { 'PASS' } else { 'FAIL' })
}
$checks['Q8 bleed'] = Convert-CheckResult -Expected '0' -Actual ([string] @($q8Shared).Count) -Outcome $(if (@($q8Shared).Count -eq 0) { 'PASS' } else { 'FAIL' })
$checks['Q9 bleed'] = Convert-CheckResult -Expected '0' -Actual ([string] @($q9Shared).Count) -Outcome $(if (@($q9Shared).Count -eq 0) { 'PASS' } else { 'FAIL' })

$correlatedTransportCount = @($transportEvidence | Where-Object Correlated).Count
$checks['Provider payment IDs -> request/dependency correlation'] = Convert-CheckResult `
    -Expected ([string]$providerCorrelationIds.Count) `
    -Actual ([string]$correlatedTransportCount) `
    -Outcome $(if ($providerCorrelationIds.Count -gt 0 -and $correlatedTransportCount -eq $providerCorrelationIds.Count) { 'PASS' } else { 'FAIL' })

if ($apiChargeEvents.Count -eq 0) {
    $checks['API log -> DB charge IDs'] = Convert-CheckResult -Expected 'App Insights charge rows' -Actual 'No API charge rows returned for the selected run prefix' -Outcome 'INCONCLUSIVE'
}
else {
    $checks['API log -> DB charge IDs'] = Convert-CheckResult -Expected ([string] @($apiChargeEvents).Count) -Actual ([string] @($chargeCorrelation | Where-Object InDb).Count) -Outcome $(if (@($chargeCorrelation | Where-Object InDb).Count -eq @($apiChargeEvents).Count) { 'PASS' } else { 'FAIL' })
}

$expectedUiCallbacks = @($chargeCorrelation | Where-Object UiCallbackExpected).Count
$actualUiCallbacks = @($chargeCorrelation | Where-Object { $_.UiCallbackExpected -and $_.UiCallbackLogged }).Count
if ($apiChargeEvents.Count -eq 0 -and $selectedUiEvents.Count -eq 0) {
    $checks['UI telemetry -> callbacks present where expected'] = Convert-CheckResult -Expected '3DS tenants only' -Actual 'No browser/UI telemetry rows returned for the selected run prefix' -Outcome 'INCONCLUSIVE'
}
else {
    $checks['UI telemetry -> callbacks present where expected'] = Convert-CheckResult -Expected ([string] $expectedUiCallbacks) -Actual ([string] $actualUiCallbacks) -Outcome $(if ($actualUiCallbacks -eq $expectedUiCallbacks) { 'PASS' } else { 'FAIL' })
}

$report = [PSCustomObject] @{
    Environment = $Environment
    Runtime = 'azure'
    RunPrefix = $selectedRunPrefix
    AppInsightsAvailable = $appInsightsAvailable
    Warnings = @($appInsightsWarnings)
    AppInsights = [PSCustomObject] @{
        ApiEvidence = @($selectedApiEvents | Select-Object Timestamp, Tenant, ResolvedCustomerOrderId, ChargeId, Message)
        UiEvidence = @($reportedUiEvents | Select-Object Timestamp, Tenant, CustomerOrderId, UiEventName, ChargeId, StatusCode, Message)
        TransportEvidence = @($transportEvidence)
    }
    Topology = @(
        $tenantTopology |
            Select-Object @{ Name = 'tenantCode'; Expression = { $_.TenantCode } },
                          @{ Name = 'active'; Expression = { $_.Active } },
                          @{ Name = 'tier'; Expression = { $_.TenantTier } },
                          @{ Name = 'providerCode'; Expression = { $_.PaymentProviderCode } },
                          @{ Name = 'dedicatedDatabaseName'; Expression = { $_.DedicatedDatabaseName } },
                          @{ Name = 'dedicatedConnectionSecret'; Expression = { $_.DedicatedConnectionSecret } },
                          @{ Name = 'providerPrivateKeyAlias'; Expression = { $_.ProviderPrivateKeyAlias } },
                          @{ Name = 'contractStatus'; Expression = { $_.ContractStatus } }
    )
    Preflight = Convert-HashtableToObject -Table $threeDsByTenant
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
