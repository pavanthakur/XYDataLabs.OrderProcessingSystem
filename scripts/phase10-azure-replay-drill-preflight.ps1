#Requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$LibraryOnly,
    [ValidateSet('dev')][string]$Environment = 'dev',
    [Parameter(Mandatory = $false)][string]$ExpectedSubscriptionId,
    [string]$RunnerPrincipalObjectId,
    [string]$ReportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'phase10-azure-replay-drill-common.ps1')

function Resolve-ReplayPreflightReportPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RepositoryRoot
    )
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { throw 'Repository root is required to resolve replay evidence safely.' }
    $full = [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $RepositoryRoot $Path }))
    $testResultsRoot = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'TestResults'))
    $relative = [IO.Path]::GetRelativePath($testResultsRoot, $full)
    if ($relative -eq '.' -or [IO.Path]::IsPathRooted($relative) -or
        $relative -eq '..' -or $relative.StartsWith('..' + [IO.Path]::DirectorySeparatorChar, [StringComparison]::Ordinal) -or
        $relative.StartsWith('..' + [IO.Path]::AltDirectorySeparatorChar, [StringComparison]::Ordinal)) {
        throw 'Replay preflight report must be written under project TestResults.'
    }

    $cursor = $testResultsRoot
    $candidates = @($cursor)
    foreach ($segment in $relative.Split([IO.Path]::DirectorySeparatorChar, [StringSplitOptions]::RemoveEmptyEntries)) {
        $cursor = Join-Path $cursor $segment
        $candidates += $cursor
    }
    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate)) { continue }
        $item = Get-Item -LiteralPath $candidate -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Replay preflight report cannot pass through a symbolic link or reparse point under TestResults.'
        }
    }
    return $full
}

function Get-ReplayDrillConfigurationPlan {
    <#
      Pure transition planner for the temporary replay window. It deliberately
      accepts only the approved deployed baseline; it cannot normalize an
      unsafe live configuration or perform Azure writes.
    #>
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$PublisherStates,
        [Parameter(Mandatory)][ValidateSet('Pause', 'Route', 'Restore', 'RestoreSafe')][string]$Action,
        [Parameter(Mandatory)][string]$NormalQueueName,
        [Parameter(Mandatory)][string]$DrillQueueName,
        [guid]$ReplayRequestId = [guid]::Empty,
        [System.Collections.IDictionary]$OriginalStates
    )

    $names = @('orders', 'payments', 'inventory', 'notifications')
    if (@($PublisherStates.Keys | Where-Object { $_ -notin $names }).Count -gt 0 -or
        @($names | Where-Object { -not $PublisherStates.Contains($_) }).Count -gt 0) {
        throw 'Replay configuration transition requires exactly the four known publisher states.'
    }

    if ([string]::IsNullOrWhiteSpace($NormalQueueName) -or [string]::IsNullOrWhiteSpace($DrillQueueName) -or
        [string]::Equals($NormalQueueName, $DrillQueueName, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Replay queue names must be explicit, non-empty, and distinct.'
    }
    $normalQueue = $NormalQueueName
    $drillQueue = $DrillQueueName
    $baseline = @{
        orders = @{ enabled = 'true'; queue = $normalQueue; requestId = $null }
        payments = @{ enabled = 'false'; queue = $normalQueue; requestId = $null }
        inventory = @{ enabled = 'false'; queue = $normalQueue; requestId = $null }
        notifications = @{ enabled = 'false'; queue = $normalQueue; requestId = $null }
    }

    function Test-StateEquals {
        param([object]$Actual, [System.Collections.IDictionary]$Expected)
        return ([string]$Actual.enabled -eq [string]$Expected.enabled -and
            [string]$Actual.queue -eq [string]$Expected.queue -and
            [string]$Actual.requestId -eq [string]$Expected.requestId)
    }
    function Test-AllPaused {
        param([System.Collections.IDictionary]$States)
        foreach ($name in $names) {
            if ([string]$States[$name].enabled -ne 'false' -or
                [string]$States[$name].queue -ne $normalQueue -or
                -not [string]::IsNullOrEmpty([string]$States[$name].requestId)) { return $false }
        }
        return $true
    }

    switch ($Action) {
        'Pause' {
            foreach ($name in $names) {
                if (-not (Test-StateEquals $PublisherStates[$name] $baseline[$name])) {
                    throw "Cannot pause publishers: '$name' is not at the approved single-publisher baseline. Run read-only preflight and investigate; do not normalize automatically."
                }
            }
            $desired = @{}
            foreach ($name in $names) { $desired[$name] = @{ enabled = 'false'; queue = $normalQueue; requestId = $null } }
        }
        'Route' {
            if (-not (Test-AllPaused $PublisherStates)) { throw 'Cannot route replay: all four publishers must first be paused and verified.' }
            if ($ReplayRequestId -eq [guid]::Empty) { throw 'Cannot route replay without one explicit, approved replay request ID.' }
            $desired = @{}
            foreach ($name in $names) { $desired[$name] = @{ enabled = 'false'; queue = $normalQueue; requestId = $null } }
            $desired.orders = @{ enabled = 'true'; queue = $drillQueue; requestId = $ReplayRequestId.ToString('D') }
        }
        { $_ -in @('Restore', 'RestoreSafe') } {
            if (-not $OriginalStates) { throw 'Restore requires the exact pre-drill snapshot; guessing a baseline is prohibited.' }
            foreach ($name in $names) {
                if (-not $OriginalStates.Contains($name) -or -not (Test-StateEquals $OriginalStates[$name] $baseline[$name])) {
                    throw 'The saved state is incomplete or differs from the approved baseline; stop and review the recovery manifest.'
                }
            }
            if ($Action -eq 'Restore') { $desired = $OriginalStates }
            else {
                $desired = @{}
                foreach ($name in $names) { $desired[$name] = @{ enabled = 'false'; queue = $normalQueue; requestId = $null } }
            }
        }
    }

    return [pscustomobject]@{
        action = $Action
        mutationPerformed = $false
        publishers = @($names | ForEach-Object {
            [pscustomobject]@{ name = $_; enabled = $desired[$_].enabled; queue = $desired[$_].queue; requestId = $desired[$_].requestId }
        })
    }
}

function Get-ReplayDrillRuntimeChecks {
    param(
        [Parameter(Mandatory)][object]$Target,
        [Parameter(Mandatory)][System.Collections.IDictionary]$ContainerApps,
        [Parameter(Mandatory)][object]$FunctionApp,
        [Parameter(Mandatory)][string[]]$QueueNames,
        [Parameter(Mandatory)][System.Collections.IDictionary]$RoleAssignments,
        [bool]$ApplicationInsightsQueryAvailable = $false,
        [string]$RunnerPrincipalObjectId
    )

    $checks = [System.Collections.Generic.List[object]]::new()
    function Add-Check {
        param([string]$Name, [bool]$Passed, [string]$Detail)
        $checks.Add([pscustomobject]@{ name = $Name; status = if ($Passed) { 'PASS' } else { 'BLOCKED' }; detail = $Detail })
    }

    $normalQueue = [string]$Target.azureReplayRequestQueueName
    $drillQueue = [string]$Target.azureReplayDrillRequestQueueName
    $fqdn = [string]$Target.azureServiceBusFullyQualifiedNamespace
    Add-Check 'dev target has distinct normal and drill queues' (
        $Target.environment -eq 'dev' -and
        -not [string]::IsNullOrWhiteSpace($fqdn) -and
        -not [string]::IsNullOrWhiteSpace($normalQueue) -and
        -not [string]::IsNullOrWhiteSpace($drillQueue) -and
        -not [string]::Equals($normalQueue, $drillQueue, [StringComparison]::OrdinalIgnoreCase)
    ) 'Runtime target must be Azure dev with a configured namespace and distinct replay queues.'

    Add-Check 'isolated drill queue exists' ($QueueNames -contains $drillQueue) 'The isolated queue must be deployed before any replay approval.'
    Add-Check 'normal Functions queue exists' ($QueueNames -contains $normalQueue) 'The normal replay queue must remain available to the deployed Function.'
    Add-Check 'operator can query Application Insights' $ApplicationInsightsQueryAvailable 'Duplicate-consumer telemetry read access is required to prove the redelivery reached Inventory and Notifications.'

    $expectedPublishers = @(
        @{ key = 'azureOrdersContainerAppName'; expectedReplay = 'true' },
        @{ key = 'azurePaymentsContainerAppName'; expectedReplay = 'false' },
        @{ key = 'azureInventoryContainerAppName'; expectedReplay = 'false' },
        @{ key = 'azureNotificationsContainerAppName'; expectedReplay = 'false' }
    )
    foreach ($publisher in $expectedPublishers) {
        $appName = [string]$Target.($publisher.key)
        $app = $ContainerApps[$appName]
        if ($null -eq $app) {
            Add-Check "publisher $appName is available" $false 'Container App inspection did not return the required app.'
            continue
        }

        $envVariables = @($app.properties.template.containers[0].env)
        $enabled = Get-ReplayDrillEnvironmentValue $envVariables 'ServiceBus__ReplayEnabled'
        $queue = Get-ReplayDrillEnvironmentValue $envVariables 'ServiceBus__ReplayRequestQueueName'
        $requestId = Get-ReplayDrillEnvironmentValue $envVariables 'ServiceBus__ReplayRequestId'
        $ready = -not [string]::IsNullOrWhiteSpace([string]$app.properties.latestReadyRevisionName) -and
            [string]$app.properties.runningStatus -eq 'Running' -and
            @($app.properties.template.containers | Where-Object { $_.image -notmatch '@sha256:[a-f0-9]{64}$' }).Count -eq 0
        Add-Check "publisher $appName is ready on immutable image" $ready 'Each publisher must have a ready revision and digest-pinned image.'
        Add-Check "publisher $appName replay state is approved baseline" (
            $enabled.count -eq 1 -and $enabled.value -eq $publisher.expectedReplay
        ) "Expected ReplayEnabled=$($publisher.expectedReplay); actual configuration is intentionally not copied into the report."
        Add-Check "publisher $appName targets the normal queue" (
            $queue.count -eq 1 -and $queue.value -eq $normalQueue
        ) 'Every application must target the normal request queue outside the isolated drill window.'
        Add-Check "publisher $appName has no stale request filter" ($requestId.count -eq 0) 'No stale one-request filter may remain outside the drill window.'
    }

    $functionVariables = @($FunctionApp.appSettings)
    $functionQueueEntries = @($functionVariables | Where-Object { $_.name -in @('ServiceBus__ReplayRequestQueueName', 'Phase10ReplayRequestQueueName') })
    $functionQueueNames = @($functionQueueEntries | ForEach-Object { [string]$_.value } | Sort-Object -Unique)
    Add-Check 'deployed Function remains on the normal queue' (
        $functionQueueNames.Count -gt 0 -and $functionQueueNames -contains $normalQueue -and $functionQueueNames -notcontains $drillQueue
    ) 'Function trigger configuration must use the normal replay queue, not the drill queue.'

    $runnerConfigured = -not [string]::IsNullOrWhiteSpace($RunnerPrincipalObjectId)
    Add-Check 'runner principal is explicitly configured' $runnerConfigured 'Supply the dedicated runner object ID; do not infer it from the signed-in user.'
    if ($runnerConfigured) {
        $queueRoles = @($RoleAssignments.queue)
        $topicRoles = @($RoleAssignments.topic)
        $receiverRoleId = '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'
        $senderRoleId = '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39'
        $queueReceiver = @($queueRoles | Where-Object {
            $_.principalId -eq $RunnerPrincipalObjectId -and [string]$_.roleDefinitionId -match "$receiverRoleId$"
        }).Count -gt 0
        $topicSender = @($topicRoles | Where-Object {
            $_.principalId -eq $RunnerPrincipalObjectId -and [string]$_.roleDefinitionId -match "$senderRoleId$"
        }).Count -gt 0
        Add-Check 'runner has queue-scoped receive role' $queueReceiver 'The runner needs Service Bus Data Receiver on only the isolated queue.'
        Add-Check 'runner has topic-scoped send role' $topicSender 'The runner needs Service Bus Data Sender on only the existing business topic.'
    }

    return @($checks)
}

if ($LibraryOnly) { return }
if ([string]::IsNullOrWhiteSpace($ExpectedSubscriptionId) -or $ExpectedSubscriptionId -notmatch '^[0-9a-fA-F-]{36}$') {
    throw 'ExpectedSubscriptionId must identify the approved dev subscription; no Azure queries were started.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$targetCatalog = Get-Content -LiteralPath (Join-Path $repoRoot 'automation/config/runtime-targets.json') -Raw | ConvertFrom-Json
$targets = @($targetCatalog.targets | Where-Object key -eq 'azure-dev')
if ($targets.Count -ne 1) { throw 'Runtime-target catalog must contain exactly one azure-dev target.' }
$target = $targets[0]
if ($target.environment -ne $Environment) { throw 'Azure replay preflight supports the dev target only.' }

$accountJson = & az account show --subscription $ExpectedSubscriptionId --query '{id:id,state:state}' -o json 2>$null
if ($LASTEXITCODE -ne 0) { throw 'Azure CLI read-only account check failed; no Azure mutations were attempted.' }
$account = $accountJson | ConvertFrom-Json
if ($account.id -ne $ExpectedSubscriptionId -or $account.state -ne 'Enabled') { throw 'Azure CLI is not on the expected enabled subscription.' }

$apps = @{}
foreach ($appName in @($target.azureOrdersContainerAppName, $target.azurePaymentsContainerAppName, $target.azureInventoryContainerAppName, $target.azureNotificationsContainerAppName)) {
    $json = & az containerapp show --subscription $ExpectedSubscriptionId --resource-group $target.azureResourceGroupName --name $appName -o json 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Read-only Container App inspection failed for '$appName'." }
    $apps[$appName] = $json | ConvertFrom-Json
}

$functionJson = & az functionapp config appsettings list --subscription $ExpectedSubscriptionId --resource-group $target.azureResourceGroupName --name $target.azureFunctionAppName --query "[?name=='ServiceBus__ReplayRequestQueueName' || name=='Phase10ReplayRequestQueueName'].{name:name,value:value}" -o json 2>$null
if ($LASTEXITCODE -ne 0) { throw 'Read-only Function App settings inspection failed.' }
$functionApp = [pscustomobject]@{ appSettings = @($functionJson | ConvertFrom-Json) }

$queueJson = & az servicebus queue list --subscription $ExpectedSubscriptionId --resource-group $target.azureResourceGroupName --namespace-name $target.azureServiceBusNamespaceName --query '[].name' -o json 2>$null
if ($LASTEXITCODE -ne 0) { throw 'Read-only Service Bus queue inspection failed.' }
$queueNames = @($queueJson | ConvertFrom-Json)
$namespaceJson = & az servicebus namespace show --subscription $ExpectedSubscriptionId --resource-group $target.azureResourceGroupName --name $target.azureServiceBusNamespaceName --query id -o tsv 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$namespaceJson)) { throw 'Could not resolve the Service Bus namespace resource ID.' }
$appInsightsProbe = & az monitor app-insights query --subscription $ExpectedSubscriptionId --resource-group $target.azureResourceGroupName --app $target.azureApplicationInsightsName --analytics-query 'print Result=1 | project Result' --offset 1h -o json 2>$null
$appInsightsQueryAvailable = $false
if ($LASTEXITCODE -eq 0) {
    try {
        $probeResponse = $appInsightsProbe | ConvertFrom-Json
        $appInsightsQueryAvailable = @($probeResponse.tables[0].rows | Where-Object { $_[0] -eq 1 }).Count -eq 1
    } catch { $appInsightsQueryAvailable = $false }
}
$queueScope = "$($namespaceJson.Trim())/queues/$($target.azureReplayDrillRequestQueueName)"
$topicScope = "$($namespaceJson.Trim())/topics/$($target.azureOrderEventsTopicName)"
$roleAssignments = @{ queue = @(); topic = @() }
if (-not [string]::IsNullOrWhiteSpace($RunnerPrincipalObjectId)) {
    foreach ($scope in @(@{ key = 'queue'; id = $queueScope }, @{ key = 'topic'; id = $topicScope })) {
        $roleJson = & az role assignment list --subscription $ExpectedSubscriptionId --scope $scope.id --query '[].{principalId:principalId,roleDefinitionId:roleDefinitionId}' -o json 2>$null
        if ($LASTEXITCODE -ne 0) { throw "Read-only RBAC inspection failed for the isolated $($scope.key) scope." }
        $roleAssignments[$scope.key] = @($roleJson | ConvertFrom-Json)
    }
}

$checks = @(Get-ReplayDrillRuntimeChecks -Target $target -ContainerApps $apps -FunctionApp $functionApp -QueueNames $queueNames -RoleAssignments $roleAssignments -ApplicationInsightsQueryAvailable $appInsightsQueryAvailable -RunnerPrincipalObjectId $RunnerPrincipalObjectId)
$failed = @($checks | Where-Object status -ne 'PASS')
$result = [ordered]@{
    schemaVersion = 1
    status = if ($failed.Count -eq 0) { 'PASS' } else { 'BLOCKED' }
    environment = 'dev'
    subscriptionId = $ExpectedSubscriptionId
    subscriptionVerified = $true
    runnerPrincipalObjectId = $RunnerPrincipalObjectId
    checkedUtc = [DateTimeOffset]::UtcNow.ToString('O')
    applicationRevisions = @($apps.GetEnumerator() | ForEach-Object { [ordered]@{ app = $_.Key; revision = $_.Value.properties.latestReadyRevisionName; image = $_.Value.properties.template.containers[0].image } })
    checks = $checks
    mutationPerformed = $false
}

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $repoRoot "TestResults/Phase10/azure-replay-preflight-$([DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssZ')).json"
}
$resolvedReport = Resolve-ReplayPreflightReportPath -Path $ReportPath -RepositoryRoot $repoRoot
if (Test-Path -LiteralPath $resolvedReport) { throw 'Replay preflight report already exists; select a unique path.' }
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($resolvedReport))
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resolvedReport -Encoding utf8NoBOM
Write-Output "Replay preflight status: $($result.status)"
Write-Output "Checks: $($checks.Count); blocked: $($failed.Count)"
Write-Output "Report: $resolvedReport"
if ($failed.Count -gt 0) { exit 2 }
