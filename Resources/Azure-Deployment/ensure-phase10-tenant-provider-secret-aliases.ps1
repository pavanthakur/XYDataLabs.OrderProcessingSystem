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

function Get-KeyVaultSecretValue {
    param([Parameter(Mandatory)][string]$SecretName)

    $value = Invoke-AzText -Arguments @('keyvault', 'secret', 'show', '--vault-name', $keyVaultName, '--name', $SecretName, '--query', 'value')
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }

    return $value
}

function Set-KeyVaultSecretValue {
    param(
        [Parameter(Mandatory)][string]$SecretName,
        [Parameter(Mandatory)][string]$SecretValue
    )

    & az keyvault secret set --vault-name $keyVaultName --name $SecretName --value $SecretValue --only-show-errors 1>$null 2>$null
    return ($LASTEXITCODE -eq 0)
}

$topology = Get-TenantRegistryTopology
$results = New-Object 'System.Collections.Generic.List[object]'
$createdCount = 0
$failures = New-Object 'System.Collections.Generic.List[string]'

foreach ($tenant in $topology.Items) {
    $tenantCode = [string]$tenant.TenantCode
    $providerCode = [string]$tenant.PaymentProviderCode
    $providerAlias = ''
    $providerFallbackSecret = ''
    $action = 'unchanged'
    $detail = 'Alias already present.'

    if ([string]::IsNullOrWhiteSpace($tenantCode)) {
        $failures.Add('Active tenant is missing TenantCode.')
        continue
    }

    if ([string]::IsNullOrWhiteSpace($providerCode)) {
        $failures.Add("Active tenant '$tenantCode' is missing PaymentProviderCode.")
        continue
    }

    if ($supportedProviders -notcontains $providerCode) {
        $failures.Add("Active tenant '$tenantCode' uses unsupported provider '$providerCode'.")
        continue
    }

    $providerAlias = "PaymentProviders--$tenantCode--$providerCode--PrivateKey"
    $existingAlias = Get-KeyVaultSecretValue -SecretName $providerAlias

    if ([string]::IsNullOrWhiteSpace($existingAlias)) {
        $providerFallbackSecret = "$providerCode--PrivateKey"
        $fallbackValue = Get-KeyVaultSecretValue -SecretName $providerFallbackSecret

        if ([string]::IsNullOrWhiteSpace($fallbackValue)) {
            $action = 'failed'
            $detail = "Missing alias '$providerAlias' and fallback secret '$providerFallbackSecret'."
            $failures.Add("Tenant '$tenantCode' provider alias '$providerAlias' could not be created because fallback secret '$providerFallbackSecret' is missing.")
        }
        elseif (-not (Set-KeyVaultSecretValue -SecretName $providerAlias -SecretValue $fallbackValue)) {
            $action = 'failed'
            $detail = "Failed to create alias '$providerAlias' from fallback secret '$providerFallbackSecret'."
            $failures.Add("Tenant '$tenantCode' provider alias '$providerAlias' could not be written to Key Vault.")
        }
        else {
            $action = 'created'
            $detail = "Created alias '$providerAlias' from fallback secret '$providerFallbackSecret'."
            $createdCount++
        }
    }

    $results.Add([pscustomobject]@{
            TenantCode = $tenantCode
            ProviderCode = $providerCode
            ProviderPrivateKeyAlias = $providerAlias
            ProviderFallbackSecret = $providerFallbackSecret
            Action = $action
            Detail = $detail
        })
}

$status = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
$completedUtc = [DateTimeOffset]::UtcNow

$summary = @()
$summary += '## Phase 10 Azure Tenant Provider Secret Alias Sync'
$summary += ''
$summary += "**Status:** $status"
$summary += ('**Environment:** `{0}`' -f $Environment)
$summary += ('**Resource Group:** `{0}`' -f $resourceGroup)
$summary += ('**Gateway App:** `{0}`' -f $gatewayApp)
$summary += ('**Gateway FQDN:** `{0}`' -f $topology.GatewayFqdn)
$summary += ('**Tenant Registry Endpoint:** `{0}`' -f $topology.RegistryUri)
$summary += ('**Key Vault:** `{0}`' -f $keyVaultName)
$summary += ('**Aliases Created:** `{0}`' -f $createdCount)
$summary += ('**Completed UTC:** `{0}`' -f $completedUtc.ToString('O'))
$summary += ''
$summary += '| Tenant | Provider | Alias | Fallback Secret | Action | Detail |'
$summary += '|---|---|---|---|---|---|'
foreach ($result in $results) {
    $fallbackSecret = if ([string]::IsNullOrWhiteSpace($result.ProviderFallbackSecret)) { '-' } else { $result.ProviderFallbackSecret }
    $detail = ([string]$result.Detail).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
    $summary += "| $($result.TenantCode) | $($result.ProviderCode) | $($result.ProviderPrivateKeyAlias) | $fallbackSecret | $($result.Action) | $detail |"
}

if ($failures.Count -eq 0) {
    $summary += ''
    $summary += 'All active tenant/provider private-key aliases are present for the current topology.'
}
else {
    $summary += ''
    $summary += 'One or more tenant/provider aliases could not be created. Fix the fallback provider secrets or Key Vault access before continuing.'
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
                          @{ Name = 'providerCode'; Expression = { $_.ProviderCode } },
                          @{ Name = 'providerPrivateKeyAlias'; Expression = { $_.ProviderPrivateKeyAlias } },
                          @{ Name = 'providerFallbackSecret'; Expression = { $_.ProviderFallbackSecret } },
                          @{ Name = 'action'; Expression = { $_.Action } }
    ) | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
}

if ($failures.Count -gt 0) {
    exit 1
}

exit 0
