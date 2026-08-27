param(
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'dev',

    [string]$ResourceGroupName,

    [string]$GatewayBaseUrl,
    [string]$SummaryPath,
    [string]$BaseName = 'orderprocessing',
    [ValidateSet('OpenPay', 'Razorpay')]
    [string[]]$RequiredProviderCodes = @(),
    [int]$Attempts = 6,
    [int]$DelaySeconds = 10
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot '../Resources/Azure-Deployment/phase10-keyvault-command-helpers.ps1')

$envSuffix = if ($Environment -eq 'staging') { 'stg' } else { $Environment }
$resourceGroup = if ([string]::IsNullOrWhiteSpace($ResourceGroupName)) { "rg-$BaseName-$envSuffix" } else { $ResourceGroupName }
$gatewayApp = "$BaseName-gate-$envSuffix"
$shortBaseName = $BaseName.Substring(0, [Math]::Min(15, $BaseName.Length))
$keyVaultName = "kv-$shortBaseName-$envSuffix"
$supportedTenantTiers = @('SharedPool', 'Dedicated')
$supportedProviders = @('OpenPay', 'Razorpay')
$requiredExecutionProviderCodes = @(
    $RequiredProviderCodes |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique
)

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

function Get-GatewayUri {
    if (-not [string]::IsNullOrWhiteSpace($GatewayBaseUrl)) {
        $normalizedGatewayBaseUrl = $GatewayBaseUrl.Trim().TrimEnd('/')
        return [pscustomobject]@{
            Fqdn = ([System.Uri]$normalizedGatewayBaseUrl).Host
            BaseUrl = $normalizedGatewayBaseUrl
            Source = 'runtime-targets'
        }
    }

    $fqdn = Invoke-AzText -Arguments @(
        'containerapp', 'show',
        '--resource-group', $resourceGroup,
        '--name', $gatewayApp,
        '--query', 'properties.configuration.ingress.fqdn'
    )

    if ([string]::IsNullOrWhiteSpace($fqdn)) {
        return $null
    }

    return [pscustomobject]@{
        Fqdn = $fqdn
        BaseUrl = "https://$fqdn"
        Source = 'azure-containerapp'
    }
}

function Get-TenantRegistryTopology {
    $lastError = 'No response.'

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $gatewayUri = Get-GatewayUri
            if ($null -eq $gatewayUri -or [string]::IsNullOrWhiteSpace($gatewayUri.BaseUrl)) {
                throw "Gateway endpoint could not be resolved from runtime-targets.json or Azure Container Apps for '$gatewayApp'."
            }

            $uri = "$($gatewayUri.BaseUrl)/api/v1/Info/tenant-registry"
            $response = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 60
            $items = @($response)
            if ($items.Count -gt 0) {
                return [pscustomobject]@{
                    GatewayFqdn = $gatewayUri.Fqdn
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
    $validatedProviderSecretNames = New-Object 'System.Collections.Generic.List[string]'
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
    }

    if (-not [string]::IsNullOrWhiteSpace($tenantCode)) {
        $providerCodesToValidate = @(
            @($providerCode) + $requiredExecutionProviderCodes |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Select-Object -Unique
        )

        foreach ($providerCodeToValidate in $providerCodesToValidate) {
            if ($supportedProviders -notcontains $providerCodeToValidate) {
                $passed = $false
                $detailMessages.Add("Required execution provider '$providerCodeToValidate' is not part of the supported provider catalog.")
                continue
            }

            $executionProviderSecretName = "PaymentProviders--$tenantCode--$providerCodeToValidate--PrivateKey"
            $validatedProviderSecretNames.Add($executionProviderSecretName)
            $providerSecretRead = Get-Phase10KeyVaultSecret -KeyVaultName $keyVaultName -SecretName $executionProviderSecretName
            if ($providerSecretRead.State -eq 'Error') {
                $passed = $false
                $detailMessages.Add("Unable to validate Key Vault secret '$executionProviderSecretName'. $($providerSecretRead.Diagnostic)")
            }
            elseif ($providerSecretRead.State -eq 'Missing') {
                $passed = $false
                $contractPurpose = if ($providerCodeToValidate -eq $providerCode) { 'active tenant/provider mapping' } else { 'requested matrix execution path' }
                $detailMessages.Add("Missing Key Vault secret '$executionProviderSecretName' for the $contractPurpose.")
            }
        }
    }

    if ($tenantTier -eq 'Dedicated' -and -not [string]::IsNullOrWhiteSpace($tenantCode)) {
        $dedicatedSecretName = "DedicatedTenantConnectionStrings--$tenantCode"
        $dedicatedSecretRead = Get-Phase10KeyVaultSecret -KeyVaultName $keyVaultName -SecretName $dedicatedSecretName
        if ($dedicatedSecretRead.State -eq 'Error') {
            $passed = $false
            $detailMessages.Add("Unable to validate dedicated connection secret '$dedicatedSecretName'. $($dedicatedSecretRead.Diagnostic)")
        }
        elseif ($dedicatedSecretRead.State -eq 'Missing') {
            $passed = $false
            $detailMessages.Add("Missing dedicated connection secret '$dedicatedSecretName'.")
        }
        else {
            $dedicatedDatabaseName = [string](Resolve-DedicatedDatabaseNameFromConnectionString -ConnectionString $dedicatedSecretRead.Value)
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
            ValidatedProviderSecretNames = @($validatedProviderSecretNames)
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
$summary += ('**Required Matrix Providers:** `{0}`' -f $(if ($requiredExecutionProviderCodes.Count -eq 0) { 'registry assignments only' } else { $requiredExecutionProviderCodes -join ', ' }))
$summary += ('**Completed UTC:** `{0}`' -f $completedUtc.ToString('O'))
$summary += ''
$summary += '| Tenant | Tier | Assigned Provider | Validated Provider Aliases | Dedicated DB | Result | Detail |'
$summary += '|---|---|---|---|---|---|---|'
foreach ($result in $results) {
    $resultText = if ($result.Passed) { 'PASS' } else { 'FAIL' }
    $dbName = if ([string]::IsNullOrWhiteSpace($result.DedicatedDatabaseName)) { '-' } else { $result.DedicatedDatabaseName }
    $providerAliases = if (@($result.ValidatedProviderSecretNames).Count -eq 0) { '-' } else { @($result.ValidatedProviderSecretNames) -join ', ' }
    $detail = ([string]$result.Detail).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
    $summary += "| $($result.TenantCode) | $($result.TenantTier) | $($result.PaymentProviderCode) | $providerAliases | $dbName | $resultText | $detail |"
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
                          @{ Name = 'validatedProviderPrivateKeyAliases'; Expression = { @($_.ValidatedProviderSecretNames) } },
                          @{ Name = 'contractStatus'; Expression = { $_.ContractStatus } }
    ) | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
}

if ($failures.Count -gt 0) {
    exit 1
}

exit 0
