param(
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'dev',

    [string]$ResourceGroupName,
    [string]$SummaryPath,
    [string]$BaseName = 'orderprocessing',
    [string]$DeploymentPrincipalObjectId,
    [int]$Attempts = 6,
    [int]$DelaySeconds = 10,
    [int]$AccessPolicyAttempts = 6,
    [int]$AccessPolicyDelaySeconds = 10
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'phase10-keyvault-command-helpers.ps1')

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

$topology = Get-TenantRegistryTopology
$results = New-Object 'System.Collections.Generic.List[object]'
$createdCount = 0
$failures = New-Object 'System.Collections.Generic.List[string]'
$accessCheck = [pscustomobject]@{
    Succeeded = $false
    AuthorizationMode = 'unknown'
    ObservedPermissions = @()
    Diagnostic = 'Deployment principal object ID was not provided.'
    Attempts = 0
}

if ([string]::IsNullOrWhiteSpace($DeploymentPrincipalObjectId)) {
    $failures.Add('Deployment principal object ID is required for the Key Vault write-access preflight.')
}
else {
    $accessCheck = Wait-Phase10KeyVaultSecretWriteAccess `
        -KeyVaultName $keyVaultName `
        -ResourceGroupName $resourceGroup `
        -PrincipalObjectId $DeploymentPrincipalObjectId `
        -Attempts $AccessPolicyAttempts `
        -DelaySeconds $AccessPolicyDelaySeconds

    if (-not $accessCheck.Succeeded) {
        $failures.Add("Key Vault write-access preflight failed. $($accessCheck.Diagnostic)")
    }
}

foreach ($tenant in $topology.Items) {
    $tenantCode = [string]$tenant.TenantCode
    $providerCode = [string]$tenant.PaymentProviderCode
    $providerAlias = ''
    $providerFallbackSecret = ''
    $action = 'unchanged'
    $detail = 'Alias already present.'
    $diagnostic = ''
    $attemptsUsed = 0

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

    if (-not $accessCheck.Succeeded) {
        $action = 'blocked'
        $detail = 'Alias synchronization was not attempted because the deployment principal lacks confirmed write access.'
        $diagnostic = $accessCheck.Diagnostic
    }
    else {
        $aliasRead = Get-Phase10KeyVaultSecret -KeyVaultName $keyVaultName -SecretName $providerAlias
        $attemptsUsed += $aliasRead.Attempts
        if ($aliasRead.State -eq 'Error') {
            $action = 'failed'
            $detail = "Failed to read alias '$providerAlias'."
            $diagnostic = $aliasRead.Diagnostic
            $failures.Add("Tenant '$tenantCode' alias read failed. $diagnostic")
        }
        elseif ($aliasRead.State -eq 'Missing') {
        $providerFallbackSecret = "$providerCode--PrivateKey"
            $fallbackRead = Get-Phase10KeyVaultSecret -KeyVaultName $keyVaultName -SecretName $providerFallbackSecret
            $attemptsUsed += $fallbackRead.Attempts

            if ($fallbackRead.State -eq 'Error') {
                $action = 'failed'
                $detail = "Failed to read fallback secret '$providerFallbackSecret'."
                $diagnostic = $fallbackRead.Diagnostic
                $failures.Add("Tenant '$tenantCode' fallback provider secret read failed. $diagnostic")
            }
            elseif ($fallbackRead.State -eq 'Missing') {
            $action = 'failed'
            $detail = "Missing alias '$providerAlias' and fallback secret '$providerFallbackSecret'."
            $failures.Add("Tenant '$tenantCode' provider alias '$providerAlias' could not be created because fallback secret '$providerFallbackSecret' is missing.")
            }
            else {
                $writeResult = Set-Phase10KeyVaultSecret `
                    -KeyVaultName $keyVaultName `
                    -SecretName $providerAlias `
                    -SecretValue $fallbackRead.Value `
                    -SecretValues @($fallbackRead.Value)
                $attemptsUsed += $writeResult.Attempts

                if (-not $writeResult.Succeeded) {
            $action = 'failed'
            $detail = "Failed to create alias '$providerAlias' from fallback secret '$providerFallbackSecret'."
                    $diagnostic = $writeResult.Diagnostic
                    $failures.Add("Tenant '$tenantCode' provider alias '$providerAlias' could not be written to Key Vault. $diagnostic")
                }
                else {
            $action = 'created'
            $detail = "Created alias '$providerAlias' from fallback secret '$providerFallbackSecret'."
            $createdCount++
                }
            }
        }
    }

    $results.Add([pscustomobject]@{
            TenantCode = $tenantCode
            ProviderCode = $providerCode
            ProviderPrivateKeyAlias = $providerAlias
            ProviderFallbackSecret = $providerFallbackSecret
            Action = $action
            Detail = $detail
            Diagnostic = $diagnostic
            Attempts = $attemptsUsed
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
$summary += ('**Deployment Principal Object ID:** `{0}`' -f $(if ([string]::IsNullOrWhiteSpace($DeploymentPrincipalObjectId)) { 'missing' } else { $DeploymentPrincipalObjectId }))
$summary += ('**Authorization Mode:** `{0}`' -f $accessCheck.AuthorizationMode)
$summary += ('**Observed Secret Permissions:** `{0}`' -f $(if (@($accessCheck.ObservedPermissions).Count -eq 0) { 'none' } else { @($accessCheck.ObservedPermissions) -join ', ' }))
$summary += ('**Authorization Attempts:** `{0}`' -f $accessCheck.Attempts)
$summary += ('**Aliases Created:** `{0}`' -f $createdCount)
$summary += ('**Completed UTC:** `{0}`' -f $completedUtc.ToString('O'))
$summary += ''
$summary += '| Tenant | Provider | Alias | Fallback Secret | Action | Attempts | Detail | Azure Diagnostic |'
$summary += '|---|---|---|---|---|---|---|---|'
foreach ($result in $results) {
    $fallbackSecret = if ([string]::IsNullOrWhiteSpace($result.ProviderFallbackSecret)) { '-' } else { $result.ProviderFallbackSecret }
    $detail = ([string]$result.Detail).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
    $diagnostic = if ([string]::IsNullOrWhiteSpace([string]$result.Diagnostic)) { '-' } else { ([string]$result.Diagnostic).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ') }
    $summary += "| $($result.TenantCode) | $($result.ProviderCode) | $($result.ProviderPrivateKeyAlias) | $fallbackSecret | $($result.Action) | $($result.Attempts) | $detail | $diagnostic |"
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
    [pscustomobject]@{
        status = $status
        environment = $Environment
        resourceGroup = $resourceGroup
        gatewayFqdn = $topology.GatewayFqdn
        registryUri = $topology.RegistryUri
        keyVault = $keyVaultName
        deploymentPrincipalObjectId = $DeploymentPrincipalObjectId
        authorizationMode = $accessCheck.AuthorizationMode
        observedSecretPermissions = @($accessCheck.ObservedPermissions)
        results = @($results | Select-Object `
                @{ Name = 'tenantCode'; Expression = { $_.TenantCode } },
                @{ Name = 'providerCode'; Expression = { $_.ProviderCode } },
                @{ Name = 'providerPrivateKeyAlias'; Expression = { $_.ProviderPrivateKeyAlias } },
                @{ Name = 'providerFallbackSecret'; Expression = { $_.ProviderFallbackSecret } },
                @{ Name = 'action'; Expression = { $_.Action } },
                @{ Name = 'attempts'; Expression = { $_.Attempts } },
                @{ Name = 'detail'; Expression = { $_.Detail } },
                @{ Name = 'diagnostic'; Expression = { $_.Diagnostic } })
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
}

if ($failures.Count -gt 0) {
    exit 1
}

exit 0
