param(
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'dev',

    [string]$ResourceGroupName,
    [string]$SummaryPath,
    [string]$BaseName = 'orderprocessing',
    [int]$Attempts = 6,
    [int]$DelaySeconds = 10
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$envSuffix = if ($Environment -eq 'staging') { 'stg' } else { $Environment }
$resourceGroup = if ([string]::IsNullOrWhiteSpace($ResourceGroupName)) { "rg-$BaseName-$envSuffix" } else { $ResourceGroupName }
$gatewayApp = "$BaseName-gate-$envSuffix"
$shortBaseName = $BaseName.Substring(0, [Math]::Min(15, $BaseName.Length))
$keyVaultName = "kv-$shortBaseName-$envSuffix"
$supportedTenantTiers = @('SharedPool', 'Dedicated')
$supportedProviders = @('OpenPay', 'Razorpay')

function Invoke-AzText {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $output = & az @Arguments -o tsv 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    return [string]::Join([Environment]::NewLine, @($output | ForEach-Object { $_.ToString() })).Trim()
}

function Get-GatewayFqdn {
    return Invoke-AzText -Arguments @(
        'containerapp', 'show',
        '--resource-group', $resourceGroup,
        '--name', $gatewayApp,
        '--query', 'properties.configuration.ingress.fqdn'
    )
}

function Get-TenantRegistryTopology {
    $lastError = 'No response.'

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $fqdn = Get-GatewayFqdn
            if ([string]::IsNullOrWhiteSpace($fqdn)) {
                throw "Gateway FQDN for '$gatewayApp' could not be resolved."
            }

            $uri = "https://$fqdn/api/v1/Info/tenant-registry"
            $response = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 60
            $items = @($response)
            if ($items.Count -gt 0) {
                return [pscustomobject]@{
                    GatewayFqdn = $fqdn
                    RegistryUri = $uri
                    Items = $items
                }
            }

            throw 'Tenant registry endpoint returned no active tenants.'
        }
        catch {
            $lastError = $_.Exception.Message
            if ($attempt -lt $Attempts) {
                Write-Host "Tenant topology endpoint not ready yet ($attempt/$Attempts). $lastError"
                Start-Sleep -Seconds $DelaySeconds
            }
        }
    }

    throw "Failed to resolve tenant topology from the runtime after $Attempts attempt(s). $lastError"
}

function Resolve-DedicatedDatabaseNameFromConnectionString {
    param([Parameter(Mandatory)][string]$ConnectionString)

    $match = [regex]::Match($ConnectionString, '(?i)(?:Initial\s+Catalog|Database)\s*=\s*([^;]+)')
    if (-not $match.Success) {
        return $null
    }

    return $match.Groups[1].Value.Trim()
}

function Test-KeyVaultSecretPresence {
    param([Parameter(Mandatory)][string]$SecretName)

    $value = Invoke-AzText -Arguments @('keyvault', 'secret', 'show', '--vault-name', $keyVaultName, '--name', $SecretName, '--query', 'value')
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }

    return $value
}

$topology = Get-TenantRegistryTopology
$results = New-Object 'System.Collections.Generic.List[object]'
$failures = New-Object 'System.Collections.Generic.List[string]'

foreach ($tenant in $topology.Items) {
    $tenantCode = [string]$tenant.TenantCode
    $tenantTier = [string]$tenant.TenantTier
    $providerCode = [string]$tenant.PaymentProviderCode
    $dedicatedSecretName = ''
    $dedicatedDatabaseName = ''
    $providerSecretName = ''
    $detailMessages = New-Object 'System.Collections.Generic.List[string]'
    $passed = $true

    if ([string]::IsNullOrWhiteSpace($tenantCode)) {
        $passed = $false
        $detailMessages.Add('TenantCode is missing.')
    }

    if ($supportedTenantTiers -notcontains $tenantTier) {
        $passed = $false
        $detailMessages.Add("TenantTier '$tenantTier' is not supported by the current topology contract.")
    }

    if ([string]::IsNullOrWhiteSpace($providerCode)) {
        $passed = $false
        $detailMessages.Add('PaymentProviderCode is missing.')
    }
    elseif ($supportedProviders -notcontains $providerCode) {
        $passed = $false
        $detailMessages.Add("PaymentProviderCode '$providerCode' is not part of the supported provider catalog.")
    }

    if (-not [string]::IsNullOrWhiteSpace($tenantCode) -and -not [string]::IsNullOrWhiteSpace($providerCode)) {
        $providerSecretName = "PaymentProviders--$tenantCode--$providerCode--PrivateKey"
        $providerSecretValue = Test-KeyVaultSecretPresence -SecretName $providerSecretName
        if ([string]::IsNullOrWhiteSpace($providerSecretValue)) {
            $passed = $false
            $detailMessages.Add("Missing Key Vault secret '$providerSecretName' for the active tenant/provider mapping.")
        }
    }

    if ($tenantTier -eq 'Dedicated' -and -not [string]::IsNullOrWhiteSpace($tenantCode)) {
        $dedicatedSecretName = "DedicatedTenantConnectionStrings--$tenantCode"
        $dedicatedSecretValue = Test-KeyVaultSecretPresence -SecretName $dedicatedSecretName
        if ([string]::IsNullOrWhiteSpace($dedicatedSecretValue)) {
            $passed = $false
            $detailMessages.Add("Missing dedicated connection secret '$dedicatedSecretName'.")
        }
        else {
            $dedicatedDatabaseName = [string](Resolve-DedicatedDatabaseNameFromConnectionString -ConnectionString $dedicatedSecretValue)
            if ([string]::IsNullOrWhiteSpace($dedicatedDatabaseName)) {
                $passed = $false
                $detailMessages.Add("Secret '$dedicatedSecretName' does not expose an Initial Catalog/Database name.")
            }
        }
    }

    if ($detailMessages.Count -eq 0) {
        $detailMessages.Add('Topology contract satisfied.')
    }

    $detail = [string]::Join(' ', @($detailMessages))
    $results.Add([pscustomobject]@{
            TenantCode = $tenantCode
            Active = $true
            TenantTier = $tenantTier
            PaymentProviderCode = $providerCode
            DedicatedSecretName = $dedicatedSecretName
            DedicatedDatabaseName = $dedicatedDatabaseName
            ProviderSecretName = $providerSecretName
            Passed = $passed
            ContractStatus = if ($passed) { 'validated' } else { 'invalid' }
            Detail = $detail
        })

    if (-not $passed) {
        $failures.Add("$tenantCode :: $detail")
    }
}

$status = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
$completedUtc = [DateTimeOffset]::UtcNow

$summary = @()
$summary += '## Phase 10 Azure Tenant Topology Verification'
$summary += ''
$summary += "**Status:** $status"
$summary += ('**Environment:** `{0}`' -f $Environment)
$summary += ('**Azure Resource Suffix:** `{0}`' -f $envSuffix)
$summary += ('**Resource Group:** `{0}`' -f $resourceGroup)
$summary += ('**Gateway App:** `{0}`' -f $gatewayApp)
$summary += ('**Gateway FQDN:** `{0}`' -f $topology.GatewayFqdn)
$summary += ('**Tenant Registry Endpoint:** `{0}`' -f $topology.RegistryUri)
$summary += ('**Key Vault:** `{0}`' -f $keyVaultName)
$summary += ('**Completed UTC:** `{0}`' -f $completedUtc.ToString('O'))
$summary += ''
$summary += '| Tenant | Tier | Provider | Dedicated DB | Result | Detail |'
$summary += '|---|---|---|---|---|---|'
foreach ($result in $results) {
    $resultText = if ($result.Passed) { 'PASS' } else { 'FAIL' }
    $dbName = if ([string]::IsNullOrWhiteSpace($result.DedicatedDatabaseName)) { '-' } else { $result.DedicatedDatabaseName }
    $detail = ([string]$result.Detail).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
    $summary += "| $($result.TenantCode) | $($result.TenantTier) | $($result.PaymentProviderCode) | $dbName | $resultText | $detail |"
}

if ($failures.Count -eq 0) {
    $summary += ''
    $summary += 'All active tenants resolved from the runtime have a valid tier/provider contract, and dedicated tenants have matching Key Vault connection secrets.'
}
else {
    $summary += ''
    $summary += 'One or more active tenants failed the topology contract. Fix the registry/Key Vault mapping before continuing to smoke, transport, or payment validation.'
}

$summaryText = $summary -join [Environment]::NewLine
Write-Output $summaryText

if (-not [string]::IsNullOrWhiteSpace($SummaryPath)) {
    $summaryDirectory = Split-Path -Parent $SummaryPath
    if (-not [string]::IsNullOrWhiteSpace($summaryDirectory)) {
        New-Item -ItemType Directory -Path $summaryDirectory -Force | Out-Null
    }

    $summaryText | Set-Content -LiteralPath $SummaryPath -Encoding UTF8

    $jsonPath = [System.IO.Path]::ChangeExtension($SummaryPath, '.json')
    @(
        $results |
            Select-Object @{ Name = 'tenantCode'; Expression = { $_.TenantCode } },
                          @{ Name = 'active'; Expression = { $_.Active } },
                          @{ Name = 'tier'; Expression = { $_.TenantTier } },
                          @{ Name = 'providerCode'; Expression = { $_.PaymentProviderCode } },
                          @{ Name = 'dedicatedDatabaseName'; Expression = { $_.DedicatedDatabaseName } },
                          @{ Name = 'dedicatedConnectionSecret'; Expression = { $_.DedicatedSecretName } },
                          @{ Name = 'providerPrivateKeyAlias'; Expression = { $_.ProviderSecretName } },
                          @{ Name = 'contractStatus'; Expression = { $_.ContractStatus } }
    ) | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
}

if ($failures.Count -gt 0) {
    exit 1
}

exit 0
