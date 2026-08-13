param(
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'dev',

    [string]$ResourceGroupName,
    [string]$SummaryPath,
    [string]$BaseName = 'orderprocessing',
    [string]$DeploymentPrincipalObjectId,
    [int]$AccessPolicyAttempts = 6,
    [int]$AccessPolicyDelaySeconds = 10,

    [string]$OpenPayMerchantId,
    [string]$OpenPayPublicKey,
    [string]$OpenPayPrivateKey,
    [string]$OpenPayDeviceSessionId,
    [string]$OpenPayWebhookSecret,
    [string]$OpenPayRedirectUrl,
    [string]$RazorpayMerchantId,
    [string]$RazorpayPrivateKey,
    [string]$RazorpayWebhookSecret
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'phase10-keyvault-command-helpers.ps1')

$envSuffix = if ($Environment -eq 'staging') { 'stg' } else { $Environment }
$resourceGroup = if ([string]::IsNullOrWhiteSpace($ResourceGroupName)) { "rg-$BaseName-$envSuffix" } else { $ResourceGroupName }
$shortBaseName = $BaseName.Substring(0, [Math]::Min(15, $BaseName.Length))
$keyVaultName = "kv-$shortBaseName-$envSuffix"

$secretMap = [ordered]@{
    'OpenPay--MerchantId' = $OpenPayMerchantId
    'OpenPay--PublicKey' = $OpenPayPublicKey
    'OpenPay--PrivateKey' = $OpenPayPrivateKey
    'OpenPay--DeviceSessionId' = $OpenPayDeviceSessionId
    'OpenPay--RedirectUrl' = $OpenPayRedirectUrl
    'Razorpay--MerchantId' = $RazorpayMerchantId
    'Razorpay--PrivateKey' = $RazorpayPrivateKey
    'Webhooks--OpenPay--Secret' = $OpenPayWebhookSecret
    'Webhooks--Razorpay--Secret' = $RazorpayWebhookSecret
}
$secretValues = @($secretMap.Values | ForEach-Object { [string]$_ })

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
$accessCheck = [pscustomobject]@{
    Succeeded = $false
    AuthorizationMode = 'unknown'
    ObservedPermissions = @()
    Diagnostic = 'Deployment principal object ID was not provided.'
    Attempts = 0
}

if ($missingInputs.Count -gt 0) {
    foreach ($secretName in $missingInputs) {
        $failures.Add("Required GitHub environment secret backing '$secretName' was not provided to the workflow.")
    }
}
elseif ([string]::IsNullOrWhiteSpace($DeploymentPrincipalObjectId)) {
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
        foreach ($secretName in $secretMap.Keys) {
            $results.Add([pscustomobject]@{
                    SecretName = $secretName
                    Action = 'blocked'
                    Detail = 'Secret synchronization was not attempted because the deployment principal lacks confirmed write access.'
                    Diagnostic = $accessCheck.Diagnostic
                    Attempts = 0
                })
        }
    }
}

if ($failures.Count -eq 0) {
    foreach ($entry in $secretMap.GetEnumerator()) {
        $secretName = [string]$entry.Key
        $desiredValue = [string]$entry.Value
        $readResult = Get-Phase10KeyVaultSecret `
            -KeyVaultName $keyVaultName `
            -SecretName $secretName `
            -SecretValues $secretValues
        $action = 'unchanged'
        $detail = 'Secret already matched the GitHub environment source.'
        $diagnostic = ''
        $attemptsUsed = $readResult.Attempts

        if ($readResult.State -eq 'Error') {
            $action = 'failed'
            $detail = "Failed to read '$secretName' before synchronization."
            $diagnostic = $readResult.Diagnostic
            $failures.Add("$detail $diagnostic")
        }
        elseif ($readResult.State -eq 'Missing') {
            $writeResult = Set-Phase10KeyVaultSecret `
                -KeyVaultName $keyVaultName `
                -SecretName $secretName `
                -SecretValue $desiredValue `
                -SecretValues $secretValues
            $attemptsUsed += $writeResult.Attempts

            if (-not $writeResult.Succeeded) {
                $action = 'failed'
                $detail = "Failed to create '$secretName' in Key Vault."
                $diagnostic = $writeResult.Diagnostic
                $failures.Add("$detail $diagnostic")
            }
            else {
                $action = 'created'
                $detail = "Created '$secretName' in Key Vault from the GitHub environment secret."
                $createdCount++
            }
        }
        elseif ($readResult.Value -ne $desiredValue) {
            $writeResult = Set-Phase10KeyVaultSecret `
                -KeyVaultName $keyVaultName `
                -SecretName $secretName `
                -SecretValue $desiredValue `
                -SecretValues $secretValues
            $attemptsUsed += $writeResult.Attempts

            if (-not $writeResult.Succeeded) {
                $action = 'failed'
                $detail = "Failed to update '$secretName' in Key Vault."
                $diagnostic = $writeResult.Diagnostic
                $failures.Add("$detail $diagnostic")
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
                Diagnostic = $diagnostic
                Attempts = $attemptsUsed
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
$summary += ('**Deployment Principal Object ID:** `{0}`' -f $(if ([string]::IsNullOrWhiteSpace($DeploymentPrincipalObjectId)) { 'missing' } else { $DeploymentPrincipalObjectId }))
$summary += ('**Authorization Mode:** `{0}`' -f $accessCheck.AuthorizationMode)
$summary += ('**Observed Secret Permissions:** `{0}`' -f $(if (@($accessCheck.ObservedPermissions).Count -eq 0) { 'none' } else { @($accessCheck.ObservedPermissions) -join ', ' }))
$summary += ('**Authorization Attempts:** `{0}`' -f $accessCheck.Attempts)
$summary += ('**Secrets Created:** `{0}`' -f $createdCount)
$summary += ('**Secrets Updated:** `{0}`' -f $updatedCount)
$summary += ('**Completed UTC:** `{0}`' -f $completedUtc.ToString('O'))
$summary += ''
$summary += '| Secret | Action | Attempts | Detail | Azure Diagnostic |'
$summary += '|---|---|---|---|---|'

if ($results.Count -gt 0) {
    foreach ($result in $results) {
        $detail = ([string]$result.Detail).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
        $diagnostic = if ([string]::IsNullOrWhiteSpace([string]$result.Diagnostic)) { '-' } else { ([string]$result.Diagnostic).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ') }
        $summary += "| $($result.SecretName) | $($result.Action) | $($result.Attempts) | $detail | $diagnostic |"
    }
}
else {
    foreach ($failure in $failures) {
        $detail = ([string]$failure).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
        $summary += "| - | failed | 0 | $detail | - |"
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
    [pscustomobject]@{
        status = $status
        environment = $Environment
        resourceGroup = $resourceGroup
        keyVault = $keyVaultName
        deploymentPrincipalObjectId = $DeploymentPrincipalObjectId
        authorizationMode = $accessCheck.AuthorizationMode
        observedSecretPermissions = @($accessCheck.ObservedPermissions)
        results = @($results | Select-Object `
                @{ Name = 'secretName'; Expression = { $_.SecretName } },
                @{ Name = 'action'; Expression = { $_.Action } },
                @{ Name = 'attempts'; Expression = { $_.Attempts } },
                @{ Name = 'detail'; Expression = { $_.Detail } },
                @{ Name = 'diagnostic'; Expression = { $_.Diagnostic } })
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
}

if ($failures.Count -gt 0) {
    exit 1
}

exit 0
