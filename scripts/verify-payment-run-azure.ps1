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
    prefix is found in the selected telemetry window, that prefix is used automatically.

.PARAMETER CustomerOrderId
    Optional persisted customer order ID for an individual automation journey.
    SQL evidence is scoped to this exact ID when supplied.

.PARAMETER OrderReferenceId
    Optional persisted authoritative order reference for an individual automation journey.
    SQL evidence is additionally scoped to this exact order reference when supplied.

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
    [datetimeoffset] $StartedUtc,

    [Parameter(Mandatory = $false)]
    [datetimeoffset] $FinishedUtc,

    [Parameter(Mandatory = $false)]
    [string] $CustomerOrderId,

    [Parameter(Mandatory = $false)]
    [string] $OrderReferenceId,

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
    [int] $PreQueryDelaySeconds = 0,

    [Parameter(Mandatory = $false)]
    [string] $RunAttempt = '1',

    [Parameter(Mandatory = $false)]
    [string] $FirewallLeaseManifestPath,

    [Parameter(Mandatory = $false)]
    [ValidateSet('KeyVault', 'Entra')]
    [string] $SqlAuthenticationMode = 'KeyVault',

    [Parameter(Mandatory = $false)]
    [switch] $PreflightOnly,

    [Parameter(Mandatory = $false)]
    [string] $PreflightReportPath,

    [Parameter(Mandatory = $false)]
    [string] $ExpectedSubscriptionId
)

$requestedTenantCode = $TenantCode
. (Join-Path $PSScriptRoot 'phase10-paid-order-evidence.ps1')
if (($PSBoundParameters.ContainsKey('StartedUtc')) -xor ($PSBoundParameters.ContainsKey('FinishedUtc'))) {
    throw 'StartedUtc and FinishedUtc must be supplied together.'
}
if ($PSBoundParameters.ContainsKey('StartedUtc') -and $FinishedUtc -le $StartedUtc) {
    throw 'FinishedUtc must be later than StartedUtc.'
}
if ($PSBoundParameters.ContainsKey('StartedUtc')) {
    $telemetryWindowStartUtc = $StartedUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ', [Globalization.CultureInfo]::InvariantCulture)
    $telemetryWindowEndUtc = $FinishedUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ', [Globalization.CultureInfo]::InvariantCulture)
    $script:TelemetryTimeFilter = "timestamp between (datetime($telemetryWindowStartUtc) .. datetime($telemetryWindowEndUtc))"
}
else {
    $script:TelemetryTimeFilter = 'timestamp >= ago(7d)'
}
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'phase10-azure-firewall-lease.ps1')
. (Join-Path $PSScriptRoot 'phase10-appinsights-query.ps1')
$script:AzureSqlFirewallLease = $null
$script:AzureSqlFirewallLeaseManifestPath = $null
$script:AppInsightsQueryOutcomes = [System.Collections.Generic.List[object]]::new()

function Invoke-AzureCliForFirewallLease {
    param([string[]]$Arguments)
    & az @Arguments 2>&1
    $global:LASTEXITCODE = $LASTEXITCODE
}

function Close-AzureSqlFirewallLease {
    if ($null -ne $script:AzureSqlFirewallLease) {
        Remove-Phase10FirewallLease -ManifestPath $script:AzureSqlFirewallLease.ManifestPath -InvokeAz ${function:Invoke-AzureCliForFirewallLease}
        $script:AzureSqlFirewallLease = $null
    }
    elseif (-not [string]::IsNullOrWhiteSpace($script:AzureSqlFirewallLeaseManifestPath) -and (Test-Path -LiteralPath $script:AzureSqlFirewallLeaseManifestPath)) {
        Remove-Phase10FirewallLease -ManifestPath $script:AzureSqlFirewallLeaseManifestPath -InvokeAz ${function:Invoke-AzureCliForFirewallLease}
    }
}

trap {
    $primaryError = $_
    try { Close-AzureSqlFirewallLease }
    catch { Write-Warning 'SQL firewall lease cleanup failed; inspect the sanitized lease manifest for recovery.' }
    throw $primaryError
}

$resourceEnvironment = switch ($Environment) {
    'staging' { 'stg' }
    default { $Environment }
}
$logicalEnvironment = switch ($Environment) {
    'stg' { 'staging' }
    default { $Environment }
}

$envSuffix = $resourceEnvironment
$resourceGroup = if ([string]::IsNullOrWhiteSpace($env:XYDATALABS_AZURE_RESOURCE_GROUP_NAME)) { "rg-orderprocessing-$envSuffix" } else { $env:XYDATALABS_AZURE_RESOURCE_GROUP_NAME }
$appInsightsName = if ([string]::IsNullOrWhiteSpace($env:XYDATALABS_AZURE_APP_INSIGHTS_NAME)) { "ai-orderprocessing-$envSuffix" } else { $env:XYDATALABS_AZURE_APP_INSIGHTS_NAME }
$keyVaultName = if ([string]::IsNullOrWhiteSpace($env:XYDATALABS_AZURE_KEY_VAULT_NAME)) { "kv-orderprocessing-$envSuffix" } else { $env:XYDATALABS_AZURE_KEY_VAULT_NAME }
$sqlServerName = if ([string]::IsNullOrWhiteSpace($env:XYDATALABS_AZURE_SQL_SERVER_NAME)) { "orderprocessing-sql-$envSuffix" } else { $env:XYDATALABS_AZURE_SQL_SERVER_NAME }
$sqlServerFqdn = "$sqlServerName.database.windows.net"
$supportedTenantTiers = @('SharedPool', 'Dedicated')
$supportedProviders = @('OpenPay', 'Razorpay')
$sharedDbName = switch ($logicalEnvironment) {
    'dev' { 'OrderProcessingSystem_Dev' }
    'staging' { 'OrderProcessingSystem_Staging' }
    'prod' { 'OrderProcessingSystem_Prod' }
}
$script:SqlAuthenticationMode = $SqlAuthenticationMode
$script:SqlAdminUser = $null
$script:SqlAdminPassword = $null
$script:SqlAccessToken = $null
$script:DedicatedDatabaseByTenant = @{}

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

function Get-CollectionCount {
    param([Parameter(Mandatory = $false)] [object] $Value)

    return @($Value).Count
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
    return ConvertTo-Phase10AppInsightsRows -Response $Response
}

function Invoke-AppInsightsQuery {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Query,

        [Parameter(Mandatory = $true)]
        [string] $Purpose,

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
                --only-show-errors 2>&1
            $exitCode = $LASTEXITCODE
            $response = ConvertFrom-Phase10AppInsightsCliResult -Output @($raw) -ExitCode $exitCode -Operation $Purpose
            $rowCount = (Get-CollectionCount -Value (ConvertTo-Phase10AppInsightsRows -Response $response))
            $script:AppInsightsQueryOutcomes.Add([PSCustomObject]@{ purpose = $Purpose; status = 'PASS'; rowCount = $rowCount })
            return $response
        }
        catch {
            if ($attempt -ge $MaxAttempts) {
                $script:AppInsightsQueryOutcomes.Add([PSCustomObject]@{ purpose = $Purpose; status = 'FAIL'; failure = [string]$_.Exception.Message })
                throw
            }

            Write-Host "App Insights query '$Purpose' attempt $attempt of $MaxAttempts failed." -ForegroundColor Yellow
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

        [Parameter(Mandatory = $false)]
        [string] $UserName,

        [Parameter(Mandatory = $false)]
        [string] $Password
    )

    if ($Database -notmatch '^[A-Za-z0-9_]+$') {
        throw 'SQL database name contains unsupported characters.'
    }

    $connectionString = "Server=tcp:$sqlServerFqdn,1433;Initial Catalog=$Database;Persist Security Info=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
    $connection = [System.Data.SqlClient.SqlConnection]::new($connectionString)
    try {
        if ($script:SqlAuthenticationMode -eq 'Entra') {
            if ([string]::IsNullOrWhiteSpace($script:SqlAccessToken)) {
                throw 'Entra SQL authentication was selected but no access token is available.'
            }
            $connection.AccessToken = $script:SqlAccessToken
        }
        else {
            $effectiveUserName = if ([string]::IsNullOrWhiteSpace($UserName)) { $script:SqlAdminUser } else { $UserName }
            $effectivePassword = if ([string]::IsNullOrWhiteSpace($Password)) { $script:SqlAdminPassword } else { $Password }
            if ([string]::IsNullOrWhiteSpace($effectiveUserName) -or [string]::IsNullOrWhiteSpace($effectivePassword)) {
                throw 'Key Vault SQL authentication requires the SQL administrator credentials.'
            }
            $connection.ConnectionString = "$connectionString User ID=$effectiveUserName;Password=$effectivePassword;"
        }

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

    if ((Get-CollectionCount -Value $normalizedValues) -eq 0) {
        return ''
    }

    return ($normalizedValues | ForEach-Object { "'{0}'" -f $_.Replace("'", "''") }) -join ', '
}

function ConvertTo-SqlStringLiteral {
    param([Parameter(Mandatory = $true)][string]$Value)

    return $Value.Replace("'", "''")
}

function Ensure-AzureSqlFirewallAccess {
    $publicIp = Get-PublicIpAddress
    $subscriptionId = Invoke-AzureCliText -Operation 'Resolve active Azure subscription' -Command {
        az account show --query id -o tsv
    }
    $attempt = if (-not [string]::IsNullOrWhiteSpace($env:PHASE10_FIREWALL_RUN_ATTEMPT)) { $env:PHASE10_FIREWALL_RUN_ATTEMPT } elseif (-not [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ATTEMPT)) { $env:GITHUB_RUN_ATTEMPT } else { $RunAttempt }
    $runIdentity = if (-not [string]::IsNullOrWhiteSpace($env:PHASE10_FIREWALL_RUN_ID)) { $env:PHASE10_FIREWALL_RUN_ID } elseif (-not [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID)) { $env:GITHUB_RUN_ID } else { "local-$([guid]::NewGuid().ToString('N'))" }
    $manifestPath = if (-not [string]::IsNullOrWhiteSpace($FirewallLeaseManifestPath)) { $FirewallLeaseManifestPath } elseif (-not [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) { Join-Path $env:RUNNER_TEMP "phase10-sql-firewall-lease-payment-$runIdentity-$attempt-$([guid]::NewGuid().ToString('N')).json" } else { Join-Path ([IO.Path]::GetTempPath()) "phase10-sql-firewall-lease-payment-$runIdentity-$attempt-$([guid]::NewGuid().ToString('N')).json" }
    $script:AzureSqlFirewallLeaseManifestPath = $manifestPath
    $script:AzureSqlFirewallLease = New-Phase10FirewallLease -Environment $resourceEnvironment -SubscriptionId $subscriptionId -ResourceGroup $resourceGroup -Server $sqlServerName -PublicIp $publicIp -RunId $runIdentity -Attempt $attempt -InvocationId ([guid]::NewGuid().ToString('N')) -ManifestPath $manifestPath -InvokeAz ${function:Invoke-AzureCliForFirewallLease}
    Write-Host "Azure SQL firewall lease opened for this verifier invocation. Manifest: $manifestPath" -ForegroundColor Green
}

function Get-MinimumTimeDeltaSeconds {
    param(
        [Parameter(Mandatory = $true)]
        [datetimeoffset] $CandidateTimestamp,

        [Parameter(Mandatory = $true)]
        [datetimeoffset[]] $ReferenceTimestamps
    )

    if ((Get-CollectionCount -Value $ReferenceTimestamps) -eq 0) {
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

    if ($null -eq $Events -or (Get-CollectionCount -Value $Events) -eq 0) {
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

    if ((Get-CollectionCount -Value $directMatches) -gt 0) {
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
    param()

    $registryRows = @(Invoke-AzureSqlQuery -Database $sharedDbName -Query @"
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

    if ((Get-CollectionCount -Value $registryRows) -eq 0) {
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
            if ($script:SqlAuthenticationMode -eq 'Entra') {
                $databaseMatches = @($script:DedicatedDatabaseByTenant[$tenantCode.ToLowerInvariant()])
                if ($databaseMatches.Count -ne 1) {
                    throw "Tenant registry contract failure: dedicated tenant '$tenantCode' must map to exactly one Azure SQL database tagged with tenant='$tenantCode'."
                }
                $dedicatedDatabaseName = [string]$databaseMatches[0]
            }
            else {
                $dedicatedConnectionString = Invoke-AzureCliText -Operation "Resolve $dedicatedSecretName from Key Vault" -Command {
                    az keyvault secret show --vault-name $keyVaultName --name $dedicatedSecretName --query value -o tsv
                }

                if ([string]::IsNullOrWhiteSpace($dedicatedConnectionString)) {
                    throw "Tenant registry contract failure: dedicated tenant '$tenantCode' is missing Key Vault secret '$dedicatedSecretName'."
                }

                $dedicatedDatabaseName = Resolve-DatabaseNameFromConnectionString -ConnectionString $dedicatedConnectionString
            }
        }

        $providerPrivateKeyAlias = "PaymentProviders--$tenantCode--$providerCode--PrivateKey"
        if ($script:SqlAuthenticationMode -eq 'KeyVault') {
            $providerPrivateKeyValue = Invoke-AzureCliText -Operation "Resolve $providerPrivateKeyAlias from Key Vault" -Command {
                az keyvault secret show --vault-name $keyVaultName --name $providerPrivateKeyAlias --query value -o tsv
            }

            if ([string]::IsNullOrWhiteSpace($providerPrivateKeyValue)) {
                throw "Tenant registry contract failure: active tenant/provider mapping '$tenantCode/$providerCode' is missing Key Vault secret '$providerPrivateKeyAlias'."
            }
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
                ContractStatus = if ($script:SqlAuthenticationMode -eq 'Entra') { 'sql-topology-validated-provider-secret-presence-not-checked' } else { 'validated' }
            })
    }

    return $topology.ToArray()
}

Write-Step "Resolving Azure resources and credentials for $Environment"
if ($SqlAuthenticationMode -eq 'Entra') {
    $script:SqlAccessToken = Invoke-AzureCliText -Operation 'Acquire Azure SQL access token' -Command {
        az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv
    }
    $databaseResourcesJson = Invoke-AzureCliText -Operation 'Discover tagged Azure SQL databases' -Command {
        az sql db list --server $sqlServerName --resource-group $resourceGroup --query '[].{name:name,tags:tags}' -o json
    }
    $databaseResources = @($databaseResourcesJson | ConvertFrom-Json)
    foreach ($databaseResource in $databaseResources) {
        $taggedTenant = [string](Get-ObjectPropertyValue -Object $databaseResource.tags -PropertyName 'tenant')
        $databaseName = [string]$databaseResource.name
        if (-not [string]::IsNullOrWhiteSpace($taggedTenant) -and $databaseName -match '^[A-Za-z0-9_]+$') {
            $key = $taggedTenant.ToLowerInvariant()
            if (-not $script:DedicatedDatabaseByTenant.ContainsKey($key)) { $script:DedicatedDatabaseByTenant[$key] = @() }
            $script:DedicatedDatabaseByTenant[$key] += $databaseName
        }
    }
}
else {
    $script:SqlAdminUser = Invoke-AzureCliText -Operation 'Resolve SQL administrator login' -Command {
        az sql server show --name $sqlServerName --resource-group $resourceGroup --query administratorLogin -o tsv
    }

    $script:SqlAdminPassword = Invoke-AzureCliText -Operation 'Resolve sql-admin-password from Key Vault' -Command {
        az keyvault secret show --vault-name $keyVaultName --name sql-admin-password --query value -o tsv
    }

    if ([string]::IsNullOrWhiteSpace($script:SqlAdminUser)) {
        throw "Failed to resolve SQL administrator login for $sqlServerName."
    }

    if ([string]::IsNullOrWhiteSpace($script:SqlAdminPassword)) {
        throw "Failed to resolve sql-admin-password from $keyVaultName."
    }
}
$sqlAdminUser = [string]$script:SqlAdminUser
$sqlAdminPassword = [string]$script:SqlAdminPassword

if (-not $SkipFirewallOpen) {
    Write-Step "Opening Azure SQL firewall access"
    Ensure-AzureSqlFirewallAccess
}

if ($PreQueryDelaySeconds -gt 0) {
    Write-Step "Waiting $PreQueryDelaySeconds seconds for App Insights telemetry ingestion..."
    Start-Sleep -Seconds $PreQueryDelaySeconds
}

$tenantTopology = @(Get-AzureTenantTopology)
$sharedTenants = @($tenantTopology | Where-Object TenantTier -eq 'SharedPool')
$dedicatedTenants = @($tenantTopology | Where-Object TenantTier -eq 'Dedicated')
$sharedTenantCodes = @($sharedTenants | ForEach-Object { $_.TenantCode })
$dedicatedTenantCodes = @($dedicatedTenants | ForEach-Object { $_.TenantCode })

if ($PreflightOnly) {
    $preflightStartedUtc = [DateTime]::UtcNow.ToString('o')
    $preflightChecks = [System.Collections.Generic.List[object]]::new()
    $preflightFailure = $false
    $subscriptionId = ''
    $expectedSubscription = if (-not [string]::IsNullOrWhiteSpace($ExpectedSubscriptionId)) { $ExpectedSubscriptionId.Trim() } elseif (-not [string]::IsNullOrWhiteSpace($env:EXPECTED_AZURE_SUBSCRIPTION_ID)) { $env:EXPECTED_AZURE_SUBSCRIPTION_ID.Trim() } elseif (-not [string]::IsNullOrWhiteSpace($env:AZUREAPPSERVICE_SUBSCRIPTIONID)) { $env:AZUREAPPSERVICE_SUBSCRIPTIONID.Trim() } else { '' }
    $sqlDatabaseChecks = @()
    try {
        $subscriptionId = Invoke-AzureCliText -Operation 'Resolve active Azure subscription' -Command {
            az account show --query id -o tsv
        }
        if ([string]::IsNullOrWhiteSpace($expectedSubscription)) {
            $preflightFailure = $true
            $preflightChecks.Add([PSCustomObject]@{ service = 'Azure subscription'; status = 'FAIL'; detail = 'Expected subscription ID is not configured; supply it explicitly so the target can be verified before testing.' })
        }
        elseif ($subscriptionId -ne $expectedSubscription) {
            $preflightFailure = $true
            $preflightChecks.Add([PSCustomObject]@{ service = 'Azure subscription'; status = 'FAIL'; detail = 'Active subscription does not match the approved expected subscription.' })
        }
        else {
            $preflightChecks.Add([PSCustomObject]@{ service = 'Azure subscription'; status = 'PASS'; detail = 'Active subscription matches the approved expected subscription.' })
        }
    }
    catch {
        $preflightFailure = $true
        $preflightChecks.Add([PSCustomObject]@{ service = 'Azure subscription'; status = 'FAIL'; detail = 'Could not resolve the active subscription context; run az login/account set and verify the target.' })
    }

    if ($SqlAuthenticationMode -eq 'KeyVault') {
        $preflightChecks.Add([PSCustomObject]@{ service = 'Key Vault'; status = 'PASS'; detail = 'Configured verifier secret reads for SQL and active tenant/provider contracts succeeded without emitting values.' })
    }
    else {
        $preflightChecks.Add([PSCustomObject]@{ service = 'Key Vault'; status = 'NOT_REQUIRED'; detail = 'Operator Entra verification does not need Key Vault secret-read access; deployed workload identity access is covered by deployment/runtime checks.' })
    }

    try {
        $healthRows = @(Convert-AppInsightsRows -Response (Invoke-AppInsightsQuery -Purpose 'access-preflight' -Query 'print Result=1 | project Result'))
        if ($healthRows.Count -ne 1 -or [string]$healthRows[0].Result -ne '1') {
            throw 'App Insights access preflight did not return its expected one-row result.'
        }
        $preflightChecks.Add([PSCustomObject]@{ service = 'Application Insights'; status = 'PASS'; detail = 'Resource query endpoint and Logs read access verified with a non-sensitive one-row query.' })
    }
    catch {
        $preflightFailure = $true
        $preflightChecks.Add([PSCustomObject]@{ service = 'Application Insights'; status = 'FAIL'; detail = 'Resource query or Logs read access failed; no role or resource was changed.' })
    }

    try {
        $databases = @($sharedDbName) + @($dedicatedTenants | ForEach-Object DedicatedDatabaseName | Sort-Object -Unique)
        foreach ($databaseName in $databases) {
            if ([string]::IsNullOrWhiteSpace($databaseName)) {
                $sqlDatabaseChecks += [PSCustomObject]@{ database = 'UNKNOWN'; status = 'FAIL'; detail = 'No unique database mapping was resolved for an active dedicated tenant.' }
                $preflightFailure = $true
                continue
            }
            try {
                $dbRows = @(Invoke-AzureSqlQuery -Database $databaseName -Query @'
SELECT DB_NAME() AS DatabaseName, CAST(1 AS int) AS Ready
WHERE NOT EXISTS (SELECT TOP (0) ProviderType FROM payments.PaymentProviders)
  AND NOT EXISTS (SELECT TOP (0) TransactionId FROM payments.CardTransactions)
  AND NOT EXISTS (SELECT TOP (0) TransactionId FROM payments.TransactionStatusHistories);
'@)
                if ($dbRows.Count -ne 1 -or [string]$dbRows[0].DatabaseName -ne $databaseName -or [int]$dbRows[0].Ready -ne 1) {
                    throw 'SQL database identity/result mismatch.'
                }
                $sqlDatabaseChecks += [PSCustomObject]@{ database = $databaseName; status = 'PASS' }
            }
            catch {
                $sqlDatabaseChecks += [PSCustomObject]@{ database = $databaseName; status = 'FAIL'; detail = 'Read-only SQL connection failed; check the Entra SQL user, SELECT grant, and firewall lease.' }
                $preflightFailure = $true
            }
        }
    }
    catch {
        $preflightFailure = $true
        $preflightChecks.Add([PSCustomObject]@{ service = 'Azure SQL'; status = 'FAIL'; detail = 'SQL preflight could not enumerate target databases.' })
    }

    if (@($sqlDatabaseChecks | Where-Object status -ne 'PASS').Count -eq 0 -and $sqlDatabaseChecks.Count -gt 0) {
        $preflightChecks.Add([PSCustomObject]@{ service = 'Azure SQL'; status = 'PASS'; detail = "Read-only identity verified for $($sqlDatabaseChecks.Count) resolved database(s)." })
    }
    $preflightChecks.Add([PSCustomObject]@{ service = 'Tenant/provider topology'; status = $(if ($tenantTopology.Count -gt 0) { 'PASS' } else { 'FAIL' }); detail = "Discovered $($tenantTopology.Count) active tenant(s); dedicated tenants are resolved from configuration references and Azure SQL resource tags, not tenant-name conventions." })
    if ($tenantTopology.Count -eq 0) { $preflightFailure = $true }
    try { Close-AzureSqlFirewallLease }
    catch {
        $preflightFailure = $true
        $preflightChecks.Add([PSCustomObject]@{ service = 'Azure SQL firewall lease'; status = 'FAIL'; detail = 'Owned SQL firewall lease cleanup failed; inspect its recovery manifest before retrying.' })
    }
    if (-not [string]::IsNullOrWhiteSpace($script:AzureSqlFirewallLeaseManifestPath) -and (Test-Path -LiteralPath $script:AzureSqlFirewallLeaseManifestPath)) {
        try {
            $leaseState = (Get-Content -LiteralPath $script:AzureSqlFirewallLeaseManifestPath -Raw | ConvertFrom-Json -ErrorAction Stop).state
            if ($leaseState -ne 'removed') { throw 'unverified lease state' }
            $preflightChecks.Add([PSCustomObject]@{ service = 'Azure SQL firewall lease'; status = 'PASS'; detail = 'Owned temporary firewall rule removal was verified.' })
        }
        catch {
            $preflightFailure = $true
            $preflightChecks.Add([PSCustomObject]@{ service = 'Azure SQL firewall lease'; status = 'FAIL'; detail = 'Temporary firewall rule removal could not be proven; preserve the manifest and resolve it before retrying.' })
        }
    }

    $repoRoot = Split-Path -Parent $PSScriptRoot
    $revision = (& git -C $repoRoot rev-parse HEAD 2>$null | Out-String).Trim()
    $dirty = [bool](& git -C $repoRoot status --porcelain 2>$null)
    $report = [PSCustomObject]@{
        schemaVersion = 'phase10-azure-verification-preflight-v1'
        status = if (-not $preflightFailure -and @($preflightChecks | Where-Object { $_.status -notin @('PASS', 'NOT_REQUIRED') }).Count -eq 0) { 'PASS' } else { 'FAIL' }
        environment = $logicalEnvironment
        startedUtc = $preflightStartedUtc
        finishedUtc = [DateTime]::UtcNow.ToString('o')
        subscriptionId = $subscriptionId
        expectedSubscriptionId = if ([string]::IsNullOrWhiteSpace($expectedSubscription)) { 'UNKNOWN' } else { $expectedSubscription }
        resourceGroup = $resourceGroup
        sqlAuthenticationMode = $SqlAuthenticationMode
        sourceRevision = if ($revision -match '^[a-f0-9]{40}$') { $revision } else { 'UNKNOWN' }
        sourceDirty = $dirty
        tenantCount = $tenantTopology.Count
        tenants = @($tenantTopology | Select-Object TenantCode, TenantTier, PaymentProviderCode)
        checks = @($preflightChecks.ToArray())
        sqlDatabases = @($sqlDatabaseChecks)
        appInsightsQueries = @($script:AppInsightsQueryOutcomes.ToArray())
        firewallLeaseManifest = $script:AzureSqlFirewallLeaseManifestPath
    }
    $jsonReport = $report | ConvertTo-Json -Depth 8
    if ([string]::IsNullOrWhiteSpace($PreflightReportPath)) {
        $reportDirectory = Join-Path $repoRoot ('TestResults/Playwright/azure-https/preflight-{0}-{1}' -f $logicalEnvironment, (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $PreflightReportPath = Join-Path $reportDirectory 'verification-preflight.json'
    }
    $fullReportPath = [IO.Path]::GetFullPath($PreflightReportPath)
    $testResultsRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'TestResults')).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $fullReportPath.StartsWith($testResultsRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Preflight report path must remain under repository TestResults.'
    }
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $fullReportPath))
    Set-Content -LiteralPath $fullReportPath -Value $jsonReport -Encoding utf8
    $markdownPath = [IO.Path]::ChangeExtension($fullReportPath, '.md')
    $markdown = @(
        '# Azure Verification Preflight'
        ''
        "- Status: **$($report.status)**"
        "- Environment: $logicalEnvironment"
        "- Subscription: $subscriptionId"
        "- SQL authentication: $SqlAuthenticationMode"
        "- Source: $($report.sourceRevision) (dirty=$($report.sourceDirty))"
        "- Active tenants discovered: $($tenantTopology.Count)"
        ''
        '| Service/check | Status | Detail |'
        '|---|---|---|'
        @($preflightChecks | ForEach-Object { "| $($_.service) | $($_.status) | $($_.detail -replace '\|','/') |" })
        ''
        '| SQL database | Status |'
        '|---|---|'
        @($sqlDatabaseChecks | ForEach-Object { "| $($_.database) | $($_.status) |" })
        ''
        "JSON evidence: $([IO.Path]::GetFileName($fullReportPath))"
    ) -join [Environment]::NewLine
    Set-Content -LiteralPath $markdownPath -Value $markdown -Encoding utf8
    if ($OutputFormat -eq 'Json') { Write-Output $jsonReport } else { Write-Host $jsonReport }
    if ($report.status -ne 'PASS') { exit 1 }
    return
}

Write-Step "Querying App Insights API telemetry"
$apiQuery = @"
union isfuzzy=true
(
customEvents
| where $($script:TelemetryTimeFilter)
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
| where $($script:TelemetryTimeFilter)
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
    $apiRows = Convert-AppInsightsRows -Response (Invoke-AppInsightsQuery -Query $apiQuery -Purpose 'api-payment-telemetry')
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
$appInsightsAvailable = ((Get-CollectionCount -Value $availableRunPrefixes) -gt 0)

$selectedRunPrefix = $RunPrefix
if ([string]::IsNullOrWhiteSpace($selectedRunPrefix)) {
    if ((Get-CollectionCount -Value $availableRunPrefixes) -eq 1) {
        $selectedRunPrefix = $availableRunPrefixes[0]
    }
    elseif ((Get-CollectionCount -Value $availableRunPrefixes) -gt 1) {
        $prefixList = ($availableRunPrefixes | ForEach-Object { "- $_" }) -join "`n"
        throw "Multiple run prefixes were found. Re-run with -RunPrefix.`n$prefixList"
    }
    else {
        throw "No payment run prefixes were found in the selected API telemetry window for $Environment. Re-run with -RunPrefix to force a DB-backed verification pass."
    }
}

if ((Get-CollectionCount -Value $availableRunPrefixes) -gt 0 -and $availableRunPrefixes -notcontains $selectedRunPrefix) {
    if ([string]::IsNullOrWhiteSpace($RunPrefix)) {
        $prefixList = ($availableRunPrefixes | ForEach-Object { "- $_" }) -join "`n"
        throw "Run prefix '$selectedRunPrefix' was not found in the selected API telemetry window.`n$prefixList"
    }

    $appInsightsWarnings += "Run prefix '$selectedRunPrefix' was not found in the selected API telemetry window yet; continuing with DB-backed verification."
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
| where $($script:TelemetryTimeFilter)
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
| where $($script:TelemetryTimeFilter)
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
    $uiRows = Convert-AppInsightsRows -Response (Invoke-AppInsightsQuery -Query $uiQuery -Purpose 'ui-callback-telemetry')
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

$preflightDedicated = @(
    foreach ($tenant in $dedicatedTenants) {
        $assignedProviderCode = ConvertTo-SqlStringLiteral -Value $tenant.PaymentProviderCode
        Invoke-AzureSqlQuery -Database $tenant.DedicatedDatabaseName -UserName $sqlAdminUser -Password $sqlAdminPassword -Query @"
SELECT '$($tenant.TenantCode)' AS Tenant, pp.Use3DSecure AS ThreeDSEnabled
FROM payments.PaymentProviders pp
WHERE pp.ProviderType = N'$assignedProviderCode';
"@
    }
)

$customerOrderSqlPredicate = if (-not [string]::IsNullOrWhiteSpace($CustomerOrderId) -and -not [string]::IsNullOrWhiteSpace($OrderReferenceId)) {
    $escapedCustomerOrderId = ConvertTo-SqlStringLiteral -Value $CustomerOrderId.Trim()
    $escapedOrderReferenceId = ConvertTo-SqlStringLiteral -Value $OrderReferenceId.Trim()
    "(ct.CustomerOrderId = N'$escapedCustomerOrderId' OR ct.TransactionReferenceId = N'$escapedOrderReferenceId')"
}
elseif (-not [string]::IsNullOrWhiteSpace($CustomerOrderId)) {
    $escapedCustomerOrderId = ConvertTo-SqlStringLiteral -Value $CustomerOrderId.Trim()
    "ct.CustomerOrderId = N'$escapedCustomerOrderId'"
}
elseif (-not [string]::IsNullOrWhiteSpace($OrderReferenceId)) {
    $escapedOrderReferenceId = ConvertTo-SqlStringLiteral -Value $OrderReferenceId.Trim()
    "ct.TransactionReferenceId = N'$escapedOrderReferenceId'"
}
else {
    $escapedRunPrefix = ConvertTo-SqlStringLiteral -Value $selectedRunPrefix
    "ct.CustomerOrderId LIKE N'$escapedRunPrefix%'"
}

$q2Shared = @(Invoke-AzureSqlQuery -Database $sharedDbName -UserName $sqlAdminUser -Password $sqlAdminPassword -Query @"
SELECT t.Code AS Tenant, ct.CustomerOrderId, ct.Id AS CardTransactionRowId, ct.TransactionId AS ChargeId,
       ct.TransactionType, ct.TransactionStatus AS Status, ct.IsThreeDSecureEnabled AS ThreeDS,
       ct.ThreeDSecureStage, ct.TransactionReferenceId AS Ref,
       ct.IsTransactionSuccess AS OK, ct.CreatedDate
FROM payments.CardTransactions ct
JOIN dbo.Tenants t ON t.Id = ct.TenantId
WHERE $customerOrderSqlPredicate
ORDER BY ct.TenantId, ct.CustomerOrderId, ct.Id;
"@)

$q5Shared = @(Invoke-AzureSqlQuery -Database $sharedDbName -UserName $sqlAdminUser -Password $sqlAdminPassword -Query @"
SELECT t.Code AS Tenant, ct.CustomerOrderId, ct.Id AS CardTransactionRowId,
       ct.TransactionType, ct.TransactionStatus AS CurrentStatus, tsh.Id AS HistoryId, tsh.Status,
       tsh.ThreeDSecureStage AS Stage, tsh.IsThreeDSecureEnabled AS ThreeDS,
       tsh.TransactionReferenceId AS Ref
FROM payments.TransactionStatusHistories tsh
JOIN payments.CardTransactions ct ON ct.Id = tsh.TransactionId
JOIN dbo.Tenants t ON t.Id = ct.TenantId
WHERE $customerOrderSqlPredicate
ORDER BY ct.TenantId, ct.CustomerOrderId, ct.Id, tsh.Id;
"@)

$q8Shared = @()

$q2Dedicated = @(
    foreach ($tenant in $dedicatedTenants) {
        Invoke-AzureSqlQuery -Database $tenant.DedicatedDatabaseName -UserName $sqlAdminUser -Password $sqlAdminPassword -Query @"
SELECT '$($tenant.TenantCode)' AS Tenant, ct.CustomerOrderId, ct.Id AS CardTransactionRowId, ct.TransactionId AS ChargeId,
       ct.TransactionType, ct.TransactionStatus AS Status, ct.IsThreeDSecureEnabled AS ThreeDS,
       ct.ThreeDSecureStage, ct.TransactionReferenceId AS Ref,
       ct.IsTransactionSuccess AS OK, ct.CreatedDate
FROM payments.CardTransactions ct
WHERE $customerOrderSqlPredicate
ORDER BY ct.CustomerOrderId, ct.Id;
"@
    }
)

$q5Dedicated = @(
    foreach ($tenant in $dedicatedTenants) {
        Invoke-AzureSqlQuery -Database $tenant.DedicatedDatabaseName -UserName $sqlAdminUser -Password $sqlAdminPassword -Query @"
SELECT '$($tenant.TenantCode)' AS Tenant, ct.CustomerOrderId, ct.Id AS CardTransactionRowId,
       ct.TransactionType, ct.TransactionStatus AS CurrentStatus, tsh.Id AS HistoryId, tsh.Status, tsh.ThreeDSecureStage AS Stage,
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
            (Get-CollectionCount -Value $sharedTenantCodes) -gt 0 -and ($sharedTenantCodes -notcontains $tenantCode)
        }
)

if (-not [string]::IsNullOrWhiteSpace($requestedTenantCode)) {
    $scopedTenantCode = $requestedTenantCode.Trim()
    $q2Shared = @($q2Shared | Where-Object Tenant -eq $scopedTenantCode)
    $q5Shared = @($q5Shared | Where-Object Tenant -eq $scopedTenantCode)
    $q2Dedicated = @($q2Dedicated | Where-Object Tenant -eq $scopedTenantCode)
    $q5Dedicated = @($q5Dedicated | Where-Object Tenant -eq $scopedTenantCode)
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

foreach ($tenantRow in $preflightDedicated) {
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

if ((Get-CollectionCount -Value $expectedOrdersByTenant.Keys) -eq 0) {
    $sharedOrdersByTenant = $q2Shared | Group-Object Tenant
    foreach ($tenantGroup in $sharedOrdersByTenant) {
        $expectedOrdersByTenant[$tenantGroup.Name] = @($tenantGroup.Group | Select-Object -ExpandProperty CustomerOrderId -Unique)
    }

    foreach ($tenantGroup in ($q2Dedicated | Group-Object Tenant)) {
        $expectedOrdersByTenant[$tenantGroup.Name] = @($tenantGroup.Group | Select-Object -ExpandProperty CustomerOrderId -Unique)
    }
}

$sharedDbChargeIds = @($q2Shared | Select-Object -ExpandProperty ChargeId)
$dedicatedDbChargeIds = @($q2Dedicated | Select-Object -ExpandProperty ChargeId)
$allDbChargeIds = @($sharedDbChargeIds + $dedicatedDbChargeIds)
$allDbChargeRows = @(@($q2Shared) + @($q2Dedicated))
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

if ((Get-CollectionCount -Value $providerCorrelationIds) -gt 0) {
    $providerChargeIdList = Get-KqlQuotedValues -Values $providerCorrelationIds
    $transportQuery = @"
union isfuzzy=true
(
requests
| where $($script:TelemetryTimeFilter)
| extend telemetryType = 'request'
| extend detail = strcat(name, ' ', url)
| where detail has_any ($providerChargeIdList)
| where success == true
| project timestamp, telemetryType, operation_Id, cloud_RoleName, name, resultCode, success, target='', detail
),
(
dependencies
| where $($script:TelemetryTimeFilter)
| extend telemetryType = 'dependency'
| extend detail = strcat(name, ' ', data, ' ', target)
| where detail has_any ($providerChargeIdList)
| where success == true
| project timestamp, telemetryType, operation_Id, cloud_RoleName, name, resultCode, success, target, detail
)
| order by timestamp asc
"@

    try {
        $transportRows = @(Convert-AppInsightsRows -Response (Invoke-AppInsightsQuery -Query $transportQuery -Purpose 'provider-request-dependency-correlation'))
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
                    RequestCount = (Get-CollectionCount -Value @($matchingRows | Where-Object telemetryType -eq 'request'))
                    DependencyCount = (Get-CollectionCount -Value @($matchingRows | Where-Object telemetryType -eq 'dependency'))
                    CorrelatedOperationIds = @($correlatedOperationIds)
                    Correlated = ((Get-CollectionCount -Value @($correlatedOperationIds)) -gt 0)
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

# Provider IDs can be different from the internal transaction ID and from the
# browser-generated customer-order reference. Follow the provider-correlated
# operation IDs back to the API custom event, then use its authoritative
# tenant/order key to read the matching shared or dedicated SQL row.
$providerOperationIds = @(
    $transportEvidence |
        Where-Object Correlated |
        ForEach-Object { @($_.CorrelatedOperationIds) } |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
        Sort-Object -Unique
)
if ((Get-CollectionCount -Value $providerOperationIds) -gt 0) {
    $operationIdList = Get-KqlQuotedValues -Values $providerOperationIds
    $providerIdList = Get-KqlQuotedValues -Values $providerCorrelationIds
    $operationApiQuery = @"
customEvents
| where $($script:TelemetryTimeFilter)
| where operation_Id in ($operationIdList)
| where name in ('payment_validation_attempt_created', 'payment_validation_charge_created', 'payment_validation_callback_reconciled')
| extend application = tostring(customDimensions['Application'])
| extend tenant = tostring(customDimensions['TenantCode'])
| extend customerOrderId = tostring(customDimensions['CustomerOrderId'])
| extend chargeId = tostring(customDimensions['PaymentId'])
| extend message = case(
    name == 'payment_validation_attempt_created', strcat('Payment attempt created for customer order ', customerOrderId),
    name == 'payment_validation_charge_created', strcat('Charge created with ID: ', chargeId),
    name == 'payment_validation_callback_reconciled', strcat('Payment callback reconciliation completed for payment ', chargeId),
    name)
| where (application == 'API' or cloud_RoleName has 'api')
| where chargeId in ($providerIdList)
| project timestamp, tenant, customerOrderId, chargeId, message
| order by timestamp asc
"@

    try {
        $operationApiRows = @(Convert-AppInsightsRows -Response (Invoke-AppInsightsQuery -Query $operationApiQuery -Purpose 'provider-operation-api-event-correlation'))
        $operationApiEvents = @(
            foreach ($row in $operationApiRows) {
                [PSCustomObject]@{
                    Timestamp = [datetimeoffset]$row.timestamp
                    Tenant = [string]$row.tenant
                    CustomerOrderId = [string]$row.customerOrderId
                    ResolvedCustomerOrderId = [string]$row.customerOrderId
                    RunPrefix = $selectedRunPrefix
                    ResolvedRunPrefix = $selectedRunPrefix
                    ChargeId = [string]$row.chargeId
                    Message = [string]$row.message
                }
            }
        )
        if (-not [string]::IsNullOrWhiteSpace($requestedTenantCode)) {
            $operationApiEvents = @($operationApiEvents | Where-Object Tenant -eq $requestedTenantCode.Trim())
        }

        # Some SDK paths return API custom events for the correlated provider
        # payment ID but with an operation_Id that differs from the request /
        # dependency span. Only fall back after checking the operation-based
        # results against the requested tenant; then SQL validates the event's
        # persisted order key in that tenant's authoritative database.
        if ((Get-CollectionCount -Value $operationApiEvents) -eq 0) {
            $providerApiFallbackQuery = @"
customEvents
| where $($script:TelemetryTimeFilter)
| where name in ('payment_validation_attempt_created', 'payment_validation_charge_created', 'payment_validation_callback_reconciled')
| extend application = tostring(customDimensions['Application'])
| extend tenant = tostring(customDimensions['TenantCode'])
| extend customerOrderId = tostring(customDimensions['CustomerOrderId'])
| extend chargeId = tostring(customDimensions['PaymentId'])
| extend message = case(
    name == 'payment_validation_attempt_created', strcat('Payment attempt created for customer order ', customerOrderId),
    name == 'payment_validation_charge_created', strcat('Charge created with ID: ', chargeId),
    name == 'payment_validation_callback_reconciled', strcat('Payment callback reconciliation completed for payment ', chargeId),
    name)
| where (application == 'API' or cloud_RoleName has 'api')
| where chargeId in ($providerIdList)
| project timestamp, operation_Id, tenant, customerOrderId, chargeId, message
| order by timestamp asc
"@
            $providerApiFallbackRows = @(Convert-AppInsightsRows -Response (Invoke-AppInsightsQuery -Query $providerApiFallbackQuery -Purpose 'provider-payment-id-api-event-fallback'))
            $operationApiEvents = @(
                foreach ($row in $providerApiFallbackRows) {
                    [PSCustomObject]@{
                        Timestamp = [datetimeoffset]$row.timestamp
                        Tenant = [string]$row.tenant
                        CustomerOrderId = [string]$row.customerOrderId
                        ResolvedCustomerOrderId = [string]$row.customerOrderId
                        RunPrefix = $selectedRunPrefix
                        ResolvedRunPrefix = $selectedRunPrefix
                        ChargeId = [string]$row.chargeId
                        Message = [string]$row.message
                    }
                }
            )
            if (-not [string]::IsNullOrWhiteSpace($requestedTenantCode)) {
                $operationApiEvents = @($operationApiEvents | Where-Object Tenant -eq $requestedTenantCode.Trim())
            }
        }

        if ((Get-CollectionCount -Value $operationApiEvents) -gt 0) {
            foreach ($operationEvent in $operationApiEvents) {
                if ([string]::IsNullOrWhiteSpace($operationEvent.Tenant) -or [string]::IsNullOrWhiteSpace($operationEvent.CustomerOrderId)) { continue }
                $knownOrders = @($expectedOrdersByTenant[$operationEvent.Tenant])
                $expectedOrdersByTenant[$operationEvent.Tenant] = @($knownOrders + $operationEvent.CustomerOrderId | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)
            }
            $selectedApiEvents = @($selectedApiEvents + $operationApiEvents | Sort-Object Timestamp)
            $apiChargeEvents = @(
                $apiChargeEvents + @(
                    $operationApiEvents |
                        Where-Object { -not [string]::IsNullOrWhiteSpace($_.ChargeId) } |
                        Group-Object ChargeId |
                        ForEach-Object { $_.Group | Select-Object -First 1 }
                ) | Sort-Object Timestamp
            )
            $appInsightsAvailable = $true

            foreach ($operationEvent in $operationApiEvents) {
                if ([string]::IsNullOrWhiteSpace($operationEvent.Tenant) -or [string]::IsNullOrWhiteSpace($operationEvent.CustomerOrderId)) { continue }
                $resolvedTenant = $tenantTopology | Where-Object TenantCode -eq $operationEvent.Tenant | Select-Object -First 1
                if ($null -eq $resolvedTenant) { continue }
                $sqlOrderId = ConvertTo-SqlStringLiteral -Value $operationEvent.CustomerOrderId
                $sqlTenant = ConvertTo-SqlStringLiteral -Value $operationEvent.Tenant
                if ($resolvedTenant.TenantTier -eq 'SharedPool') {
                    $mappedTransactions = @(Invoke-AzureSqlQuery -Database $sharedDbName -Query @"
SELECT t.Code AS Tenant, ct.CustomerOrderId, ct.Id AS CardTransactionRowId, ct.TransactionId AS ChargeId,
       ct.TransactionType, ct.TransactionStatus AS Status, ct.IsThreeDSecureEnabled AS ThreeDS,
       ct.ThreeDSecureStage, ct.TransactionReferenceId AS Ref,
       ct.IsTransactionSuccess AS OK, ct.CreatedDate
FROM payments.CardTransactions ct
JOIN dbo.Tenants t ON t.Id = ct.TenantId
WHERE t.Code = N'$sqlTenant' AND ct.CustomerOrderId = N'$sqlOrderId'
ORDER BY ct.Id;
"@)
                    $mappedHistories = @(Invoke-AzureSqlQuery -Database $sharedDbName -Query @"
SELECT t.Code AS Tenant, ct.CustomerOrderId, ct.Id AS CardTransactionRowId,
       ct.TransactionType, ct.TransactionStatus AS CurrentStatus, tsh.Id AS HistoryId, tsh.Status,
       tsh.ThreeDSecureStage AS Stage, tsh.IsThreeDSecureEnabled AS ThreeDS,
       tsh.TransactionReferenceId AS Ref
FROM payments.TransactionStatusHistories tsh
JOIN payments.CardTransactions ct ON ct.Id = tsh.TransactionId
JOIN dbo.Tenants t ON t.Id = ct.TenantId
WHERE t.Code = N'$sqlTenant' AND ct.CustomerOrderId = N'$sqlOrderId'
ORDER BY ct.Id, tsh.Id;
"@)
                    $q2Shared = @($q2Shared + $mappedTransactions | Sort-Object Tenant, CustomerOrderId, ChargeId -Unique)
                    $q5Shared = @($q5Shared + $mappedHistories | Sort-Object Tenant, CustomerOrderId, HistoryId -Unique)
                }
                else {
                    $mappedTransactions = @(Invoke-AzureSqlQuery -Database $resolvedTenant.DedicatedDatabaseName -Query @"
SELECT '$sqlTenant' AS Tenant, ct.CustomerOrderId, ct.Id AS CardTransactionRowId, ct.TransactionId AS ChargeId,
       ct.TransactionType, ct.TransactionStatus AS Status, ct.IsThreeDSecureEnabled AS ThreeDS,
       ct.ThreeDSecureStage, ct.TransactionReferenceId AS Ref,
       ct.IsTransactionSuccess AS OK, ct.CreatedDate
FROM payments.CardTransactions ct
WHERE ct.CustomerOrderId = N'$sqlOrderId'
ORDER BY ct.Id;
"@)
                    $mappedHistories = @(Invoke-AzureSqlQuery -Database $resolvedTenant.DedicatedDatabaseName -Query @"
SELECT '$sqlTenant' AS Tenant, ct.CustomerOrderId, ct.Id AS CardTransactionRowId,
       ct.TransactionType, ct.TransactionStatus AS CurrentStatus, tsh.Id AS HistoryId, tsh.Status,
       tsh.ThreeDSecureStage AS Stage, tsh.IsThreeDSecureEnabled AS ThreeDS,
       tsh.TransactionReferenceId AS Ref
FROM payments.TransactionStatusHistories tsh
JOIN payments.CardTransactions ct ON ct.Id = tsh.TransactionId
WHERE ct.CustomerOrderId = N'$sqlOrderId'
ORDER BY ct.Id, tsh.Id;
"@)
                    $q2Dedicated = @($q2Dedicated + $mappedTransactions | Sort-Object Tenant, CustomerOrderId, ChargeId -Unique)
                    $q5Dedicated = @($q5Dedicated + $mappedHistories | Sort-Object Tenant, CustomerOrderId, HistoryId -Unique)
                }
            }

            $q8Shared = @(
                $q2Shared | Where-Object {
                    $tenantCode = [string](Get-ObjectPropertyValue -Object $_ -PropertyName 'Tenant')
                    (Get-CollectionCount -Value $sharedTenantCodes) -gt 0 -and ($sharedTenantCodes -notcontains $tenantCode)
                }
            )
            $q9Shared = @(
                $q2Shared | Where-Object {
                    $tenantCode = [string](Get-ObjectPropertyValue -Object $_ -PropertyName 'Tenant')
                    $dedicatedTenantCodes -contains $tenantCode
                }
            )
            $sharedDbChargeIds = @($q2Shared | Select-Object -ExpandProperty ChargeId)
            $dedicatedDbChargeIds = @($q2Dedicated | Select-Object -ExpandProperty ChargeId)
            $allDbChargeIds = @($sharedDbChargeIds + $dedicatedDbChargeIds)
            $allDbChargeRows = @(@($q2Shared) + @($q2Dedicated))
            $providerDbChargeRows = @(
                $allDbChargeRows |
                    Where-Object {
                        $chargeId = [string](Get-ObjectPropertyValue -Object $_ -PropertyName 'ChargeId')
                        $transactionType = [string](Get-ObjectPropertyValue -Object $_ -PropertyName 'TransactionType')
                        -not [string]::IsNullOrWhiteSpace($chargeId) -and $transactionType -eq 'charge'
                    }
            )
        }
    }
    catch {
        $appInsightsWarnings += "Provider-correlated API event recovery failed: $($_.Exception.Message)"
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

if ((Get-CollectionCount -Value @($apiChargeEvents)) -eq 0 -and (Get-CollectionCount -Value @($allDbChargeIds)) -gt 0) {
    $dbChargeIdList = Get-KqlQuotedValues -Values $allDbChargeIds
    if (-not [string]::IsNullOrWhiteSpace($dbChargeIdList)) {
        $fallbackApiQuery = @"
    union isfuzzy=true
    (
    customEvents
| where $($script:TelemetryTimeFilter)
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
    | where $($script:TelemetryTimeFilter)
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

        try {
            $fallbackApiRows = Convert-AppInsightsRows -Response (Invoke-AppInsightsQuery -Query $fallbackApiQuery -Purpose 'api-provider-id-fallback')
        }
        catch {
            $appInsightsWarnings += "API provider-ID fallback query failed: $($_.Exception.Message)"
            $fallbackApiRows = @()
        }
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

        if ((Get-CollectionCount -Value $fallbackApiEvents) -gt 0) {
            $selectedApiEvents = @(
                $fallbackApiEvents |
                    Where-Object {
                        $_.ResolvedRunPrefix -eq $selectedRunPrefix -or
                        $_.ResolvedCustomerOrderId -like "$selectedRunPrefix*" -or
                        ($allDbChargeIds -contains $_.ChargeId)
                    } |
                    Sort-Object Timestamp
            )

            if ((Get-CollectionCount -Value $selectedApiEvents) -eq 0) {
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
        if ((Get-CollectionCount -Value @($apiChargeEvents | Where-Object ChargeId -eq $evidence.ChargeId)) -gt 0) {
            continue
        }

        $dbRow = $providerDbChargeRows | Where-Object ChargeId -eq $evidence.ChargeId | Select-Object -First 1
        if ($null -eq $dbRow -and (Get-CollectionCount -Value $providerDbChargeRows) -eq 1) {
            $dbRow = $providerDbChargeRows | Select-Object -First 1
        }
        if ($null -eq $dbRow) {
            continue
        }

        $evidenceRows = @($evidence.Rows)
        $timestamp = if ((Get-CollectionCount -Value $evidenceRows) -gt 0) {
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

if ((Get-CollectionCount -Value $transportApiEvents) -gt 0) {
    $selectedApiEvents = @($selectedApiEvents + $transportApiEvents | Sort-Object Timestamp)
    $apiChargeEvents = @($apiChargeEvents + $transportApiEvents | Sort-Object Timestamp)
    $appInsightsAvailable = $true
}

$apiChargeIds = @($apiChargeEvents | Select-Object -ExpandProperty ChargeId -Unique)
$knownUiChargeIds = @($apiChargeIds + $allDbChargeIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
$selectedUiEvents = @(Get-ScopedUiEvents -Events @($uiEvents) -KnownChargeIds $knownUiChargeIds -KnownTenants $expectedUiTenants -KnownCustomerOrders $expectedUiCustomerOrders)

if ((Get-CollectionCount -Value $selectedUiEvents) -eq 0) {
    $evidenceChargeIds = if ((Get-CollectionCount -Value $apiChargeIds) -gt 0) { $apiChargeIds } else { @($allDbChargeIds | Sort-Object -Unique) }
    $evidenceChargeIdList = Get-KqlQuotedValues -Values $evidenceChargeIds
    if (-not [string]::IsNullOrWhiteSpace($evidenceChargeIdList)) {
        $fallbackUiQuery = @"
    union isfuzzy=true
    (
    customEvents
| where $($script:TelemetryTimeFilter)
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
    | where $($script:TelemetryTimeFilter)
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

        try {
            $fallbackUiRows = Convert-AppInsightsRows -Response (Invoke-AppInsightsQuery -Query $fallbackUiQuery -Purpose 'ui-provider-id-fallback')
        }
        catch {
            $appInsightsWarnings += "UI provider-ID fallback query failed: $($_.Exception.Message)"
            $fallbackUiRows = @()
        }
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

if ((Get-CollectionCount -Value $selectedApiEvents) -gt 0 -or (Get-CollectionCount -Value $selectedUiEvents) -gt 0) {
    $appInsightsAvailable = $true
}

if (($apiQueryFailed -or $uiQueryFailed) -and (Get-CollectionCount -Value $selectedApiEvents) -eq 0 -and (Get-CollectionCount -Value $selectedUiEvents) -eq 0) {
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

    $uiCorrelationMode = if ((Get-CollectionCount -Value $uiMatches) -gt 0) { 'chargeId' } else { 'none' }

    if ((Get-CollectionCount -Value $uiMatches) -eq 0 -and $threeDsByTenant[$chargeEvent.Tenant] -eq 1) {
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

        if ((Get-CollectionCount -Value $referenceTimestamps) -eq 0) {
            $referenceTimestamps = @($candidateApiEvents | Select-Object -ExpandProperty Timestamp)
        }

        if ((Get-CollectionCount -Value $referenceTimestamps) -eq 0) {
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

        if ((Get-CollectionCount -Value @($fallbackMatch)) -gt 0 -and $null -ne @($fallbackMatch)[0]) {
            $uiMatches = @(@($fallbackMatch)[0].UiEvent)
            $uiCorrelationMode = 'tenant+time'
            $null = $usedFallbackUiEventKeys.Add(@($fallbackMatch)[0].UiEvent.EventKey)
            $null = $matchedUiEventKeys.Add(@($fallbackMatch)[0].UiEvent.EventKey)
        }
    }

    $uiStatusCodes = @($uiMatches | Where-Object { -not [string]::IsNullOrWhiteSpace($_.StatusCode) } | Select-Object -ExpandProperty StatusCode -Unique)
    $uiEventNames = @($uiMatches | Where-Object { -not [string]::IsNullOrWhiteSpace($_.UiEventName) } | Select-Object -ExpandProperty UiEventName -Unique)

    if ((Get-CollectionCount -Value $uiStatusCodes) -eq 0 -and (Get-CollectionCount -Value $globalUiStatusCodes) -gt 0 -and (Get-CollectionCount -Value $apiChargeEvents) -eq 1) {
        $uiStatusCodes = $globalUiStatusCodes
    }

    $dbCandidates = @($q2Shared) + @($q2Dedicated)
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
        # Positive payment journeys require callback evidence independently of configured 3DS.
        UiCallbackExpected = $true
        UiCallbackLogged = ((Get-CollectionCount -Value $uiMatches) -gt 0)
        UiCorrelationMode = $uiCorrelationMode
        UiEventNames = @($uiEventNames)
        UiStatusCodes = @($uiStatusCodes)
    }
}
)

$reportedUiEvents = if ((Get-CollectionCount -Value $matchedUiEventKeys) -gt 0) {
    @($selectedUiEvents | Where-Object { $matchedUiEventKeys.Contains($_.EventKey) } | Sort-Object Timestamp)
}
else {
    @($selectedUiEvents)
}

function Get-HistoryIntegrityForTenant {
    param(
        [Parameter(Mandatory = $true)] [string] $TenantCode,
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [object[]] $TransactionRows,
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [object[]] $HistoryRows
    )

    $tenantTransactions = @($TransactionRows | Where-Object Tenant -eq $TenantCode)
    $tenantHistories = @($HistoryRows | Where-Object Tenant -eq $TenantCode)
    $missingHistoryCount = 0
    $terminalStatusMismatchCount = 0

    foreach ($transaction in $tenantTransactions) {
        $matchingHistory = @(
            $tenantHistories |
                Where-Object { [string]$_.CustomerOrderId -eq [string]$transaction.CustomerOrderId -and [string]$_.CardTransactionRowId -eq [string]$transaction.CardTransactionRowId } |
                Sort-Object { [long]$_.HistoryId }
        )
        if ((Get-CollectionCount -Value $matchingHistory) -eq 0) {
            $missingHistoryCount++
            continue
        }

        if ([string]$matchingHistory[-1].Status -ne [string]$transaction.Status) {
            $terminalStatusMismatchCount++
        }
    }

    [PSCustomObject]@{
        TransactionCount = (Get-CollectionCount -Value $tenantTransactions)
        HistoryCount = (Get-CollectionCount -Value $tenantHistories)
        MissingHistoryCount = $missingHistoryCount
        TerminalStatusMismatchCount = $terminalStatusMismatchCount
    }
}

$checks = [ordered] @{}
$transactionRowsForHistory = @(@($q2Shared) + @($q2Dedicated))
$historyRowsForHistory = @(@($q5Shared) + @($q5Dedicated))

$allRows = @(@($q2Shared) + @($q2Dedicated))
$allHistoryRows = @(@($q5Shared) + @($q5Dedicated) | Sort-Object Tenant, CustomerOrderId, HistoryId -Unique)
foreach ($tenantCode in ($expectedOrdersByTenant.Keys | Sort-Object)) {
    $checks["Pre-flight 3DS [$tenantCode]"] = Convert-CheckResult -Expected 'configured' -Actual ([string] $threeDsByTenant[$tenantCode]) -Outcome $(if ($threeDsByTenant.ContainsKey($tenantCode)) { 'PASS' } else { 'FAIL' })
    $tenantRows = @($allRows | Where-Object { $_.Tenant -eq $tenantCode })
    $businessTenant=@($tenantTopology | Where-Object TenantCode -eq $tenantCode)
    if($businessTenant.Count -ne 1){throw 'Tenant database resolution is ambiguous.'}
    $proofDatabase=if($businessTenant[0].TenantTier -eq 'Dedicated'){$businessTenant[0].DedicatedDatabaseName}else{$sharedDbName}
    $paidProof=Get-Phase10PaidOrderEvidence -TenantCode $tenantCode -CustomerOrderIds @($expectedOrdersByTenant[$tenantCode]) -ExpectedReference $OrderReferenceId -Query {
        param($query) Invoke-AzureSqlQuery -Database $proofDatabase -Query $query
    }
    $checks["Paid order [$tenantCode]"]=Convert-CheckResult -Expected ([string]$paidProof.Expected) -Actual ([string]$paidProof.Verified) -Outcome $(if($paidProof.Passed){'PASS'}else{'FAIL'})
    $successfulOrders = @($expectedOrdersByTenant[$tenantCode] | Where-Object {
        $expectedOrder = $_
        $charges = @($tenantRows | Where-Object { $_.CustomerOrderId -eq $expectedOrder -and $_.TransactionType -eq 'charge' })
        $charges.Count -eq 1 -and $charges[0].Status -eq 'completed' -and [string]$charges[0].OK -in @('True','1')
    })
    $checks["Successful charge [$tenantCode]"] = Convert-CheckResult -Expected ([string]$expectedOrdersByTenant[$tenantCode].Count) -Actual ([string]$successfulOrders.Count) -Outcome $(if ($successfulOrders.Count -gt 0 -and $successfulOrders.Count -eq $expectedOrdersByTenant[$tenantCode].Count) { 'PASS' } else { 'FAIL' })
    $expectedOrderCount = (Get-CollectionCount -Value $expectedOrdersByTenant[$tenantCode])
    $tenantRowCount = (Get-CollectionCount -Value $tenantRows)
    $historyIntegrity = Get-HistoryIntegrityForTenant -TenantCode $tenantCode -TransactionRows $allRows -HistoryRows $allHistoryRows
    $checks["Q2 rows [$tenantCode]"] = Convert-CheckResult -Expected ([string] ($expectedOrderCount * 2)) -Actual ([string] $tenantRowCount) -Outcome $(if ($tenantRowCount -eq ($expectedOrderCount * 2)) { 'PASS' } else { 'FAIL' })
    $historyExpected = 'one or more histories per transaction; latest status matches current transaction'
    $historyActual = "transactions=$($historyIntegrity.TransactionCount); uniqueHistories=$($historyIntegrity.HistoryCount); missing=$($historyIntegrity.MissingHistoryCount); terminalMismatches=$($historyIntegrity.TerminalStatusMismatchCount)"
    $historyValid = $historyIntegrity.TransactionCount -eq $tenantRowCount -and $historyIntegrity.MissingHistoryCount -eq 0 -and $historyIntegrity.TerminalStatusMismatchCount -eq 0
    $checks["Q5 steps [$tenantCode]"] = Convert-CheckResult -Expected $historyExpected -Actual $historyActual -Outcome $(if ($historyValid) { 'PASS' } else { 'FAIL' })
}
$checks['Q8 bleed'] = Convert-CheckResult -Expected '0' -Actual ([string] (Get-CollectionCount -Value @($q8Shared))) -Outcome $(if ((Get-CollectionCount -Value @($q8Shared)) -eq 0) { 'PASS' } else { 'FAIL' })
$checks['Q9 bleed'] = Convert-CheckResult -Expected '0' -Actual ([string] (Get-CollectionCount -Value @($q9Shared))) -Outcome $(if ((Get-CollectionCount -Value @($q9Shared)) -eq 0) { 'PASS' } else { 'FAIL' })
$failedAppInsightsQueries = @($script:AppInsightsQueryOutcomes | Where-Object status -eq 'FAIL')
$checks['App Insights query execution'] = Convert-CheckResult `
    -Expected 'all attempted queries return valid Azure tables' `
    -Actual $(if ($failedAppInsightsQueries.Count -eq 0) { 'all queries valid' } else { "$($failedAppInsightsQueries.Count) query failure(s)" }) `
    -Outcome $(if ($failedAppInsightsQueries.Count -eq 0) { 'PASS' } else { 'FAIL' })

$correlatedTransportCount = (Get-CollectionCount -Value @($transportEvidence | Where-Object Correlated))
$checks['Provider payment IDs -> request/dependency correlation'] = Convert-CheckResult `
    -Expected ([string](Get-CollectionCount -Value $providerCorrelationIds)) `
    -Actual ([string]$correlatedTransportCount) `
    -Outcome $(if ((Get-CollectionCount -Value $providerCorrelationIds) -gt 0 -and $correlatedTransportCount -eq (Get-CollectionCount -Value $providerCorrelationIds)) { 'PASS' } else { 'FAIL' })

if ((Get-CollectionCount -Value $apiChargeEvents) -eq 0) {
    $checks['API log -> DB charge IDs'] = Convert-CheckResult -Expected 'App Insights charge rows' -Actual 'No API charge rows returned for the selected run prefix' -Outcome 'INCONCLUSIVE'
}
else {
    $apiChargeEventCount = (Get-CollectionCount -Value @($apiChargeEvents))
    $correlatedDbChargeCount = (Get-CollectionCount -Value @($chargeCorrelation | Where-Object InDb))
    $checks['API log -> DB charge IDs'] = Convert-CheckResult -Expected ([string] $apiChargeEventCount) -Actual ([string] $correlatedDbChargeCount) -Outcome $(if ($correlatedDbChargeCount -eq $apiChargeEventCount) { 'PASS' } else { 'FAIL' })
}

$expectedUiCallbacks = (Get-CollectionCount -Value @($chargeCorrelation | Where-Object UiCallbackExpected))
$actualUiCallbacks = (Get-CollectionCount -Value @($chargeCorrelation | Where-Object { $_.UiCallbackExpected -and $_.UiCallbackLogged }))
if ((Get-CollectionCount -Value $apiChargeEvents) -eq 0 -and (Get-CollectionCount -Value $selectedUiEvents) -eq 0) {
    $checks['UI telemetry -> callbacks present where expected'] = Convert-CheckResult -Expected '3DS tenants only' -Actual 'No browser/UI telemetry rows returned for the selected run prefix' -Outcome 'INCONCLUSIVE'
}
else {
    $checks['UI telemetry -> callbacks present where expected'] = Convert-CheckResult -Expected ([string] $expectedUiCallbacks) -Actual ([string] $actualUiCallbacks) -Outcome $(if ($actualUiCallbacks -eq $expectedUiCallbacks) { 'PASS' } else { 'FAIL' })
}

$report = [PSCustomObject] @{
    SchemaVersion = 1
    EvidenceKind = 'payment-correlation'
    GeneratedUtc = [DateTimeOffset]::UtcNow.ToString('o')
    Environment = $Environment
    Runtime = 'azure'
    RunPrefix = $selectedRunPrefix
    TelemetryWindow = [PSCustomObject]@{
        StartUtc = if ($PSBoundParameters.ContainsKey('StartedUtc')) { $telemetryWindowStartUtc } else { 'rolling-7d' }
        EndUtc = if ($PSBoundParameters.ContainsKey('FinishedUtc')) { $telemetryWindowEndUtc } else { [DateTimeOffset]::UtcNow.ToString('o') }
        Explicit = [bool]$PSBoundParameters.ContainsKey('StartedUtc')
    }
    AppInsightsAvailable = $appInsightsAvailable
    Warnings = @($appInsightsWarnings)
    AppInsights = [PSCustomObject] @{
        QueryOutcomes = @($script:AppInsightsQueryOutcomes.ToArray())
        ApiEvidence = @($selectedApiEvents | Select-Object Timestamp, Tenant, ResolvedCustomerOrderId, ChargeId, Message)
        UiEvidence = @($reportedUiEvents | Select-Object Timestamp, Tenant, CustomerOrderId, UiEventName, ChargeId, StatusCode, Message)
        TransportEvidence = @($transportEvidence)
    }
    PaymentHistoryEvidence = @($allHistoryRows | Select-Object Tenant, CustomerOrderId, CardTransactionRowId, TransactionType, CurrentStatus, HistoryId, Status, Stage, ThreeDS, Ref)
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

Close-AzureSqlFirewallLease

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
if ((Get-CollectionCount -Value $selectedApiEvents) -eq 0) {
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
if ((Get-CollectionCount -Value $selectedUiEvents) -eq 0) {
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
if ((Get-CollectionCount -Value @($chargeCorrelation)) -eq 0) {
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
