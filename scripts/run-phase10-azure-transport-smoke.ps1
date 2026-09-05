param(
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'dev',

    [string]$ResourceGroupName,
    [string]$ServiceBusNamespaceName,
    [string]$GatewayContainerAppName,
    [string]$KeyVaultName,
    [string]$SqlServerName,
    [string]$ConnectionString,
    [string]$RunId,
    [string]$SummaryPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$resourceSuffix = if ($Environment -eq 'staging') { 'stg' } else { $Environment }
$brokerSuffix = $Environment
$resourceGroup = if ([string]::IsNullOrWhiteSpace($ResourceGroupName)) { "rg-orderprocessing-$resourceSuffix" } else { $ResourceGroupName }
$namespace = if ([string]::IsNullOrWhiteSpace($ServiceBusNamespaceName)) { "sb-orderprocessing-$resourceSuffix" } else { $ServiceBusNamespaceName }
$smokeRunId = if ([string]::IsNullOrWhiteSpace($RunId)) { "phase10-transport-$brokerSuffix-$(Get-Date -Format 'yyyyMMddHHmmss')" } else { $RunId }
$gatewayApp = if ([string]::IsNullOrWhiteSpace($GatewayContainerAppName)) { "orderprocessing-gate-$resourceSuffix" } else { $GatewayContainerAppName }
$keyVaultName = if ([string]::IsNullOrWhiteSpace($KeyVaultName)) { "kv-orderprocessing-$resourceSuffix" } else { $KeyVaultName }
$sqlServerName = if ([string]::IsNullOrWhiteSpace($SqlServerName)) { "orderprocessing-sql-$resourceSuffix" } else { $SqlServerName }
$sqlServerFqdn = "$sqlServerName.database.windows.net"
$sharedDbName = switch ($Environment) {
    'dev' { 'OrderProcessingSystem_Dev' }
    'staging' { 'OrderProcessingSystem_Staging' }
    'prod' { 'OrderProcessingSystem_Prod' }
}
$supportedTenantTiers = @('SharedPool', 'Dedicated')
$supportedProviders = @('OpenPay', 'Razorpay')

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Invoke-AzureCliText {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Command,
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $false)][int]$MaxAttempts = 3
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            $result = & $Command 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw (($result | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
            }

            $text = (($result | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).Trim()
            if ([string]::IsNullOrWhiteSpace($text)) {
                throw "$Operation returned no response."
            }

            return $text
        }
        catch {
            if ($attempt -ge $MaxAttempts) {
                throw "${Operation} failed after $MaxAttempts attempt(s). $($_.Exception.Message)"
            }

            Start-Sleep -Seconds $attempt
        }
    }

    throw "$Operation failed unexpectedly."
}

function Get-PublicIpAddress {
    $candidates = @(
        'https://api.ipify.org?format=json',
        'https://ifconfig.me/ip'
    )

    foreach ($endpoint in $candidates) {
        try {
            $response = Invoke-RestMethod -Uri $endpoint -Method Get -TimeoutSec 15
            $value = if ($response -is [string]) {
                $response.Trim()
            }
            else {
                [string]$response.ip
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

function Ensure-AzureSqlFirewallAccess {
    $ruleName = "phase10-transport-smoke-$resourceSuffix"
    $publicIp = Get-PublicIpAddress

    $result = az sql server firewall-rule create `
        --resource-group $resourceGroup `
        --server $sqlServerName `
        --name $ruleName `
        --start-ip-address $publicIp `
        --end-ip-address $publicIp 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "Open Azure SQL firewall access failed. $((@($result | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine).Trim())"
    }

    Write-Host "Opened Azure SQL firewall rule '$ruleName' for $publicIp." -ForegroundColor DarkGray
}

function Resolve-DatabaseNameFromConnectionString {
    param([Parameter(Mandatory = $true)][string]$ConnectionString)

    $match = [regex]::Match($ConnectionString, '(?i)(?:Initial\s+Catalog|Database)\s*=\s*([^;]+)')
    if (-not $match.Success) {
        throw "Connection string does not contain an Initial Catalog/Database segment."
    }

    return $match.Groups[1].Value.Trim()
}

function Get-GatewayFqdn {
    Invoke-AzureCliText -Operation "Resolve gateway FQDN for $gatewayApp" -Command {
        az containerapp show --resource-group $resourceGroup --name $gatewayApp --query properties.configuration.ingress.fqdn -o tsv
    }
}

function Get-RuntimeTenantTopology {
    $attempts = 6
    $lastError = 'No response.'

    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        try {
            $gatewayFqdn = Get-GatewayFqdn
            if ([string]::IsNullOrWhiteSpace($gatewayFqdn)) {
                throw "Gateway FQDN for '$gatewayApp' could not be resolved."
            }

            $uri = "https://$gatewayFqdn/api/v1/Info/tenant-registry"
            $response = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 60
            $items = @($response)
            if ($items.Count -eq 0) {
                throw 'Tenant registry endpoint returned no active tenants.'
            }

            return [PSCustomObject]@{
                GatewayFqdn = $gatewayFqdn
                RegistryUri = $uri
                Items = $items
            }
        }
        catch {
            $lastError = $_.Exception.Message
            if ($attempt -lt $attempts) {
                Write-Host "Tenant topology endpoint not ready yet ($attempt/$attempts). $lastError" -ForegroundColor Yellow
                Start-Sleep -Seconds 10
            }
        }
    }

    throw "Failed to resolve tenant topology from the runtime after $attempts attempt(s). $lastError"
}

function Resolve-ValidatedTenantTopology {
    $topology = Get-RuntimeTenantTopology
    $validated = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}

    foreach ($tenant in $topology.Items) {
        $tenantId = [int]$tenant.TenantId
        $tenantCode = [string]$tenant.TenantCode
        $tenantTier = [string]$tenant.TenantTier
        $providerCode = [string]$tenant.PaymentProviderCode

        if ([string]::IsNullOrWhiteSpace($tenantCode)) {
            throw 'Tenant registry contract failure: an active Azure tenant is missing TenantCode.'
        }

        if ($seen.ContainsKey($tenantCode)) {
            throw "Tenant registry contract failure: duplicate active tenant '$tenantCode' was returned."
        }
        $seen[$tenantCode] = $true

        if ($tenantId -le 0) {
            throw "Tenant registry contract failure: tenant '$tenantCode' has invalid TenantId '$tenantId'."
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

        $providerPrivateKeyAlias = "PaymentProviders--$tenantCode--$providerCode--PrivateKey"
        $providerSecretValue = Invoke-AzureCliText -Operation "Resolve $providerPrivateKeyAlias from Key Vault" -Command {
            az keyvault secret show --vault-name $keyVaultName --name $providerPrivateKeyAlias --query value -o tsv
        }

        if ([string]::IsNullOrWhiteSpace($providerSecretValue)) {
            throw "Tenant registry contract failure: active tenant/provider mapping '$tenantCode/$providerCode' is missing Key Vault secret '$providerPrivateKeyAlias'."
        }

        $dedicatedSecretName = $null
        $dedicatedDatabaseName = $null
        $verificationDatabaseName = $sharedDbName

        if ($tenantTier -eq 'Dedicated') {
            $dedicatedSecretName = "DedicatedTenantConnectionStrings--$tenantCode"
            $dedicatedConnectionString = Invoke-AzureCliText -Operation "Resolve $dedicatedSecretName from Key Vault" -Command {
                az keyvault secret show --vault-name $keyVaultName --name $dedicatedSecretName --query value -o tsv
            }

            if ([string]::IsNullOrWhiteSpace($dedicatedConnectionString)) {
                throw "Tenant registry contract failure: dedicated tenant '$tenantCode' is missing Key Vault secret '$dedicatedSecretName'."
            }

            $dedicatedDatabaseName = Resolve-DatabaseNameFromConnectionString -ConnectionString $dedicatedConnectionString
            $verificationDatabaseName = $dedicatedDatabaseName
        }

        $validated.Add([PSCustomObject]@{
                TenantId = $tenantId
                TenantCode = $tenantCode
                Active = $true
                Tier = $tenantTier
                ProviderCode = $providerCode
                DedicatedDatabaseName = $dedicatedDatabaseName
                DedicatedConnectionSecret = $dedicatedSecretName
                ProviderPrivateKeyAlias = $providerPrivateKeyAlias
                VerificationDatabaseName = $verificationDatabaseName
                ContractStatus = 'validated'
                GatewayFqdn = $topology.GatewayFqdn
                RegistryUri = $topology.RegistryUri
            })
    }

    if ($validated.Count -eq 0) {
        throw 'Tenant registry endpoint returned no active tenants after validation.'
    }

    return $validated.ToArray()
}

function Write-TopologyArtifact {
    param(
        [Parameter(Mandatory = $true)][object[]]$Topology,
        [Parameter(Mandatory = $true)][string]$ArtifactPath
    )

    $directory = Split-Path -Parent $ArtifactPath
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    @(
        $Topology | Select-Object `
            @{ Name = 'tenantCode'; Expression = { $_.TenantCode } }, `
            @{ Name = 'active'; Expression = { $_.Active } }, `
            @{ Name = 'tier'; Expression = { $_.Tier } }, `
            @{ Name = 'providerCode'; Expression = { $_.ProviderCode } }, `
            @{ Name = 'dedicatedDatabaseName'; Expression = { $_.DedicatedDatabaseName } }, `
            @{ Name = 'dedicatedConnectionSecret'; Expression = { $_.DedicatedConnectionSecret } }, `
            @{ Name = 'providerPrivateKeyAlias'; Expression = { $_.ProviderPrivateKeyAlias } }, `
            @{ Name = 'contractStatus'; Expression = { $_.ContractStatus } }
    ) | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ArtifactPath -Encoding UTF8
}

if ([string]::IsNullOrWhiteSpace($ConnectionString)) {
    Write-Step "Retrieving Service Bus connection string from auth rule 'phase10-transport'"
    $ConnectionString = az servicebus namespace authorization-rule keys list `
        --resource-group $resourceGroup `
        --namespace-name $namespace `
        --name phase10-transport `
        --query primaryConnectionString `
        -o tsv
}

if ([string]::IsNullOrWhiteSpace($ConnectionString)) {
    throw "Service Bus connection string could not be resolved for namespace '$namespace'."
}

$sqlAdminUser = Invoke-AzureCliText -Operation 'Resolve SQL administrator login' -Command {
    az sql server show --name $sqlServerName --resource-group $resourceGroup --query administratorLogin -o tsv
}
$sqlAdminPassword = Invoke-AzureCliText -Operation 'Resolve sql-admin-password from Key Vault' -Command {
    az keyvault secret show --vault-name $keyVaultName --name sql-admin-password --query value -o tsv
}

Write-Step "Opening Azure SQL firewall access"
Ensure-AzureSqlFirewallAccess

Write-Step "Resolving runtime tenant topology and validating tenant/provider contracts"
$tenantTopology = @(Resolve-ValidatedTenantTopology)
$selectedTenant = @($tenantTopology | Where-Object Tier -eq 'SharedPool' | Select-Object -First 1)[0]
if ($null -eq $selectedTenant) {
    $selectedTenant = $tenantTopology[0]
}

$sqlConnectionString = "Server=tcp:$sqlServerFqdn,1433;Initial Catalog=$($selectedTenant.VerificationDatabaseName);Persist Security Info=False;User ID=$sqlAdminUser;Password=$sqlAdminPassword;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
$env:PHASE10_TRANSPORT_SQL_CONNECTION_STRING = $sqlConnectionString

if (-not [string]::IsNullOrWhiteSpace($SummaryPath)) {
    $topologyPath = [System.IO.Path]::ChangeExtension($SummaryPath, '.topology.json')
    Write-TopologyArtifact -Topology $tenantTopology -ArtifactPath $topologyPath
}

$toolProject = Join-Path $PSScriptRoot '..\tools\Phase10.TransportSmoke\Phase10.TransportSmoke.csproj'
$arguments = @(
    'run',
    '--project', $toolProject,
    '--',
    '--environment', $Environment,
    '--namespace', $namespace,
    '--topic', "order-events-$brokerSuffix",
    '--inventory-subscription', "inventory-order-created-$brokerSuffix",
    '--notifications-subscription', "notifications-order-created-$brokerSuffix",
    '--dead-letter-topic', 'order-events-dlq',
    '--dead-letter-subscription', "dlq-replay-$brokerSuffix",
    '--connection-string', $ConnectionString,
    '--sql-database', $selectedTenant.VerificationDatabaseName,
    '--tenant-id', $selectedTenant.TenantId,
    '--tenant-code', $selectedTenant.TenantCode,
    '--run-id', $smokeRunId
)

Write-Host "Using validated smoke tenant '$($selectedTenant.TenantCode)' (Tier=$($selectedTenant.Tier), Provider=$($selectedTenant.ProviderCode), Db=$($selectedTenant.VerificationDatabaseName))." -ForegroundColor DarkGray
Write-Host "Running Phase 10 Azure transport smoke for '$Environment'..."
$output = & dotnet @arguments
$exitCode = $LASTEXITCODE

$output | ForEach-Object { Write-Output $_ }

if (-not [string]::IsNullOrWhiteSpace($SummaryPath)) {
    $summaryDirectory = Split-Path -Parent $SummaryPath
    if (-not [string]::IsNullOrWhiteSpace($summaryDirectory)) {
        New-Item -ItemType Directory -Path $summaryDirectory -Force | Out-Null
    }

    $output | Set-Content -LiteralPath $SummaryPath -Encoding UTF8
}

Remove-Item Env:PHASE10_TRANSPORT_SQL_CONNECTION_STRING -ErrorAction SilentlyContinue

exit $exitCode
