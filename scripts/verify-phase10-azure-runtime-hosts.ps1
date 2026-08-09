param(
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'dev',

    [string]$ResourceGroupName,
    [string]$SummaryPath,
    [int]$Attempts = 12,
    [int]$DelaySeconds = 10
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$envSuffix = if ($Environment -eq 'staging') { 'stg' } else { $Environment }
$resourceGroup = if ([string]::IsNullOrWhiteSpace($ResourceGroupName)) { "rg-orderprocessing-$envSuffix" } else { $ResourceGroupName }

function Invoke-AzJson {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $output = & az @Arguments -o json 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($output)) {
        return $null
    }

    return $output | ConvertFrom-Json
}

function Get-NestedValue {
    param(
        [AllowNull()]
        [object]$Object,
        [Parameter(Mandatory)]
        [string[]]$Path
    )

    $current = $Object
    foreach ($segment in $Path) {
        if ($null -eq $current) { return $null }

        $property = $current.PSObject.Properties[$segment]
        if ($null -eq $property) { return $null }
        $current = $property.Value
    }

    return $current
}

function ConvertTo-Array {
    param(
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return @()
    }

    if ($InputObject -is [string]) {
        return @($InputObject)
    }

    if ($InputObject -is [System.Collections.IEnumerable]) {
        return @($InputObject)
    }

    return @($InputObject)
}

function Test-ContainerAppHost {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $lastDetail = 'No response from Azure CLI.'

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $app = Invoke-AzJson -Arguments @('containerapp', 'show', '--resource-group', $resourceGroup, '--name', $Name)
        if ($null -eq $app) {
            $lastDetail = "Azure could not resolve Container App '$Name'."
        }
        else {
            $latestRevisionName = [string](Get-NestedValue -Object $app -Path @('properties', 'latestRevisionName'))
            $provisioningState = [string](Get-NestedValue -Object $app -Path @('properties', 'provisioningState'))
            $runningStatus = [string](Get-NestedValue -Object $app -Path @('properties', 'runningStatus'))
            $fqdn = [string](Get-NestedValue -Object $app -Path @('properties', 'configuration', 'ingress', 'fqdn'))

            $revisions = Invoke-AzJson -Arguments @('containerapp', 'revision', 'list', '--resource-group', $resourceGroup, '--name', $Name)
            $revisionList = ConvertTo-Array -InputObject $revisions
            $latestRevision = $null
            if ($revisionList.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($latestRevisionName)) {
                $latestRevision = @($revisionList | Where-Object { $_.name -eq $latestRevisionName }) | Select-Object -First 1
            }

            $revisionRunningState = [string](Get-NestedValue -Object $latestRevision -Path @('properties', 'runningState'))
            if ([string]::IsNullOrWhiteSpace($revisionRunningState)) {
                $revisionRunningState = [string](Get-NestedValue -Object $latestRevision -Path @('runningState'))
            }

            $revisionHealthState = [string](Get-NestedValue -Object $latestRevision -Path @('properties', 'healthState'))
            if ([string]::IsNullOrWhiteSpace($revisionHealthState)) {
                $revisionHealthState = [string](Get-NestedValue -Object $latestRevision -Path @('healthState'))
            }

            $active = Get-NestedValue -Object $latestRevision -Path @('properties', 'active')
            if ($null -eq $active) {
                $active = Get-NestedValue -Object $latestRevision -Path @('active')
            }

            $checks = @()
            if (-not [string]::IsNullOrWhiteSpace($provisioningState)) {
                $checks += ($provisioningState -eq 'Succeeded')
            }
            if (-not [string]::IsNullOrWhiteSpace($runningStatus)) {
                $checks += ($runningStatus -eq 'Running')
            }
            $checks += (-not [string]::IsNullOrWhiteSpace($latestRevisionName))
            $checks += ($null -ne $latestRevision)
            if (-not [string]::IsNullOrWhiteSpace($revisionRunningState)) {
                $checks += ($revisionRunningState -eq 'Running')
            }
            if (-not [string]::IsNullOrWhiteSpace($revisionHealthState)) {
                $checks += ($revisionHealthState -eq 'Healthy')
            }
            if ($null -ne $active) {
                $checks += ([bool]$active)
            }
            $checks += (-not [string]::IsNullOrWhiteSpace($fqdn))

            $allPassed = $true
            foreach ($check in $checks) {
                if (-not $check) {
                    $allPassed = $false
                    break
                }
            }

            $detailParts = @(
                "provisioningState=$([string]::IsNullOrWhiteSpace($provisioningState) ? 'n/a' : $provisioningState)",
                "runningStatus=$([string]::IsNullOrWhiteSpace($runningStatus) ? 'n/a' : $runningStatus)",
                "latestRevision=$([string]::IsNullOrWhiteSpace($latestRevisionName) ? 'n/a' : $latestRevisionName)",
                "revisions=$($revisionList.Count)",
                "revisionRunning=$([string]::IsNullOrWhiteSpace($revisionRunningState) ? 'n/a' : $revisionRunningState)",
                "revisionHealth=$([string]::IsNullOrWhiteSpace($revisionHealthState) ? 'n/a' : $revisionHealthState)",
                "active=$([string]::IsNullOrWhiteSpace([string]$active) ? 'n/a' : [string]$active)",
                "fqdn=$([string]::IsNullOrWhiteSpace($fqdn) ? 'n/a' : $fqdn)"
            )
            $lastDetail = $detailParts -join '; '

            if ($allPassed) {
                return [pscustomobject]@{
                    Name = $Name
                    Kind = 'ContainerApp'
                    Passed = $true
                    Detail = $lastDetail
                }
            }
        }

        if ($attempt -lt $Attempts) {
            Write-Host "Container App '$Name' not ready yet ($attempt/$Attempts). $lastDetail"
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    return [pscustomobject]@{
        Name = $Name
        Kind = 'ContainerApp'
        Passed = $false
        Detail = $lastDetail
    }
}

function Test-FunctionAppHost {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $lastDetail = 'No response from Azure CLI.'

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $app = Invoke-AzJson -Arguments @('functionapp', 'show', '--resource-group', $resourceGroup, '--name', $Name)
        if ($null -eq $app) {
            $lastDetail = "Azure could not resolve Function App '$Name'."
        }
        else {
            $state = [string](Get-NestedValue -Object $app -Path @('state'))
            $enabledHostNames = @(Get-NestedValue -Object $app -Path @('enabledHostNames'))
            $defaultHostName = [string](Get-NestedValue -Object $app -Path @('defaultHostName'))

            $passed = ($state -eq 'Running') -and (-not [string]::IsNullOrWhiteSpace($defaultHostName)) -and ($enabledHostNames.Count -gt 0)
            $lastDetail = "state=$state; defaultHostName=$defaultHostName; enabledHostNames=$($enabledHostNames.Count)"

            if ($passed) {
                return [pscustomobject]@{
                    Name = $Name
                    Kind = 'FunctionApp'
                    Passed = $true
                    Detail = $lastDetail
                }
            }
        }

        if ($attempt -lt $Attempts) {
            Write-Host "Function App '$Name' not ready yet ($attempt/$Attempts). $lastDetail"
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    return [pscustomobject]@{
        Name = $Name
        Kind = 'FunctionApp'
        Passed = $false
        Detail = $lastDetail
    }
}

$containerApps = @(
    "orderprocessing-gate-$envSuffix",
    "orderprocessing-ord-$envSuffix",
    "orderprocessing-pay-$envSuffix",
    "orderprocessing-inv-$envSuffix",
    "orderprocessing-notif-$envSuffix",
    "orderprocessing-ui-$envSuffix"
)
$functionApp = "orderprocessing-functions-$envSuffix"

Write-Host "Verifying Phase 10 Azure runtime hosts for '$Environment' in '$resourceGroup'..."

$results = @()
foreach ($containerApp in $containerApps) {
    $results += Test-ContainerAppHost -Name $containerApp
}
$results += Test-FunctionAppHost -Name $functionApp

$failed = @($results | Where-Object { -not $_.Passed })
$status = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }
$startedUtc = [DateTimeOffset]::UtcNow.AddSeconds(-1 * $Attempts * $DelaySeconds)
$completedUtc = [DateTimeOffset]::UtcNow

$summary = @()
$summary += '## Phase 10 Azure Runtime Host Verification'
$summary += ''
$summary += "**Status:** $status"
$summary += ('**Environment:** `{0}`' -f $Environment)
$summary += ('**Azure Resource Suffix:** `{0}`' -f $envSuffix)
$summary += ('**Resource Group:** `{0}`' -f $resourceGroup)
$summary += ('**Completed UTC:** `{0}`' -f $completedUtc.ToString('O'))
$summary += ''
$summary += '| Host | Kind | Result | Detail |'
$summary += '|---|---|---|---|'
foreach ($result in $results) {
    $resultText = if ($result.Passed) { 'PASS' } else { 'FAIL' }
    $detail = ([string]$result.Detail).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
    $summary += "| $($result.Name) | $($result.Kind) | $resultText | $detail |"
}

if ($failed.Count -eq 0) {
    $summary += ''
    $summary += 'All required Phase 10 runtime hosts are present and reported healthy/running by Azure control-plane checks.'
}
else {
    $summary += ''
    $summary += 'One or more runtime hosts are not healthy. Inspect the failing host revision, replicas, and log stream in Azure Portal before continuing.'
}

$summaryText = $summary -join [Environment]::NewLine
Write-Output $summaryText

if (-not [string]::IsNullOrWhiteSpace($SummaryPath)) {
    $summaryDirectory = Split-Path -Parent $SummaryPath
    if (-not [string]::IsNullOrWhiteSpace($summaryDirectory)) {
        New-Item -ItemType Directory -Path $summaryDirectory -Force | Out-Null
    }

    $summaryText | Set-Content -LiteralPath $SummaryPath -Encoding UTF8
}

if ($failed.Count -gt 0) {
    exit 1
}

exit 0
