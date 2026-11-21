#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\phase10-azure-replay-drill-preflight.ps1') -LibraryOnly

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function New-ContainerApp([string]$Name, [string]$ReplayEnabled = 'false', [string]$Queue = 'dlq-replay-requests-dev', [string]$Image = 'registry.example.test/app@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', [bool]$WithRequestFilter = $false) {
    $env = @(
        [pscustomobject]@{ name = 'ServiceBus__ReplayEnabled'; value = $ReplayEnabled },
        [pscustomobject]@{ name = 'ServiceBus__ReplayRequestQueueName'; value = $Queue }
    )
    if ($WithRequestFilter) { $env += [pscustomobject]@{ name = 'ServiceBus__ReplayRequestId'; value = [guid]::NewGuid().ToString('D') } }
    [pscustomobject]@{
        name = $Name
        properties = [pscustomobject]@{
            latestReadyRevisionName = "$Name--0000001"
            runningStatus = 'Running'
            template = [pscustomobject]@{ containers = @([pscustomobject]@{ image = $Image; env = $env }) }
        }
    }
}

$target = [pscustomobject]@{
    environment = 'dev'
    azureOrdersContainerAppName = 'orders'
    azurePaymentsContainerAppName = 'payments'
    azureInventoryContainerAppName = 'inventory'
    azureNotificationsContainerAppName = 'notifications'
    azureReplayRequestQueueName = 'dlq-replay-requests-dev'
    azureReplayDrillRequestQueueName = 'dlq-replay-drill-requests-dev'
    azureServiceBusFullyQualifiedNamespace = 'sb-orderprocessing-dev.servicebus.windows.net'
    azureOrderEventsTopicName = 'order-events-dev'
}
$normalQueue = $target.azureReplayRequestQueueName
$drillQueue = $target.azureReplayDrillRequestQueueName
$baselineStates = @{
    orders = @{ enabled = 'true'; queue = $normalQueue; requestId = $null }
    payments = @{ enabled = 'false'; queue = $normalQueue; requestId = $null }
    inventory = @{ enabled = 'false'; queue = $normalQueue; requestId = $null }
    notifications = @{ enabled = 'false'; queue = $normalQueue; requestId = $null }
}
$ambiguousQueuePlanRejected = $false
try { [void](Get-ReplayDrillConfigurationPlan -PublisherStates $baselineStates -Action Pause -NormalQueueName $normalQueue -DrillQueueName $normalQueue) } catch { $ambiguousQueuePlanRejected = $true }
Assert-True $ambiguousQueuePlanRejected 'replay planning refuses missing or identical normal/drill queue separation'
$pausePlan = Get-ReplayDrillConfigurationPlan -PublisherStates $baselineStates -Action Pause -NormalQueueName $normalQueue -DrillQueueName $drillQueue
Assert-True (-not $pausePlan.mutationPerformed) 'pause planning is non-mutating'
Assert-True (@($pausePlan.publishers | Where-Object enabled -eq 'true').Count -eq 0) 'pause plan disables all four publishers'
$pausedStates = @{}
foreach ($publisher in $pausePlan.publishers) {
    $pausedStates[$publisher.name] = @{ enabled = $publisher.enabled; queue = $publisher.queue; requestId = $publisher.requestId }
}
$routePlan = Get-ReplayDrillConfigurationPlan -PublisherStates $pausedStates -Action Route -NormalQueueName $normalQueue -DrillQueueName $drillQueue -ReplayRequestId '22222222-2222-4222-8222-222222222222'
Assert-True (($routePlan.publishers | Where-Object name -eq 'orders').queue -eq $drillQueue) 'only Orders is routed to the isolated queue'
Assert-True (@($routePlan.publishers | Where-Object { $_.name -ne 'orders' -and $_.enabled -ne 'false' }).Count -eq 0) 'other publishers remain paused'
$restorePlan = Get-ReplayDrillConfigurationPlan -PublisherStates $pausedStates -Action Restore -NormalQueueName $normalQueue -DrillQueueName $drillQueue -OriginalStates $baselineStates
Assert-True (($restorePlan.publishers | Where-Object name -eq 'orders').queue -eq $normalQueue) 'restore returns Orders to its exact normal queue'
$safeRestorePlan = Get-ReplayDrillConfigurationPlan -PublisherStates $pausedStates -Action RestoreSafe -NormalQueueName $normalQueue -DrillQueueName $drillQueue -OriginalStates $baselineStates
Assert-True (($safeRestorePlan.publishers | Where-Object name -eq 'orders').enabled -eq 'false') 'safe restore keeps Orders paused when completion proof is unavailable'
$safeRestorePlan.publishers | Where-Object name -ne 'orders' | ForEach-Object {
    Assert-True ($_.enabled -eq 'false' -and $_.queue -eq $normalQueue) 'safe restore leaves other publishers paused on normal queue'
}
$unsafeStates = @{
    orders = @{ enabled = 'true'; queue = $normalQueue; requestId = $null }
    payments = @{ enabled = 'true'; queue = $normalQueue; requestId = $null }
    inventory = @{ enabled = 'true'; queue = $normalQueue; requestId = $null }
    notifications = @{ enabled = 'true'; queue = $normalQueue; requestId = $null }
}
$unsafePlanRejected = $false
try { [void](Get-ReplayDrillConfigurationPlan -PublisherStates $unsafeStates -Action Pause -NormalQueueName $normalQueue -DrillQueueName $drillQueue) } catch { $unsafePlanRejected = $true }
Assert-True $unsafePlanRejected 'unsafe all-publishers-enabled baseline is refused, not automatically repaired'
$routeWithoutPauseRejected = $false
try { [void](Get-ReplayDrillConfigurationPlan -PublisherStates $baselineStates -Action Route -NormalQueueName $normalQueue -DrillQueueName $drillQueue -ReplayRequestId '22222222-2222-4222-8222-222222222222') } catch { $routeWithoutPauseRejected = $true }
Assert-True $routeWithoutPauseRejected 'routing refuses to proceed before all publishers are paused'

$apps = @{
    orders = New-ContainerApp 'orders' 'true'
    payments = New-ContainerApp 'payments'
    inventory = New-ContainerApp 'inventory'
    notifications = New-ContainerApp 'notifications'
}
$functionApp = [pscustomobject]@{ appSettings = @([pscustomobject]@{ name = 'Phase10ReplayRequestQueueName'; value = 'dlq-replay-requests-dev' }) }
$roles = @{ queue = @(); topic = @() }
$checks = @(Get-ReplayDrillRuntimeChecks -Target $target -ContainerApps $apps -FunctionApp $functionApp -QueueNames @('dlq-replay-requests-dev','dlq-replay-drill-requests-dev') -RoleAssignments $roles -ApplicationInsightsQueryAvailable $true -RunnerPrincipalObjectId '00000000-0000-4000-8000-000000000001')
Assert-True (@($checks | Where-Object status -ne 'PASS').Count -eq 2) 'missing runner role assignments are reported without claiming readiness'
Assert-True (@($checks | Where-Object name -like 'publisher * replay state is approved baseline' | Where-Object status -eq 'PASS').Count -eq 4) 'only Orders is enabled in the approved deployment baseline'
Assert-True (@($checks | Where-Object name -eq 'operator can query Application Insights').status -eq 'PASS') 'duplicate-consumer telemetry query capability is included in preflight'

$unsafeApps = @{
    orders = New-ContainerApp 'orders' 'true'
    payments = New-ContainerApp 'payments' 'true'
    inventory = New-ContainerApp 'inventory' 'true'
    notifications = New-ContainerApp 'notifications' 'true'
}
$unsafeChecks = @(Get-ReplayDrillRuntimeChecks -Target $target -ContainerApps $unsafeApps -FunctionApp $functionApp -QueueNames @('dlq-replay-requests-dev','dlq-replay-drill-requests-dev') -RoleAssignments $roles -RunnerPrincipalObjectId '')
Assert-True (@($unsafeChecks | Where-Object name -like 'publisher * replay state is approved baseline' | Where-Object status -eq 'BLOCKED').Count -eq 3) 'the live historical all-publishers-enabled state is blocked'
Assert-True (@($unsafeChecks | Where-Object name -eq 'runner principal is explicitly configured').status -eq 'BLOCKED') 'missing runner identity blocks readiness'

$missingQueueChecks = @(Get-ReplayDrillRuntimeChecks -Target $target -ContainerApps $apps -FunctionApp $functionApp -QueueNames @('dlq-replay-requests-dev') -RoleAssignments $roles -RunnerPrincipalObjectId '')
Assert-True (@($missingQueueChecks | Where-Object name -eq 'isolated drill queue exists').status -eq 'BLOCKED') 'missing isolated queue blocks readiness'

$missingTelemetryChecks = @(Get-ReplayDrillRuntimeChecks -Target $target -ContainerApps $apps -FunctionApp $functionApp -QueueNames @('dlq-replay-requests-dev','dlq-replay-drill-requests-dev') -RoleAssignments $roles -ApplicationInsightsQueryAvailable $false -RunnerPrincipalObjectId '')
Assert-True (@($missingTelemetryChecks | Where-Object name -eq 'operator can query Application Insights').status -eq 'BLOCKED') 'missing duplicate-consumer telemetry access blocks drill readiness'

$staleApps = @{
    orders = New-ContainerApp 'orders' 'true' 'dlq-replay-requests-dev' 'registry.example.test/app@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' $true
    payments = New-ContainerApp 'payments'
    inventory = New-ContainerApp 'inventory'
    notifications = New-ContainerApp 'notifications'
}
$staleChecks = @(Get-ReplayDrillRuntimeChecks -Target $target -ContainerApps $staleApps -FunctionApp $functionApp -QueueNames @('dlq-replay-requests-dev','dlq-replay-drill-requests-dev') -RoleAssignments $roles -RunnerPrincipalObjectId '')
Assert-True (@($staleChecks | Where-Object name -eq 'publisher orders has no stale request filter').status -eq 'BLOCKED') 'stale exact-request filters block readiness'

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$reportRoot = Join-Path $repositoryRoot 'TestResults'
$ordinaryReportPath = Resolve-ReplayPreflightReportPath -Path 'TestResults/Phase10/preflight.json' -RepositoryRoot $repositoryRoot
Assert-True ($ordinaryReportPath.StartsWith($reportRoot, [StringComparison]::OrdinalIgnoreCase)) 'preflight report path remains under TestResults'
$traversalRejected = $false
try { [void](Resolve-ReplayPreflightReportPath -Path 'TestResults/../../outside.json' -RepositoryRoot $repositoryRoot) } catch { $traversalRejected = $true }
Assert-True $traversalRejected 'preflight report path traversal is refused'

$linkName = 'replay-preflight-path-safety-' + [guid]::NewGuid().ToString('N')
$linkPath = Join-Path $reportRoot $linkName
$externalTarget = Join-Path ([IO.Path]::GetTempPath()) $linkName
try {
    New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $externalTarget -ErrorAction Stop | Out-Null
    New-Item -ItemType Junction -Path $linkPath -Target $externalTarget -ErrorAction Stop | Out-Null
    $reparseRejected = $false
    try {
        [void](Resolve-ReplayPreflightReportPath -Path (Join-Path 'TestResults' (Join-Path $linkName 'preflight.json')) -RepositoryRoot $repositoryRoot)
    } catch { $reparseRejected = $_.Exception.Message -match 'symbolic link or reparse point' }
    Assert-True $reparseRejected 'preflight report path through a junction is refused'
} finally {
    if (Test-Path -LiteralPath $linkPath) { Remove-Item -LiteralPath $linkPath -Force }
    if (Test-Path -LiteralPath $externalTarget) { Remove-Item -LiteralPath $externalTarget -Force -Recurse }
}

Write-Output 'Phase 10 Azure replay preflight contract tests passed (6 groups).'
