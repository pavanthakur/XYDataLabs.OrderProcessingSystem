#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][ValidateSet('Pause', 'Route', 'Restore', 'RestoreSafe')][string]$Action,
    [switch]$LibraryOnly,
    [string]$ExpectedSubscriptionId,
    [guid]$ReplayRequestId = [guid]::Empty,
    [string]$ManifestPath,
    [string]$ReportPath,
    [string]$PreflightReportPath,
    [string]$ReplayCompletionEvidencePath,
    [switch]$Execute,
    [string]$ConfirmMutation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'phase10-azure-replay-drill-common.ps1')

function Get-DrillConfigState {
    param([Parameter(Mandatory)][object]$ContainerApp)
    $env = @($ContainerApp.properties.template.containers[0].env)
    $enabled = @(Get-ReplayDrillEnvironmentValue $env 'ServiceBus__ReplayEnabled')
    $queue = @(Get-ReplayDrillEnvironmentValue $env 'ServiceBus__ReplayRequestQueueName')
    $request = @(Get-ReplayDrillEnvironmentValue $env 'ServiceBus__ReplayRequestId')
    if ($enabled.Count -ne 1 -or $queue.Count -ne 1 -or $request.Count -gt 1) {
        throw 'Publisher settings are missing or duplicated; refusing to mutate runtime configuration.'
    }
    return [ordered]@{
        enabled = $enabled[0].value
        queue = $queue[0].value
        requestId = if ($request.Count -eq 0) { '' } else { [string]$request[0].value }
        revision = [string]$ContainerApp.properties.latestReadyRevisionName
        latestRevision = [string]$ContainerApp.properties.latestRevisionName
        runningStatus = [string]$ContainerApp.properties.runningStatus
        image = [string]$ContainerApp.properties.template.containers[0].image
    }
}

function Test-DrillConfigStateEquals {
    param([System.Collections.IDictionary]$Actual, [System.Collections.IDictionary]$Expected)
    return ([string]$Actual.enabled -eq [string]$Expected.enabled -and
        [string]$Actual.queue -eq [string]$Expected.queue -and
        [string]$Actual.requestId -eq [string]$Expected.requestId)
}

function Get-DrillConfigMutationArguments {
    param([Parameter(Mandatory)][string]$AppName, [Parameter(Mandatory)][System.Collections.IDictionary]$State)
    $set = @(
        "ServiceBus__ReplayEnabled=$($State.enabled)",
        "ServiceBus__ReplayRequestQueueName=$($State.queue)"
    )
    if (-not [string]::IsNullOrWhiteSpace([string]$State.requestId)) {
        $set += "ServiceBus__ReplayRequestId=$($State.requestId)"
        return [pscustomobject]@{ appName = $AppName; setEnvVars = $set; removeEnvVars = @() }
    }
    return [pscustomobject]@{ appName = $AppName; setEnvVars = $set; removeEnvVars = @('ServiceBus__ReplayRequestId') }
}

function Wait-DrillConfigState {
    param(
        [Parameter(Mandatory)][string]$AppName,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Expected,
        [Parameter(Mandatory)][string]$ExpectedImage,
        [Parameter(Mandatory)][string]$ExpectedRevision,
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroup
    )
    for ($attempt = 1; $attempt -le 24; $attempt++) {
        $json = & az containerapp show --subscription $SubscriptionId --resource-group $ResourceGroup --name $AppName -o json 2>$null
        if ($LASTEXITCODE -eq 0) {
            $app = $json | ConvertFrom-Json
            $state = Get-DrillConfigState $app
            if ((Test-DrillConfigStateEquals $state $Expected) -and
                $state.runningStatus -eq 'Running' -and
                $state.latestRevision -eq $state.revision -and
                $state.revision -eq $ExpectedRevision -and
                $state.image -ceq $ExpectedImage -and
                $state.image -match '@sha256:[a-f0-9]{64}$') { return $state }
        }
        Start-Sleep -Seconds 5
    }
    throw "Publisher '$AppName' did not converge to the requested state/readiness within 120 seconds."
}

function Resolve-DrillEvidencePath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label,
        [string]$RepositoryRoot = $repoRoot
    )
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { throw 'Repository root is required to resolve replay evidence safely.' }
    $full = [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $RepositoryRoot $Path }))
    $testResultsRoot = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'TestResults'))
    $allowed = $testResultsRoot + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw "$Label must be under project TestResults." }

    $relative = [IO.Path]::GetRelativePath($testResultsRoot, $full)
    $candidates = [System.Collections.Generic.List[string]]::new()
    $candidates.Add($testResultsRoot)
    $cursor = $testResultsRoot
    foreach ($segment in $relative.Split([IO.Path]::DirectorySeparatorChar, [StringSplitOptions]::RemoveEmptyEntries)) {
        $cursor = Join-Path $cursor $segment
        $candidates.Add($cursor)
    }
    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate)) { continue }
        $item = Get-Item -LiteralPath $candidate -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$Label cannot pass through a symbolic link or reparse point under TestResults."
        }
    }
    return $full
}

function Assert-ReplayCompletionEvidence {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Evidence,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Manifest,
        [Parameter(Mandatory)][string]$SubscriptionId
    )
    if ($Evidence.status -ne 'PASS' -or
        $Evidence.environment -ne 'dev' -or
        $Evidence.subscriptionId -ne $SubscriptionId -or
        $Evidence.replayRequestId -ne $Manifest.replayRequestId -or
        $Evidence.publisherCheckpointed -ne $true -or
        $Evidence.pendingReplayRequestCount -ne 0) {
        throw 'Completion evidence must prove the selected request checkpointed and no replay requests remain pending; use RestoreSafe if the drill failed.'
    }
}

if ($LibraryOnly) { return }
if ($Execute -and $ConfirmMutation -cne 'MUTATE AZURE DEV REPLAY SETTINGS') { throw 'The exact confirmation phrase is required; no Azure mutation was attempted.' }
if (-not $Execute -and -not [string]::IsNullOrWhiteSpace($ConfirmMutation)) { throw 'Do not supply a mutation confirmation without -Execute.' }
if ([string]::IsNullOrWhiteSpace($ExpectedSubscriptionId) -or $ExpectedSubscriptionId -notmatch '^[0-9a-fA-F-]{36}$') {
    throw 'ExpectedSubscriptionId must identify the approved Azure-dev subscription.'
}
if ($Action -eq 'Route' -and $ReplayRequestId -eq [guid]::Empty) { throw 'Route requires one approved ReplayRequestId.' }
if ($Action -eq 'Pause' -and [string]::IsNullOrWhiteSpace($PreflightReportPath)) { throw 'Pause requires a passing read-only preflight report.' }
if ($Action -in @('Route', 'Restore', 'RestoreSafe') -and [string]::IsNullOrWhiteSpace($ManifestPath)) { throw "$Action requires the exact pause manifest path." }
if ($Action -eq 'Restore' -and [string]::IsNullOrWhiteSpace($ReplayCompletionEvidencePath)) { throw 'Restore requires verified replay completion evidence; use RestoreSafe to restore with the publisher paused.' }

$catalog = Get-Content -LiteralPath (Join-Path $repoRoot 'automation/config/runtime-targets.json') -Raw | ConvertFrom-Json
$matches = @($catalog.targets | Where-Object key -eq 'azure-dev')
if ($matches.Count -ne 1 -or $matches[0].environment -ne 'dev') { throw 'Exactly one Azure-dev runtime target is required.' }
$target = $matches[0]
$appNames = [ordered]@{
    orders = [string]$target.azureOrdersContainerAppName
    payments = [string]$target.azurePaymentsContainerAppName
    inventory = [string]$target.azureInventoryContainerAppName
    notifications = [string]$target.azureNotificationsContainerAppName
}
if ($Action -eq 'Pause' -and [string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path $repoRoot "TestResults/Phase10/azure-replay-drill-$([DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssZ')).json"
}
$manifestFullPath = Resolve-DrillEvidencePath -Path $ManifestPath -Label 'Replay drill manifest'
if ($Action -eq 'Pause' -and (Test-Path -LiteralPath $manifestFullPath)) { throw 'Pause manifest already exists; choose a unique path.' }
if ($Action -ne 'Pause' -and -not (Test-Path -LiteralPath $manifestFullPath -PathType Leaf)) { throw 'Replay drill manifest does not exist.' }
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $repoRoot "TestResults/Phase10/azure-replay-drill-config-$([DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssZ')).json"
}
$reportFull = Resolve-DrillEvidencePath -Path $ReportPath -Label 'Controller report'
if (Test-Path -LiteralPath $reportFull) { throw 'Controller report already exists; select a unique path.' }

$accountJson = & az account show --subscription $ExpectedSubscriptionId --query '{id:id,state:state}' -o json 2>$null
if ($LASTEXITCODE -ne 0) { throw 'Azure account verification failed.' }
$account = $accountJson | ConvertFrom-Json
if ($account.id -ne $ExpectedSubscriptionId -or $account.state -ne 'Enabled') { throw 'Azure CLI is not on the expected enabled subscription.' }

$liveApps = [ordered]@{}
$liveStates = [ordered]@{}
foreach ($key in $appNames.Keys) {
    $json = & az containerapp show --subscription $ExpectedSubscriptionId --resource-group $target.azureResourceGroupName --name $appNames[$key] -o json 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Read-only inspection failed for publisher '$($appNames[$key])'." }
    $liveApps[$key] = $json | ConvertFrom-Json
    $liveStates[$key] = Get-DrillConfigState $liveApps[$key]
}
$functionJson = & az functionapp config appsettings list --subscription $ExpectedSubscriptionId --resource-group $target.azureResourceGroupName --name $target.azureFunctionAppName --query "[?name=='ServiceBus__ReplayRequestQueueName' || name=='Phase10ReplayRequestQueueName'].{name:name,value:value}" -o json 2>$null
if ($LASTEXITCODE -ne 0) { throw 'Read-only Function queue inspection failed; no settings were changed.' }
$functionQueues = @($functionJson | ConvertFrom-Json | ForEach-Object { [string]$_.value } | Sort-Object -Unique)
if ($functionQueues.Count -eq 0 -or $functionQueues -notcontains [string]$target.azureReplayRequestQueueName -or $functionQueues -contains [string]$target.azureReplayDrillRequestQueueName) {
    throw 'Deployed Function must remain on the normal replay queue before any publisher configuration transition.'
}
$namespaceName = ([string]$target.azureServiceBusFullyQualifiedNamespace -split '\.')[0]
$queuesJson = & az servicebus queue list --subscription $ExpectedSubscriptionId --resource-group $target.azureResourceGroupName --namespace-name $namespaceName --query '[].name' -o json 2>$null
if ($LASTEXITCODE -ne 0) { throw 'Read-only Service Bus queue inspection failed; no settings were changed.' }
$queues = @($queuesJson | ConvertFrom-Json)
if ($queues -notcontains [string]$target.azureReplayRequestQueueName) {
    throw 'The normal Functions replay queue must exist before changing publisher settings.'
}
if ($Action -in @('Pause', 'Route') -and $queues -notcontains [string]$target.azureReplayDrillRequestQueueName) {
    throw 'The isolated replay queue must exist before pausing or routing a drill request.'
}

$baseline = @{
    orders = @{ enabled = 'true'; queue = [string]$target.azureReplayRequestQueueName; requestId = '' }
    payments = @{ enabled = 'false'; queue = [string]$target.azureReplayRequestQueueName; requestId = '' }
    inventory = @{ enabled = 'false'; queue = [string]$target.azureReplayRequestQueueName; requestId = '' }
    notifications = @{ enabled = 'false'; queue = [string]$target.azureReplayRequestQueueName; requestId = '' }
}
$expectedTransition = @{}
$manifest = $null

switch ($Action) {
    'Pause' {
        $preflightFull = Resolve-DrillEvidencePath -Path $PreflightReportPath -Label 'Replay preflight report'
        if (-not (Test-Path -LiteralPath $preflightFull -PathType Leaf)) { throw 'Replay preflight report is missing.' }
        $preflight = Get-Content -LiteralPath $preflightFull -Raw | ConvertFrom-Json
        if ($preflight.status -ne 'PASS' -or $preflight.subscriptionVerified -ne $true -or $preflight.subscriptionId -ne $ExpectedSubscriptionId) { throw 'Read-only replay preflight is not PASS for the verified subscription.' }
        foreach ($key in $appNames.Keys) {
            if (-not (Test-DrillConfigStateEquals $liveStates[$key] $baseline[$key])) {
                throw "Live publisher '$($appNames[$key])' is not at the approved baseline. Stop; do not auto-normalize unsafe configuration."
            }
            if ($liveApps[$key].properties.runningStatus -ne 'Running' -or
                $liveStates[$key].latestRevision -ne $liveStates[$key].revision -or
                $liveApps[$key].properties.template.containers[0].image -notmatch '@sha256:[a-f0-9]{64}$') {
                throw "Publisher '$($appNames[$key])' is not running a digest-pinned image; pause is refused."
            }
            $provenance = @($preflight.applicationRevisions | Where-Object app -eq $appNames[$key])
            if ($provenance.Count -ne 1 -or $provenance[0].revision -ne $liveStates[$key].revision -or $provenance[0].image -ne $liveStates[$key].image) {
                throw "Publisher '$($appNames[$key])' changed after the passing preflight; rerun preflight before pausing."
            }
            $expectedTransition[$key] = @{ enabled = 'false'; queue = [string]$target.azureReplayRequestQueueName; requestId = '' }
        }
        $manifest = [ordered]@{
            schemaVersion = 1
            environment = 'dev'
            subscriptionId = $ExpectedSubscriptionId
            resourceGroup = [string]$target.azureResourceGroupName
            createdUtc = [DateTimeOffset]::UtcNow.ToString('O')
            status = 'snapshot-created'
            originalStates = $liveStates
            replayRequestId = $null
        }
    }
    'Route' {
        foreach ($key in $appNames.Keys) {
            if ([string]$liveStates[$key].enabled -ne 'false' -or
                [string]$liveStates[$key].queue -ne [string]$target.azureReplayRequestQueueName -or
                -not [string]::IsNullOrEmpty([string]$liveStates[$key].requestId)) {
                throw "All publishers must be verified paused on the normal queue before routing; '$($appNames[$key])' differs."
            }
            $expectedTransition[$key] = @{ enabled = 'false'; queue = [string]$target.azureReplayRequestQueueName; requestId = '' }
        }
        $expectedTransition.orders = @{ enabled = 'true'; queue = [string]$target.azureReplayDrillRequestQueueName; requestId = $ReplayRequestId.ToString('D') }
        $manifest = Get-Content -LiteralPath $manifestFullPath -Raw | ConvertFrom-Json -AsHashtable
        if ($manifest.environment -ne 'dev' -or $manifest.subscriptionId -ne $ExpectedSubscriptionId -or $manifest.resourceGroup -ne $target.azureResourceGroupName) {
            throw 'Pause manifest target does not match Azure dev subscription/resource group.'
        }
        if ($manifest.status -ne 'paused') { throw 'Replay routing requires a fully verified paused manifest.' }
        foreach ($key in $appNames.Keys) {
            $saved = $manifest.originalStates[$key]
            if (-not $saved -or -not (Test-DrillConfigStateEquals $saved $baseline[$key])) { throw 'Pause manifest is incomplete or does not describe the approved baseline.' }
            $pausedState = $manifest.pausedStates[$key]
            if (-not $pausedState -or $liveStates[$key].image -cne $saved.image -or
                $liveStates[$key].image -cne $pausedState.image -or
                $liveStates[$key].revision -ne $pausedState.revision -or
                $liveStates[$key].latestRevision -ne $pausedState.revision -or
                $liveStates[$key].runningStatus -ne 'Running') {
                throw "Publisher '$($appNames[$key])' image or ready revision drifted after Pause; refusing to route."
            }
        }
        $manifest.replayRequestId = $ReplayRequestId.ToString('D')
        $manifest.status = 'routing'
    }
    { $_ -in @('Restore', 'RestoreSafe') } {
        $manifest = Get-Content -LiteralPath $manifestFullPath -Raw | ConvertFrom-Json -AsHashtable
        if ($manifest.environment -ne 'dev' -or $manifest.subscriptionId -ne $ExpectedSubscriptionId -or $manifest.resourceGroup -ne $target.azureResourceGroupName) {
            throw 'Recovery manifest target does not match Azure dev subscription/resource group.'
        }
        if ($Action -eq 'Restore') {
            $completionFullPath = Resolve-DrillEvidencePath -Path $ReplayCompletionEvidencePath -Label 'Replay completion evidence'
            if (-not (Test-Path -LiteralPath $completionFullPath -PathType Leaf)) { throw 'Replay completion evidence is missing.' }
            $completionEvidence = Get-Content -LiteralPath $completionFullPath -Raw | ConvertFrom-Json -AsHashtable
            Assert-ReplayCompletionEvidence -Evidence $completionEvidence -Manifest $manifest -SubscriptionId $ExpectedSubscriptionId
        }
        foreach ($key in $appNames.Keys) {
            $original = $manifest.originalStates[$key]
            if (-not $original) { throw "Recovery manifest lacks '$key' original state; restoration is blocked." }
            if ($Action -eq 'RestoreSafe') {
                $expectedTransition[$key] = @{ enabled = 'false'; queue = [string]$target.azureReplayRequestQueueName; requestId = '' }
            } else {
                $expectedTransition[$key] = @{ enabled = [string]$original.enabled; queue = [string]$original.queue; requestId = [string]$original.requestId }
            }
            $paused = ([string]$liveStates[$key].enabled -eq 'false' -and
                [string]$liveStates[$key].queue -eq [string]$target.azureReplayRequestQueueName -and
                [string]$liveStates[$key].requestId -eq '')
            $routedOrders = ($key -eq 'orders' -and [string]$liveStates[$key].enabled -eq 'true' -and
                [string]$liveStates[$key].queue -eq [string]$target.azureReplayDrillRequestQueueName -and
                [string]$liveStates[$key].requestId -eq [string]$manifest.replayRequestId)
            if (-not $paused -and -not $routedOrders -and -not (Test-DrillConfigStateEquals $liveStates[$key] $original)) {
                throw "Current '$($appNames[$key])' settings do not match a known drill state or the recorded original; refuse to overwrite drift."
            }
            if ($liveStates[$key].image -ne $original.image) { throw "Publisher '$($appNames[$key])' image changed since the snapshot; restore is blocked pending review." }
        }
        $manifest.status = 'restoring'
    }
}

$plan = @($appNames.Keys | ForEach-Object {
    Get-DrillConfigMutationArguments -AppName $appNames[$_] -State $expectedTransition[$_]
})
Write-Output "Planned action: $Action; Azure writes requested: $($Execute.IsPresent)"
Write-Output ($plan | ConvertTo-Json -Depth 5)
if (-not $Execute) { Write-Output 'Read-only plan only; no Azure settings were changed.'; return }
if (-not $PSCmdlet.ShouldProcess("Azure dev publishers in $($target.azureResourceGroupName)", "$Action replay settings")) { return }

if ($Action -eq 'Pause') {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($manifestFullPath))
    $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestFullPath -Encoding utf8NoBOM
}
if ($Action -in @('Route', 'Restore')) {
    $manifest.status = if ($Action -eq 'Route') { 'routing' } else { 'restoring' }
    $manifest.updatedUtc = [DateTimeOffset]::UtcNow.ToString('O')
    $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestFullPath -Encoding utf8NoBOM
}

$mutated = [System.Collections.Generic.List[string]]::new()
$expectedRevisions = @{}
try {
    foreach ($key in $appNames.Keys) {
        $desired = $expectedTransition[$key]
        $current = $liveStates[$key]
        $expectedRevisions[$key] = $current.revision
        if (Test-DrillConfigStateEquals $current $desired) { continue }
        $planEntry = @($plan | Where-Object appName -eq $appNames[$key])[0]
        $suffix = 'replay-' + [guid]::NewGuid().ToString('N').Substring(0, 12)
        $expectedRevisions[$key] = "$($appNames[$key])--$suffix"
        $arguments = @('containerapp', 'update', '--subscription', $ExpectedSubscriptionId, '--resource-group', [string]$target.azureResourceGroupName, '--name', $appNames[$key], '--revision-suffix', $suffix, '--set-env-vars') + @($planEntry.setEnvVars)
        $removeNames = @($planEntry.removeEnvVars)
        if ($removeNames.Count -gt 0) { $arguments += @('--remove-env-vars') + $removeNames }
        & az @arguments 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Azure update failed for publisher '$($appNames[$key])'; retain manifest and do not continue the drill." }
        $mutated.Add($key)
    }
    $verifiedStates = [ordered]@{}
    foreach ($key in $appNames.Keys) {
        $verifiedStates[$key] = Wait-DrillConfigState -AppName $appNames[$key] -Expected $expectedTransition[$key] -ExpectedImage $liveStates[$key].image -ExpectedRevision $expectedRevisions[$key] -SubscriptionId $ExpectedSubscriptionId -ResourceGroup $target.azureResourceGroupName
    }
    if ($Action -eq 'Pause') { $manifest.pausedStates = $verifiedStates }
    $manifest.status = switch ($Action) { Pause { 'paused' } Route { 'routed' } Restore { 'restored' } RestoreSafe { 'restored-safe-paused' } }
    $manifest.updatedUtc = [DateTimeOffset]::UtcNow.ToString('O')
    if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) { $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestFullPath -Encoding utf8NoBOM }
    $result = [ordered]@{ schemaVersion = 1; action = $Action; status = 'PASS'; subscriptionId = $ExpectedSubscriptionId; verifiedPublishers = @($appNames.Values); mutationPerformed = ($mutated.Count -gt 0); checkedUtc = [DateTimeOffset]::UtcNow.ToString('O') }
} catch {
    if ($manifest) {
        $manifest.status = 'recovery-required'
        $manifest.updatedUtc = [DateTimeOffset]::UtcNow.ToString('O')
        if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) { $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestFullPath -Encoding utf8NoBOM }
    }
    throw
}

if ([string]::IsNullOrWhiteSpace($ReportPath)) { $ReportPath = Join-Path $repoRoot "TestResults/Phase10/azure-replay-drill-config-$([DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssZ')).json" }
$reportFull = Resolve-DrillEvidencePath -Path $ReportPath -Label 'Controller report'
if (Test-Path -LiteralPath $reportFull) { throw 'Controller report already exists; select a unique path.' }
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($reportFull))
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportFull -Encoding utf8NoBOM
Write-Output "Configuration action status: $($result.status)"
Write-Output "Report: $reportFull"
