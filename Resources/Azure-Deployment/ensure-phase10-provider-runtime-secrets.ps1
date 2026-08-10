param(
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'dev',

    [string]$ResourceGroupName,
    [string]$SummaryPath,
    [string]$BaseName = 'orderprocessing',

    [string]$OpenPayMerchantId,
    [string]$OpenPayPublicKey,
    [string]$OpenPayPrivateKey,
    [string]$OpenPayDeviceSessionId,
    [string]$OpenPayWebhookSecret,
    [string]$RazorpayMerchantId,
    [string]$RazorpayPrivateKey,
    [string]$RazorpayWebhookSecret
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$envSuffix = if ($Environment -eq 'staging') { 'stg' } else { $Environment }
$resourceGroup = if ([string]::IsNullOrWhiteSpace($ResourceGroupName)) { "rg-$BaseName-$envSuffix" } else { $ResourceGroupName }
$shortBaseName = $BaseName.Substring(0, [Math]::Min(15, $BaseName.Length))
$keyVaultName = "kv-$shortBaseName-$envSuffix"

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

$secretMap = [ordered]@{
    'OpenPay--MerchantId' = $OpenPayMerchantId
    'OpenPay--PublicKey' = $OpenPayPublicKey
    'OpenPay--PrivateKey' = $OpenPayPrivateKey
    'OpenPay--DeviceSessionId' = $OpenPayDeviceSessionId
    'Razorpay--MerchantId' = $RazorpayMerchantId
    'Razorpay--PrivateKey' = $RazorpayPrivateKey
    'Webhooks--OpenPay--Secret' = $OpenPayWebhookSecret
    'Webhooks--Razorpay--Secret' = $RazorpayWebhookSecret
}

$missingInputs = New-Object 'System.Collections.Generic.List[string]'
foreach ($entry in $secretMap.GetEnumerator()) {
    if ([string]::IsNullOrWhiteSpace([string]$entry.Value)) {
        $missingInputs.Add($entry.Key)
    }
}

$results = New-Object 'System.Collections.Generic.List[object]'
$failures = New-Object 'System.Collections.Generic.List[string]'
$updatedCount = 0
$createdCount = 0

if ($missingInputs.Count -gt 0) {
    foreach ($secretName in $missingInputs) {
        $failures.Add("Required GitHub environment secret backing '$secretName' was not provided to the workflow.")
    }
}
else {
    foreach ($entry in $secretMap.GetEnumerator()) {
        $secretName = [string]$entry.Key
        $desiredValue = [string]$entry.Value
        $existingValue = Get-KeyVaultSecretValue -SecretName $secretName
        $action = 'unchanged'
        $detail = 'Secret already matched the GitHub environment source.'

        if ([string]::IsNullOrWhiteSpace($existingValue)) {
            if (-not (Set-KeyVaultSecretValue -SecretName $secretName -SecretValue $desiredValue)) {
                $action = 'failed'
                $detail = "Failed to create '$secretName' in Key Vault."
                $failures.Add($detail)
            }
            else {
                $action = 'created'
                $detail = "Created '$secretName' in Key Vault from the GitHub environment secret."
                $createdCount++
            }
        }
        elseif ($existingValue -ne $desiredValue) {
            if (-not (Set-KeyVaultSecretValue -SecretName $secretName -SecretValue $desiredValue)) {
                $action = 'failed'
                $detail = "Failed to update '$secretName' in Key Vault."
                $failures.Add($detail)
            }
            else {
                $action = 'updated'
                $detail = "Updated '$secretName' in Key Vault to match the GitHub environment secret."
                $updatedCount++
            }
        }

        $results.Add([pscustomobject]@{
                SecretName = $secretName
                Action = $action
                Detail = $detail
            })
    }
}

$status = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
$completedUtc = [DateTimeOffset]::UtcNow

$summary = @()
$summary += '## Phase 10 Azure Provider Runtime Secret Sync'
$summary += ''
$summary += "**Status:** $status"
$summary += ('**Environment:** `{0}`' -f $Environment)
$summary += ('**Resource Group:** `{0}`' -f $resourceGroup)
$summary += ('**Key Vault:** `{0}`' -f $keyVaultName)
$summary += ('**Secrets Created:** `{0}`' -f $createdCount)
$summary += ('**Secrets Updated:** `{0}`' -f $updatedCount)
$summary += ('**Completed UTC:** `{0}`' -f $completedUtc.ToString('O'))
$summary += ''
$summary += '| Secret | Action | Detail |'
$summary += '|---|---|---|'

if ($results.Count -gt 0) {
    foreach ($result in $results) {
        $detail = ([string]$result.Detail).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
        $summary += "| $($result.SecretName) | $($result.Action) | $detail |"
    }
}
else {
    foreach ($failure in $failures) {
        $detail = ([string]$failure).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
        $summary += "| - | failed | $detail |"
    }
}

if ($failures.Count -eq 0) {
    $summary += ''
    $summary += 'All required provider runtime secrets are present in Key Vault and aligned with the GitHub environment source.'
}
else {
    $summary += ''
    $summary += 'Provider runtime secret sync failed. Fix the missing GitHub environment secrets or Key Vault write access before continuing.'
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
            Select-Object @{ Name = 'secretName'; Expression = { $_.SecretName } },
                          @{ Name = 'action'; Expression = { $_.Action } }
    ) | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
}

if ($failures.Count -gt 0) {
    exit 1
}

exit 0
