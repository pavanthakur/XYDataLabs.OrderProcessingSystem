#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scriptPath = Join-Path $root 'scripts/phase10-azure-replay-drill-config.ps1'
$target = (Get-Content -Raw (Join-Path $root 'automation/config/runtime-targets.json') | ConvertFrom-Json).targets |
    Where-Object key -eq 'azure-dev'
$subscription = '00000000-0000-0000-0000-000000000001'
$request = '00000000-0000-0000-0000-000000000002'
$apps = @{}
$mock = @{ reads = 0; writes = 0; failNextUpdate = $false; wrongRevision = $false }
$image = 'registry.example.test/orders@sha256:' + ('a' * 64)
$orders = $target.azureOrdersContainerAppName
foreach ($name in @($orders, $target.azurePaymentsContainerAppName, $target.azureInventoryContainerAppName, $target.azureNotificationsContainerAppName)) {
    $apps[$name] = @{ properties = @{
        latestRevisionName = "${name}--base"; latestReadyRevisionName = "${name}--base"; runningStatus = 'Running'
        template = @{ containers = @(@{ image = $image; env = @(
            @{ name = 'ServiceBus__ReplayEnabled'; value = if ($name -eq $orders) { 'true' } else { 'false' } }
            @{ name = 'ServiceBus__ReplayRequestQueueName'; value = $target.azureReplayRequestQueueName }
        ) }) }
    } }
}

function az {
    $verb = $args[0..1] -join ' '
    $global:LASTEXITCODE = 0
    if ($verb -ne 'containerapp update') { $mock.reads++ }
    switch ($verb) {
        'account show' { @{id = $subscription; state = 'Enabled'} | ConvertTo-Json }
        'functionapp config' { ConvertTo-Json -InputObject @(@{ value = $target.azureReplayRequestQueueName }) -Compress }
        'servicebus queue' { ConvertTo-Json -InputObject @($target.azureReplayRequestQueueName, $target.azureReplayDrillRequestQueueName) -Compress }
        'containerapp show' { $apps[$args[[array]::IndexOf($args, '--name') + 1]] | ConvertTo-Json -Depth 10 }
        'containerapp update' {
            $mock.writes++
            $name = $args[[array]::IndexOf($args, '--name') + 1]
            $state = $apps[$name].properties
            $env = @{}
            foreach ($item in $state.template.containers[0].env) { $env[$item.name] = $item.value }
            $remove = $false
            foreach ($arg in $args[([array]::IndexOf($args, '--set-env-vars') + 1)..($args.Count - 1)]) {
                if ($arg -eq '--remove-env-vars') { $remove = $true; continue }
                if ($remove) { $env.Remove($arg); continue }
                $key,$value = $arg -split '=', 2
                $env[$key] = $value
            }
            $state.template.containers[0].env = @($env.GetEnumerator() | ForEach-Object { @{name = $_.Key; value = $_.Value} })
            $state.latestRevisionName = if ($mock.wrongRevision) { "$name--unexpected" } else { "$name--$($args[[array]::IndexOf($args, '--revision-suffix') + 1])" }
            $state.latestReadyRevisionName = $state.latestRevisionName
            if ($mock.failNextUpdate) { $mock.failNextUpdate = $false; $global:LASTEXITCODE = 1 }
        }
        default { throw "Unexpected mock command: $verb" }
    }
}

function Start-Sleep { param([int]$Seconds) }

function Assert-Rejected([scriptblock]$Run, [string]$Pattern) {
    try { & $Run | Out-Null }
    catch { if ($_.Exception.Message -match $Pattern) { return }; throw }
    throw "Expected controller rejection: $Pattern"
}

$base = Join-Path $root ('TestResults/replay-controller-test-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($base)
$preflight = Join-Path $base 'preflight.json'
$manifest = Join-Path $base 'manifest.json'
$completion = Join-Path $base 'completion.json'
$paths = @($preflight, $manifest, $completion)
$common = @{ ExpectedSubscriptionId = $subscription; ManifestPath = $manifest }
$execute = @{ Execute = $true; ConfirmMutation = 'MUTATE AZURE DEV REPLAY SETTINGS'; Confirm = $false }
try {
    foreach ($action in @('Pause', 'Route', 'Restore', 'RestoreSafe')) {
        Assert-Rejected { & $scriptPath -Action $action } 'ExpectedSubscriptionId'
    }
    if ($mock.reads -ne 0) { throw 'Invalid parameters reached Azure.' }
    @{
        status = 'PASS'; subscriptionVerified = $true; subscriptionId = $subscription
        applicationRevisions = @($apps.Keys | ForEach-Object { @{ app = $_; revision = $apps[$_].properties.latestReadyRevisionName; image = $image } })
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $preflight
    $report = Join-Path $base 'pause.json'; $paths += $report
    & $scriptPath -Action Pause @common -PreflightReportPath $preflight -ReportPath $report | Out-Null
    if ($mock.writes -ne 0 -or (Test-Path -LiteralPath $manifest)) { throw 'Read-only pause changed state.' }
    & $scriptPath -Action Pause @common @execute -PreflightReportPath $preflight -ReportPath $report | Out-Null
    $paused = (Get-Content -Raw $manifest | ConvertFrom-Json).pausedStates.orders.revision
    if ($paused -eq "$orders--base" -or -not (Test-Path -LiteralPath $report)) { throw 'Pause did not record the new ready revision and requested report.' }

    $report = Join-Path $base 'route.json'; $paths += $report
    $apps[$orders].properties.latestReadyRevisionName = "$orders--drift"
    Assert-Rejected { & $scriptPath -Action Route @common @execute -ReplayRequestId $request -ReportPath $report } 'drifted after Pause'
    $apps[$orders].properties.latestReadyRevisionName = $paused
    $apps[$orders].properties.template.containers[0].image = 'registry.example.test/orders@sha256:' + ('b' * 64)
    Assert-Rejected { & $scriptPath -Action Route @common @execute -ReplayRequestId $request -ReportPath $report } 'drifted after Pause'
    $apps[$orders].properties.template.containers[0].image = $image
    if ($mock.writes -ne 1) { throw 'A drifted route attempted a write.' }
    & $scriptPath -Action Route @common @execute -ReplayRequestId $request -ReportPath $report | Out-Null

    $report = Join-Path $base 'restore.json'; $paths += $report
    @{status = 'PASS'; environment = 'dev'; subscriptionId = $subscription; replayRequestId = $request; publisherCheckpointed = $true; pendingReplayRequestCount = 1} |
        ConvertTo-Json | Set-Content -LiteralPath $completion
    Assert-Rejected { & $scriptPath -Action Restore @common @execute -ReplayCompletionEvidencePath $completion -ReportPath $report } 'no replay requests remain pending'
    $evidence = Get-Content -Raw $completion | ConvertFrom-Json -AsHashtable
    $evidence.pendingReplayRequestCount = 0
    $evidence | ConvertTo-Json | Set-Content -LiteralPath $completion
    $mock.failNextUpdate = $true
    Assert-Rejected { & $scriptPath -Action Restore @common @execute -ReplayCompletionEvidencePath $completion -ReportPath $report } 'Azure update failed'
    if ((Get-Content -Raw $manifest | ConvertFrom-Json).status -ne 'recovery-required') { throw 'Partial update did not preserve recovery status.' }

    $report = Join-Path $base 'safe.json'; $paths += $report
    & $scriptPath -Action RestoreSafe @common @execute -ReportPath $report | Out-Null
    if ((Get-Content -Raw $manifest | ConvertFrom-Json).status -ne 'restored-safe-paused') { throw 'Safe restore did not record its terminal state.' }
    if (($apps[$orders].properties.template.containers[0].env | Where-Object name -eq 'ServiceBus__ReplayEnabled').value -ne 'false') { throw 'Safe restore re-enabled Orders replay.' }

    $report = Join-Path $base 'restore.json'
    $mock.wrongRevision = $true
    Assert-Rejected { & $scriptPath -Action Restore @common @execute -ReplayCompletionEvidencePath $completion -ReportPath $report } 'did not converge'
    if ((Get-Content -Raw $manifest | ConvertFrom-Json).status -ne 'recovery-required' -or (Test-Path -LiteralPath $report)) { throw 'Unexpected ready revision was accepted.' }
    $mock.wrongRevision = $false
    & $scriptPath -Action Restore @common @execute -ReplayCompletionEvidencePath $completion -ReportPath $report | Out-Null
    if ((Get-Content -Raw $manifest | ConvertFrom-Json).status -ne 'restored') { throw 'Normal restore did not verify the baseline.' }
    Write-Output 'Azure replay controller entrypoint tests passed: rejection, read-only, pause, drift, route, partial update, safe recovery and exact-revision restoration.'
} finally {
    foreach ($path in $paths) { if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path } }
    [IO.Directory]::Delete($base)
}
