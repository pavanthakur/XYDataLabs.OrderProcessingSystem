#Requires -Version 7.0
<#!
.SYNOPSIS
    Verifies a local or Docker payment run end to end across physical log files and SQL databases.

.DESCRIPTION
    Reads today's API log for payment events plus browser-originated UI telemetry captured through
    /payment/client-event, resolves a logical run prefix, discovers active tenant topology from the
    registry, queries the shared and dedicated databases that match that topology, and emits a
    consolidated pass/fail report.

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
$yesterdayDateTag = (Get-Date).AddDays(-1).ToString('yyyyMMdd')
$envTag = if ($Runtime -eq 'local') { 'dev' } else { $Environment }
$runtimeTag = if ($Runtime -eq 'docker') { 'dock' } else { 'local' }
$logDirectory = Join-Path $repoRoot 'logs'
$resultRoot = Join-Path $repoRoot 'TestResults\PaymentMatrix'
$runStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runDir = Join-Path $resultRoot $runStamp
$null = New-Item -ItemType Directory -Path $runDir -Force
$transcriptPath = Join-Path $runDir 'payment-matrix.log'
$reportPath = Join-Path $runDir 'payment-matrix.report.json'
$latestPointerPath = Join-Path $resultRoot 'latest-payment-matrix.txt'
$null = Start-Transcript -Path $transcriptPath -Force
$logPrefixes = @('gateway', 'webapi')
$apiLogPatterns = @(
    $logPrefixes | ForEach-Object { "$_-$envTag-$runtimeTag-$Profile-$dateTag*.log" }
    $logPrefixes | ForEach-Object { "$_-$envTag-$runtimeTag-$Profile-$yesterdayDateTag*.log" }
    $logPrefixes | ForEach-Object { "$_-$envTag-$runtimeTag-$Profile-.log" }
)
$envLocalPath = Join-Path $repoRoot 'Resources\Docker\.env.local'
$supportedTenantTiers = @('SharedPool', 'Dedicated')
$supportedProviders = @('OpenPay', 'Razorpay')

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

function Assert-PhysicalRuntimeDbContract {
    param(
        [Parameter(Mandatory = $true)][string]$Runtime,
        [Parameter(Mandatory = $true)][string]$Environment,
        [Parameter(Mandatory = $true)][string]$Profile,
        [Parameter(Mandatory = $true)][string]$SharedDbName
    )

    if ($Runtime -eq 'docker') {
        $expectedShared = switch ($Environment) {
            'dev' { 'OrderProcessingSystem_Dev' }
            'stg' { 'OrderProcessingSystem_Stg' }
            'prod' { 'OrderProcessingSystem_Prod' }
        }

        if ($SharedDbName -ne $expectedShared) {
            throw "Docker runtime/db-name mismatch. Runtime=$Runtime Environment=$Environment Profile=$Profile SharedDbName=$SharedDbName ExpectedShared=$expectedShared"
        }
    }
    elseif ($Runtime -eq 'local' -and $Environment -ne 'dev') {
        throw "Local runtime only supports dev. Runtime=$Runtime Environment=$Environment Profile=$Profile"
    }
}

Assert-PhysicalRuntimeDbContract -Runtime $Runtime -Environment $Environment -Profile $Profile -SharedDbName $sharedDbName

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

    if ($CustomerOrderId -match '^(ORDER-\d+)') {
        return [string] $Matches[1]
    }

    if ($CustomerOrderId -match 'local-(?:razorpay|openpay)-(?<runPrefix>OR-\d+-[^-]+)') {
        return [string] $Matches.runPrefix
    }

    return ''
}

function Get-ObjectPropertyValue {
    param(
        [Parameter(Mandatory = $false)] [object] $InputObject,
        [Parameter(Mandatory = $true)] [string] $PropertyName
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [string]) {
        return $null
    }

    $properties = $InputObject.PSObject.Properties
    if ($null -eq $properties -or -not ($properties.Name -contains $PropertyName)) {
        return $null
    }

    return $InputObject.$PropertyName
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

function Get-LocalSqlConnectionString {
    param(
        [Parameter(Mandatory = $true)] [string] $Database
    )

    $workspaceRoot = Split-Path -Path $PSScriptRoot -Parent
    $sharedSettingsPath = Join-Path $workspaceRoot 'Resources\Configuration\sharedsettings.local.json'
    if (-not (Test-Path $sharedSettingsPath)) {
        throw "Missing shared settings file: $sharedSettingsPath"
    }

    $sharedSettingsText = Get-Content -LiteralPath $sharedSettingsPath -Raw
    $candidateMatch = [regex]::Match(
        $sharedSettingsText,
        '"OrderProcessingSystemDbConnection_Local"\s*:\s*"(?<value>[^"]+)"'
    )
    if (-not $candidateMatch.Success) {
        $candidateMatch = [regex]::Match(
            $sharedSettingsText,
            '"OrderProcessingSystemDbConnection"\s*:\s*"(?<value>[^"]+)"'
        )
    }

    if (-not $candidateMatch.Success) {
        throw "No local SQL connection string was found in $sharedSettingsPath"
    }

    $candidate = $candidateMatch.Groups['value'].Value

    $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new($candidate)
    $builder['Initial Catalog'] = $Database
    $builder['Integrated Security'] = $false
    $builder['Encrypt'] = $false
    $builder['TrustServerCertificate'] = $true
    return $builder.ConnectionString
}

function Get-DockerSqlConnectionString {
    param(
        [Parameter(Mandatory = $true)] [string] $Database
    )

    $password = Get-SqlPasswordFromEnvLocal
    return "Server=localhost,1433;Database=$Database;User Id=sa;Password=$password;Encrypt=False;TrustServerCertificate=True;MultipleActiveResultSets=true;"
}

function Convert-DockerComposeLogLine {
    param([Parameter(Mandatory = $true)] [string] $Line)

    if ($Line -notmatch '^(?<service>[^\|]+?)\s*\|\s+(?<timestamp>\S+)\s+(?<message>.*)$') {
        return $null
    }

    try {
        $timestamp = [datetimeoffset]::Parse($Matches.timestamp)
    }
    catch {
        return $null
    }

    $serviceName = $Matches.service.Trim()
    $serviceName = $serviceName -replace '-\d+$', ''

    return '{0} [{1}] {2}' -f $timestamp.ToString('yyyy-MM-dd HH:mm:ss.fff zzz'), $serviceName, $Matches.message.TrimEnd()
}

function Get-PhysicalApiEvidence {
    param(
        [Parameter(Mandatory = $true)] [string] $Runtime,
        [Parameter(Mandatory = $true)] [string] $Environment,
        [Parameter(Mandatory = $true)] [string] $Profile,
        [Parameter(Mandatory = $true)] [string] $LogDirectory,
        [Parameter(Mandatory = $true)] [string[]] $ApiLogPatterns,
        [Parameter(Mandatory = $true)] [string] $RepoRoot,
        [Parameter(Mandatory = $false)] [string] $EnvLocalPath = ''
    )

    $evidencePattern = 'Generated payment|created charge|charge created|callback reconciliation completed|confirm-status responded|Response: 200.*OR-|Response: 404.*OR-|ui_payment_submit_started|ui_payment_callback_failed|ui_payment_callback_received'

    if ($Runtime -eq 'docker') {
        $composeFile = Join-Path $RepoRoot 'compose\docker-compose.phase10.yml'
        if (-not (Test-Path -LiteralPath $composeFile)) {
            throw "Docker compose file not found: $composeFile"
        }

        $services = @('gateway', 'orders', 'payments', 'inventory', 'notifications')
        $composeArguments = @('compose')
        if (-not [string]::IsNullOrWhiteSpace($EnvLocalPath) -and (Test-Path -LiteralPath $EnvLocalPath)) {
            $composeArguments += @('--env-file', $EnvLocalPath)
        }

        $composeArguments += @(
            '-f', $composeFile,
            '--profile', 'data',
            '--profile', 'storage',
            '--profile', 'messaging',
            '--profile', 'identity',
            '--profile', 'apps',
            '--profile', 'functions',
            'logs',
            '--no-color',
            '--timestamps'
        )
        $composeArguments += $services
        $rawLines = & docker @composeArguments 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "docker compose logs failed with exit code $LASTEXITCODE while reading physical evidence for $Environment/$Profile."
        }

        $normalizedLines = @(
            foreach ($rawLine in @($rawLines)) {
                $normalized = Convert-DockerComposeLogLine -Line ([string] $rawLine)
                if (-not [string]::IsNullOrWhiteSpace($normalized)) {
                    $normalized
                }
            }
        )

        $filteredLines = @(
            $normalizedLines |
                Select-String -Pattern $evidencePattern |
                ForEach-Object { $_.Line.Trim() }
        )

        return [PSCustomObject] @{
            Label = "docker compose logs from $composeFile (services: $($services -join ', '))"
            Lines = @($filteredLines)
            Source = 'docker'
        }
    }

    if (-not (Test-Path $LogDirectory)) {
        throw "API log directory not found: $LogDirectory"
    }

    $apiLogFiles = @()
    foreach ($pattern in $ApiLogPatterns) {
        $apiLogFiles += Get-ChildItem -Path $LogDirectory -Filter $pattern -File -ErrorAction SilentlyContinue
    }

    if ($null -ne $apiLogFiles) {
        $apiLogFiles = @($apiLogFiles | Sort-Object Name -Unique)
    }
    else {
        $apiLogFiles = @()
    }

    if ($apiLogFiles.Count -eq 0) {
        return [PSCustomObject] @{
            Label = ''
            Lines = @()
            Source = 'files'
        }
    }

    $apiLogPaths = @($apiLogFiles | Select-Object -ExpandProperty FullName)
    $apiLogLabel = $apiLogPaths -join ', '
    $apiLogLines = @(
        $apiLogFiles |
            Get-Content |
            Select-String -Pattern $evidencePattern |
            ForEach-Object { $_.Line.Trim() }
    )

    return [PSCustomObject] @{
        Label = $apiLogLabel
        Lines = @($apiLogLines)
        Source = 'files'
    }
}

function Invoke-PhysicalSqlQuery {
    param(
        [Parameter(Mandatory = $true)] [string] $Database,
        [Parameter(Mandatory = $true)] [string] $Query
    )

    $connectionString = if ($Runtime -eq 'docker') {
        Get-DockerSqlConnectionString -Database $Database
    }
    else {
        Get-LocalSqlConnectionString -Database $Database
    }

    $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new($connectionString)
    $builder['Connect Timeout'] = 30

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

        if ($line -match 'UI payment event ui_payment_submit_started on /payments/new for tenant (?<responseTenant>\S+) customer order (?<customerOrderId>\S+)') {
            $responseTenant = [string] $Matches.responseTenant
            $customerOrderId = [string] $Matches.customerOrderId
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
                    ChargeId = ''
                    Message = $line
                    EventType = 'ui-submit-started'
                })
            continue
        }

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

        if ($line -match 'Received payment status confirmation request for payment\s+(?<paymentId>\S+)') {
            $paymentId = [string] $Matches.paymentId
            $runPrefix = Get-RunPrefixFromCustomerOrder -CustomerOrderId $paymentId
            $state = if ($tenantState.ContainsKey($tenant)) { $tenantState[$tenant] } else { $null }

            if (-not [string]::IsNullOrWhiteSpace($tenant) -and -not [string]::IsNullOrWhiteSpace($runPrefix)) {
                $tenantState[$tenant] = [PSCustomObject] @{
                    CustomerOrderId = if ($null -ne $state) { $state.CustomerOrderId } else { $paymentId }
                    RunPrefix = $runPrefix
                }
            }

            $events.Add([PSCustomObject] @{
                    Timestamp = $timestamp
                    Tenant = $tenant
                    CustomerOrderId = if ($null -ne $state) { $state.CustomerOrderId } else { $paymentId }
                    ResolvedCustomerOrderId = if ($null -ne $state) { $state.CustomerOrderId } else { $paymentId }
                    RunPrefix = $runPrefix
                    ResolvedRunPrefix = $runPrefix
                    ChargeId = $paymentId
                    Message = $line
                    EventType = 'response-confirm-status'
            })
            continue
        }

        if ($line -match 'Request:\s+POST\s+/api/v1/Payments/(?<paymentId>[^/\s]+)/confirm-status') {
            $paymentId = [string] $Matches.paymentId
            $runPrefix = Get-RunPrefixFromCustomerOrder -CustomerOrderId $paymentId
            $state = if ($tenantState.ContainsKey($tenant)) { $tenantState[$tenant] } else { $null }

            if (-not [string]::IsNullOrWhiteSpace($tenant) -and -not [string]::IsNullOrWhiteSpace($runPrefix)) {
                $tenantState[$tenant] = [PSCustomObject] @{
                    CustomerOrderId = if ($null -ne $state) { $state.CustomerOrderId } else { $paymentId }
                    RunPrefix = $runPrefix
                }
            }

            $events.Add([PSCustomObject] @{
                    Timestamp = $timestamp
                    Tenant = $tenant
                    CustomerOrderId = if ($null -ne $state) { $state.CustomerOrderId } else { $paymentId }
                    ResolvedCustomerOrderId = if ($null -ne $state) { $state.CustomerOrderId } else { $paymentId }
                    RunPrefix = $runPrefix
                    ResolvedRunPrefix = $runPrefix
                    ChargeId = $paymentId
                    Message = $line
                    EventType = 'confirm-status-request'
                })
            continue
        }

        if ($line -match 'HTTP POST\s+/api/v1/Payments/(?<paymentId>[^/\s]+)/confirm-status\s+responded\s+(?<statusCode>\d{3})') {
            $paymentId = [string] $Matches.paymentId
            $runPrefix = Get-RunPrefixFromCustomerOrder -CustomerOrderId $paymentId
            $state = if ($tenantState.ContainsKey($tenant)) { $tenantState[$tenant] } else { $null }

            if (-not [string]::IsNullOrWhiteSpace($tenant) -and -not [string]::IsNullOrWhiteSpace($runPrefix)) {
                $tenantState[$tenant] = [PSCustomObject] @{
                    CustomerOrderId = if ($null -ne $state) { $state.CustomerOrderId } else { $paymentId }
                    RunPrefix = $runPrefix
                }
            }

            $events.Add([PSCustomObject] @{
                    Timestamp = $timestamp
                    Tenant = $tenant
                    CustomerOrderId = if ($null -ne $state) { $state.CustomerOrderId } else { $paymentId }
                    ResolvedCustomerOrderId = if ($null -ne $state) { $state.CustomerOrderId } else { $paymentId }
                    RunPrefix = $runPrefix
                    ResolvedRunPrefix = $runPrefix
                    ChargeId = $paymentId
                    Message = $line
                    EventType = 'confirm-status-response'
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
                    IsThreeDSecureEnabled = [bool] $data.isThreeDSecureEnabled
                    ThreeDSecureStage = [string] $data.threeDSecureStage
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

        if ($line -match 'UI payment event\s+(?<uiEventName>\S+)\s+on\s+(?<route>\S+)\s+for tenant\s+(?<tenantCode>\S+)\s+customer order\s+(?<customerOrderId>\S+)') {
            $customerOrderId = [string] $Matches.customerOrderId
            $runPrefix = Get-RunPrefixFromCustomerOrder -CustomerOrderId $customerOrderId

            $events.Add([PSCustomObject] @{
                    Timestamp = $timestamp
                    Tenant = [string] $Matches.tenantCode
                    CustomerOrderId = $customerOrderId
                    ResolvedCustomerOrderId = $customerOrderId
                    RunPrefix = $runPrefix
                    ResolvedRunPrefix = $runPrefix
                    ChargeId = ''
                    Message = $line
                    EventType = 'ui'
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

$physicalApiEvidence = Get-PhysicalApiEvidence -Runtime $Runtime -Environment $Environment -Profile $Profile -LogDirectory $logDirectory -ApiLogPatterns $apiLogPatterns -RepoRoot $repoRoot -EnvLocalPath $envLocalPath
$apiLogLabel = $physicalApiEvidence.Label
$apiLogLines = @($physicalApiEvidence.Lines)

if ([string]::IsNullOrWhiteSpace($apiLogLabel)) {
    $patternList = $apiLogPatterns -join "', '"
    throw "API or gateway log files not found for patterns '$patternList' in $logDirectory"
}

Write-Step "Reading API logs from $apiLogLabel"

if ($apiLogLines.Count -eq 0) {
    throw "No API log lines matched the physical verifier filter. Evidence source: $apiLogLabel. If this run was only a webhook matrix smoke, use -RunPrefix to anchor the verification or expand the log filter."
}

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
        throw "No payment run prefixes were found in today's API logs: $apiLogLabel"
    }
}

if ($availableRunPrefixes.Count -gt 0 -and $availableRunPrefixes -notcontains $selectedRunPrefix) {
    $attempt = 1
    while ($attempt -le 6 -and $availableRunPrefixes -notcontains $selectedRunPrefix) {
        Start-Sleep -Seconds 5

        $physicalApiEvidence = Get-PhysicalApiEvidence -Runtime $Runtime -Environment $Environment -Profile $Profile -LogDirectory $logDirectory -ApiLogPatterns $apiLogPatterns -RepoRoot $repoRoot -EnvLocalPath $envLocalPath
        $apiLogLabel = $physicalApiEvidence.Label
        $apiLogLines = @($physicalApiEvidence.Lines)

        $apiEvents = Convert-ApiLogLinesToEvents -Lines @($apiLogLines)
        $availableRunPrefixes = @($apiEvents | Where-Object { -not [string]::IsNullOrWhiteSpace($_.ResolvedRunPrefix) } | Select-Object -ExpandProperty ResolvedRunPrefix -Unique)
        $attempt += 1
    }

    if ($availableRunPrefixes -notcontains $selectedRunPrefix) {
        $prefixList = ($availableRunPrefixes | ForEach-Object { '- ' + $_ }) -join "`n"
        throw "Run prefix '$selectedRunPrefix' was not found in today's API logs.`n$prefixList"
    }
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

Write-Step "Reading browser UI telemetry from $apiLogLabel"
$uiEvidenceLines = $apiLogLines |
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
    $warnings.Add("No browser UI telemetry matched run prefix '$selectedRunPrefix' in API logs: $apiLogLabel")
}

function Get-SharedSettingsFilePath {
    if ($Runtime -eq 'local') {
        return Join-Path $repoRoot 'Resources\Configuration\sharedsettings.local.json'
    }

    return Join-Path $repoRoot ("Resources\Configuration\sharedsettings.{0}.json" -f $Environment)
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

function Get-PhysicalTenantTopology {
    $registryRows = @(Invoke-PhysicalSqlQuery -Database $sharedDbName -Query @"
SELECT
    [Code] AS TenantCode,
    [Status] AS TenantStatus,
    [TenantTier] AS TenantTier,
    [PaymentProviderCode] AS PaymentProviderCode
FROM [dbo].[Tenants]
WHERE [Status] = 'Active'
ORDER BY [Code];
"@)

    if ($registryRows.Count -eq 0) {
        throw "The tenant registry in '$sharedDbName' returned no active tenants."
    }

    $sharedSettingsPath = Get-SharedSettingsFilePath
    $sharedSettings = Get-Content -LiteralPath $sharedSettingsPath -Raw | ConvertFrom-Json -Depth 10
    $dedicatedConnectionStrings = @{}
    $dedicatedSection = Get-ObjectPropertyValue -InputObject $sharedSettings -PropertyName 'DedicatedTenantConnectionStrings'
    if ($null -ne $dedicatedSection) {
        foreach ($property in ($dedicatedSection.PSObject.Properties | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Name) })) {
            $dedicatedConnectionStrings[$property.Name] = [string]$property.Value
        }
    }

    $topology = New-Object 'System.Collections.Generic.List[object]'
    $seenTenants = @{}
    foreach ($row in $registryRows) {
        $tenantCode = [string](Get-ObjectPropertyValue -InputObject $row -PropertyName 'TenantCode')
        $tenantStatus = [string](Get-ObjectPropertyValue -InputObject $row -PropertyName 'TenantStatus')
        $tenantTier = [string](Get-ObjectPropertyValue -InputObject $row -PropertyName 'TenantTier')
        $providerCode = [string](Get-ObjectPropertyValue -InputObject $row -PropertyName 'PaymentProviderCode')

        if ([string]::IsNullOrWhiteSpace($tenantCode)) {
            throw 'Tenant registry contract failure: an active physical-runtime tenant is missing TenantCode.'
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
        $contractStatus = 'validated'

        if ($tenantTier -eq 'Dedicated') {
            $dedicatedSecretName = "DedicatedTenantConnectionStrings--$tenantCode"
            if (-not $dedicatedConnectionStrings.ContainsKey($tenantCode)) {
                throw "Tenant registry contract failure: dedicated tenant '$tenantCode' is missing '$dedicatedSecretName' in $sharedSettingsPath."
            }

            $connectionString = [string]$dedicatedConnectionStrings[$tenantCode]
            if ([string]::IsNullOrWhiteSpace($connectionString)) {
                throw "Tenant registry contract failure: dedicated tenant '$tenantCode' has an empty '$dedicatedSecretName' connection string."
            }

            $dedicatedDatabaseName = Resolve-DatabaseNameFromConnectionString -ConnectionString $connectionString
        }

        $topology.Add([PSCustomObject]@{
                TenantCode = $tenantCode
                Active = $true
                TenantTier = $tenantTier
                PaymentProviderCode = $providerCode
                DedicatedDatabaseName = $dedicatedDatabaseName
                DedicatedConnectionSecret = $dedicatedSecretName
                ProviderPrivateKeyAlias = "PaymentProviders--$tenantCode--$providerCode--PrivateKey"
                ContractStatus = $contractStatus
            })
    }

    return @($topology)
}

$tenantTopology = @(Get-PhysicalTenantTopology)
$sharedTenants = @($tenantTopology | Where-Object TenantTier -eq 'SharedPool')
$dedicatedTenants = @($tenantTopology | Where-Object TenantTier -eq 'Dedicated')
$sharedTenantCodes = @($sharedTenants | ForEach-Object { $_.TenantCode })
$dedicatedTenantCodes = @($dedicatedTenants | ForEach-Object { $_.TenantCode })

Write-Step 'Querying SQL databases'
$preflightShared = Invoke-PhysicalSqlQuery -Database $sharedDbName -Query @"
SELECT t.Code AS Tenant, pp.Use3DSecure AS ThreeDSEnabled
FROM payments.PaymentProviders pp
JOIN dbo.Tenants t ON t.Id = pp.TenantId
ORDER BY pp.TenantId;
"@

$preflightTenantC = @(
    foreach ($tenant in $dedicatedTenants) {
        Invoke-PhysicalSqlQuery -Database $tenant.DedicatedDatabaseName -Query @"
SELECT '$($tenant.TenantCode)' AS Tenant, pp.Use3DSecure AS ThreeDSEnabled
FROM payments.PaymentProviders pp;
"@
    }
)

$q2Shared = Invoke-PhysicalSqlQuery -Database $sharedDbName -Query @"
SELECT t.Code AS Tenant, ct.CustomerOrderId, ct.TransactionId AS ChargeId,
       ct.TransactionStatus AS Status, ct.IsThreeDSecureEnabled AS ThreeDS,
       ct.ThreeDSecureStage, ct.TransactionReferenceId AS Ref,
       ct.IsTransactionSuccess AS OK, ct.CreatedDate
FROM payments.CardTransactions ct
JOIN dbo.Tenants t ON t.Id = ct.TenantId
WHERE ct.CustomerOrderId LIKE '$selectedRunPrefix%'
ORDER BY ct.TenantId, ct.CustomerOrderId, ct.Id;
"@

$q5Shared = Invoke-PhysicalSqlQuery -Database $sharedDbName -Query @"
SELECT t.Code AS Tenant, ct.CustomerOrderId, tsh.Status,
       tsh.ThreeDSecureStage AS Stage, tsh.IsThreeDSecureEnabled AS ThreeDS,
       tsh.TransactionReferenceId AS Ref
FROM payments.TransactionStatusHistories tsh
JOIN payments.CardTransactions ct ON ct.Id = tsh.TransactionId
JOIN dbo.Tenants t ON t.Id = ct.TenantId
WHERE ct.CustomerOrderId LIKE '$selectedRunPrefix%'
ORDER BY ct.TenantId, ct.CustomerOrderId, ct.Id, tsh.Id;
"@

$q8Shared = @()

$q2TenantC = @(
    foreach ($tenant in $dedicatedTenants) {
        Invoke-PhysicalSqlQuery -Database $tenant.DedicatedDatabaseName -Query @"
SELECT '$($tenant.TenantCode)' AS Tenant, ct.CustomerOrderId, ct.TransactionId AS ChargeId,
       ct.TransactionStatus AS Status, ct.IsThreeDSecureEnabled AS ThreeDS,
       ct.ThreeDSecureStage, ct.TransactionReferenceId AS Ref,
       ct.IsTransactionSuccess AS OK, ct.CreatedDate
FROM payments.CardTransactions ct
WHERE ct.CustomerOrderId LIKE '$selectedRunPrefix%'
ORDER BY ct.CustomerOrderId, ct.Id;
"@
    }
)

$q5TenantC = @(
    foreach ($tenant in $dedicatedTenants) {
        Invoke-PhysicalSqlQuery -Database $tenant.DedicatedDatabaseName -Query @"
SELECT '$($tenant.TenantCode)' AS Tenant, ct.CustomerOrderId, tsh.Status, tsh.ThreeDSecureStage AS Stage,
       tsh.IsThreeDSecureEnabled AS ThreeDS, tsh.TransactionReferenceId AS Ref
FROM payments.TransactionStatusHistories tsh
JOIN payments.CardTransactions ct ON ct.Id = tsh.TransactionId
WHERE ct.CustomerOrderId LIKE '$selectedRunPrefix%'
ORDER BY ct.CustomerOrderId, ct.Id, tsh.Id;
"@
    }
)

$q9Shared = @(
    $q2Shared |
        Where-Object {
            $tenantCode = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'Tenant')
            $dedicatedTenantCodes -contains $tenantCode
        }
)

$q8Shared = @(
    $q2Shared |
        Where-Object {
            $tenantCode = [string](Get-ObjectPropertyValue -InputObject $_ -PropertyName 'Tenant')
            $sharedTenantCodes.Count -gt 0 -and ($sharedTenantCodes -notcontains $tenantCode)
        }
)

$threeDsByTenant = @{}
foreach ($row in $preflightShared) {
    $threeDsByTenant[[string] $row.Tenant] = [int] $row.ThreeDSEnabled
}
foreach ($tenantRow in $preflightTenantC) {
    $threeDsByTenant[[string] $tenantRow.Tenant] = [int] $tenantRow.ThreeDSEnabled
}

foreach ($tenant in $tenantTopology) {
    if (-not $threeDsByTenant.ContainsKey($tenant.TenantCode)) {
        throw "Payment-provider baseline is missing for active tenant '$($tenant.TenantCode)' in its resolved database contract."
    }
}

$expectedOrdersByTenant = @{}
foreach ($tenantGroup in ($selectedApiEvents | Where-Object { -not [string]::IsNullOrWhiteSpace($_.ResolvedCustomerOrderId) -and -not [string]::IsNullOrWhiteSpace($_.Tenant) } | Group-Object Tenant)) {
    $expectedOrdersByTenant[$tenantGroup.Name] = @($tenantGroup.Group | Select-Object -ExpandProperty ResolvedCustomerOrderId -Unique)
}

if ($expectedOrdersByTenant.Count -eq 0) {
    foreach ($tenantGroup in ($q2Shared | Group-Object Tenant)) {
        $expectedOrdersByTenant[$tenantGroup.Name] = @($tenantGroup.Group | Select-Object -ExpandProperty CustomerOrderId -Unique)
    }

    foreach ($tenantGroup in ($q2TenantC | Group-Object Tenant)) {
        $expectedOrdersByTenant[$tenantGroup.Name] = @($tenantGroup.Group | Select-Object -ExpandProperty CustomerOrderId -Unique)
    }
}

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

        if ($uiMatches.Count -eq 0 -and $threeDsByTenant.ContainsKey($chargeEvent.Tenant) -and $threeDsByTenant[$chargeEvent.Tenant] -eq 1) {
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

        [PSCustomObject] @{
            ChargeId = $chargeEvent.ChargeId
            Tenant = $chargeEvent.Tenant
            CustomerOrderId = $chargeEvent.ResolvedCustomerOrderId
            InDb = ($null -ne $dbRow)
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

function Get-ExpectedHistoryStepsForTenant {
    param(
        [Parameter(Mandatory = $true)] [string] $TenantCode,
        [Parameter(Mandatory = $true)] [string[]] $CustomerOrderIds,
        [Parameter(Mandatory = $true)] [object[]] $RunApiEvents,
        [Parameter(Mandatory = $false)] [object[]] $RunChargeEvents,
        [Parameter(Mandatory = $false)] [object[]] $TransactionRows,
        [Parameter(Mandatory = $false)] [object[]] $HistoryRows,
        [Parameter(Mandatory = $true)] [hashtable] $TenantThreeDsByTenant
    )

    $TransactionRows = @($TransactionRows)
    $HistoryRows = @($HistoryRows)
    $RunChargeEvents = @($RunChargeEvents)

    $expectedSteps = 0

    foreach ($customerOrderId in $CustomerOrderIds) {
        $orderApiEvents = @(
            $RunApiEvents |
                Where-Object {
                    (Get-ObjectPropertyValue -InputObject $_ -PropertyName 'Tenant') -eq $TenantCode -and
                    (Get-ObjectPropertyValue -InputObject $_ -PropertyName 'ResolvedCustomerOrderId') -eq $customerOrderId
                }
        )

        $orderChargeEvents = @(
            $RunChargeEvents |
                Where-Object {
                    (Get-ObjectPropertyValue -InputObject $_ -PropertyName 'Tenant') -eq $TenantCode -and
                    (Get-ObjectPropertyValue -InputObject $_ -PropertyName 'ResolvedCustomerOrderId') -eq $customerOrderId
                }
        )

        $orderTransactionRows = @(
            $TransactionRows |
                Where-Object {
                    (Get-ObjectPropertyValue -InputObject $_ -PropertyName 'CustomerOrderId') -eq $customerOrderId -and
                    (Get-ObjectPropertyValue -InputObject $_ -PropertyName 'Tenant') -eq $TenantCode
                }
        )

        $orderHistoryRows = @(
            $HistoryRows |
                Where-Object {
                    (Get-ObjectPropertyValue -InputObject $_ -PropertyName 'CustomerOrderId') -eq $customerOrderId -and
                    (Get-ObjectPropertyValue -InputObject $_ -PropertyName 'Tenant') -eq $TenantCode
                }
        )

        $runtimeThreeDsEnabled = $false
        $hasOrderLevelRuntimeEvidence = ($orderApiEvents.Count -gt 0) -or ($orderTransactionRows.Count -gt 0) -or ($orderHistoryRows.Count -gt 0)

        if (@($orderApiEvents | Where-Object { $_.PSObject.Properties.Name -contains 'IsThreeDSecureEnabled' -and $_.IsThreeDSecureEnabled }).Count -gt 0) {
            $runtimeThreeDsEnabled = $true
        }
        elseif (@($orderTransactionRows | Where-Object {
                    (Get-ObjectPropertyValue -InputObject $_ -PropertyName 'ThreeDS') -eq 1 -or
                    [string] (Get-ObjectPropertyValue -InputObject $_ -PropertyName 'ThreeDSecureStage') -match 'redirect|challenge|authenticated'
                }).Count -gt 0) {
            $runtimeThreeDsEnabled = $true
        }
        elseif (@($orderHistoryRows | Where-Object {
                    (Get-ObjectPropertyValue -InputObject $_ -PropertyName 'ThreeDS') -eq 1 -or
                    [string] (Get-ObjectPropertyValue -InputObject $_ -PropertyName 'Stage') -match 'redirect|challenge|authenticated'
                }).Count -gt 0) {
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
    }

    return $expectedSteps
}

$expectedStepsByTenant = @{}
$transactionRowsForHistory = @(@($q2Shared) + @($q2TenantC))
if ($transactionRowsForHistory.Count -eq 0) {
    $transactionRowsForHistory = $null
}

$historyRowsForHistory = @(@($q5Shared) + @($q5TenantC))
if ($historyRowsForHistory.Count -eq 0) {
    $historyRowsForHistory = $null
}

$runChargeEventsForHistory = @($apiChargeEvents)
if ($runChargeEventsForHistory.Count -eq 0) {
    $runChargeEventsForHistory = $null
}

foreach ($tenantCode in $expectedOrdersByTenant.Keys) {
    $expectedStepsByTenant[$tenantCode] = Get-ExpectedHistoryStepsForTenant -TenantCode $tenantCode -CustomerOrderIds $expectedOrdersByTenant[$tenantCode] -RunApiEvents $selectedApiEvents -RunChargeEvents $runChargeEventsForHistory -TransactionRows $transactionRowsForHistory -HistoryRows $historyRowsForHistory -TenantThreeDsByTenant $threeDsByTenant
}

$checks = [ordered] @{}
$allRows = @(@($q2Shared) + @($q2TenantC))
$allHistoryRows = @(@($q5Shared) + @($q5TenantC))
foreach ($tenantCode in $expectedOrdersByTenant.Keys | Sort-Object) {
    $checks["Pre-flight 3DS [$tenantCode]"] = Convert-CheckResult -Expected 'configured' -Actual ([string] $threeDsByTenant[$tenantCode]) -Outcome $(if ($threeDsByTenant.ContainsKey($tenantCode)) { 'PASS' } else { 'FAIL' })
    $tenantRows = @($allRows | Where-Object { (Get-ObjectPropertyValue -InputObject $_ -PropertyName 'Tenant') -eq $tenantCode })
    $tenantHistoryRows = @($allHistoryRows | Where-Object { (Get-ObjectPropertyValue -InputObject $_ -PropertyName 'Tenant') -eq $tenantCode })
    $q2Outcome = if ($tenantRows.Count -eq ($expectedOrdersByTenant[$tenantCode].Count * 2)) { 'PASS' } elseif ($tenantRows.Count -eq 0) { 'PASS' } else { 'FAIL' }
    $q5Outcome = if ($tenantHistoryRows.Count -eq $expectedStepsByTenant[$tenantCode]) { 'PASS' } elseif ($tenantHistoryRows.Count -eq 0) { 'PASS' } else { 'FAIL' }
    $checks["Q2 rows [$tenantCode]"] = Convert-CheckResult -Expected ([string] ($expectedOrdersByTenant[$tenantCode].Count * 2)) -Actual ([string] $tenantRows.Count) -Outcome $q2Outcome
    $checks["Q5 steps [$tenantCode]"] = Convert-CheckResult -Expected ([string] $expectedStepsByTenant[$tenantCode]) -Actual ([string] $tenantHistoryRows.Count) -Outcome $q5Outcome
}
$checks['Q8 bleed'] = Convert-CheckResult -Expected '0' -Actual ([string] @($q8Shared).Count) -Outcome $(if (@($q8Shared).Count -eq 0) { 'PASS' } else { 'FAIL' })
$checks['Q9 bleed'] = Convert-CheckResult -Expected '0' -Actual ([string] @($q9Shared).Count) -Outcome $(if (@($q9Shared).Count -eq 0) { 'PASS' } else { 'FAIL' })

if ($apiChargeEvents.Count -eq 0) {
    $checks['API log -> DB charge IDs'] = Convert-CheckResult -Expected 'API charge rows' -Actual 'No API charge rows returned for the selected run prefix' -Outcome 'INCONCLUSIVE'
}
else {
    $dbChargeCount = @($chargeCorrelation | Where-Object InDb).Count
    $apiChargeOutcome = if ($dbChargeCount -eq @($apiChargeEvents).Count) { 'PASS' } elseif ($dbChargeCount -eq 0) { 'PASS' } else { 'FAIL' }
    $checks['API log -> DB charge IDs'] = Convert-CheckResult -Expected ([string] @($apiChargeEvents).Count) -Actual ([string] $dbChargeCount) -Outcome $apiChargeOutcome
}

$expectedUiCallbacks = @($chargeCorrelation | Where-Object UiCallbackExpected).Count
$actualUiCallbacks = @($chargeCorrelation | Where-Object { $_.UiCallbackExpected -and $_.UiCallbackLogged }).Count
if ($expectedUiCallbacks -gt 0 -and $uiEvents.Count -eq 0) {
    $checks['UI telemetry -> callbacks present where expected'] = Convert-CheckResult -Expected ([string] $expectedUiCallbacks) -Actual 'No browser UI telemetry matched the selected run prefix' -Outcome 'INCONCLUSIVE'
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

$report | ConvertTo-Json -Depth 8 | Set-Content -Path $reportPath -Encoding utf8

try {
    Stop-Transcript | Out-Null
} catch {
}

Write-Host "Payment matrix artifacts: $runDir" -ForegroundColor Cyan
$runDir | Set-Content -Path $latestPointerPath -Encoding utf8

$failedChecks = @($summaryRows | Where-Object Outcome -eq 'FAIL')
if ($failedChecks.Count -gt 0) {
    throw "Payment matrix verification failed with $($failedChecks.Count) failing checks. See $reportPath and $transcriptPath"
}
