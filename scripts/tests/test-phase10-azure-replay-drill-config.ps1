#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $PSScriptRoot '..\phase10-azure-replay-drill-config.ps1') -Action Pause -LibraryOnly

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

$state = Get-DrillConfigState ([pscustomobject]@{
    properties = [pscustomobject]@{
        latestReadyRevisionName = 'orders--0000007'
            latestRevisionName = 'orders--0000007'
        runningStatus = 'Running'
        template = [pscustomobject]@{
            containers = @([pscustomobject]@{
                image = 'registry.example.test/orders@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
                env = @(
                    [pscustomobject]@{ name = 'ServiceBus__ReplayEnabled'; value = 'false' },
                    [pscustomobject]@{ name = 'ServiceBus__ReplayRequestQueueName'; value = 'dlq-replay-requests-dev' }
                )
            })
        }
    }
})
Assert-True ($state.requestId -eq '') 'absent one-request filter is normalized as empty'
Assert-True ($state.revision -eq 'orders--0000007') 'ready revision identity is captured'

$routeArguments = Get-DrillConfigMutationArguments -AppName 'orders' -State @{ enabled = 'true'; queue = 'dlq-replay-drill-requests-dev'; requestId = '22222222-2222-4222-8222-222222222222' }
Assert-True ($routeArguments.setEnvVars.Count -eq 3) 'routed state sets enabled, isolated queue and exact request id together'
Assert-True ($routeArguments.removeEnvVars.Count -eq 0) 'routed state does not remove its request filter'

$restoreArguments = Get-DrillConfigMutationArguments -AppName 'orders' -State @{ enabled = 'true'; queue = 'dlq-replay-requests-dev'; requestId = '' }
Assert-True ($restoreArguments.setEnvVars.Count -eq 2) 'restored state sets normal queue and original enablement'
Assert-True ($restoreArguments.removeEnvVars -contains 'ServiceBus__ReplayRequestId') 'restored state removes the temporary request filter'

$allowedPath = Resolve-DrillEvidencePath -Path 'TestResults/Phase10/replay-plan.json' -Label 'test' -RepositoryRoot $repositoryRoot
Assert-True ($allowedPath.EndsWith([IO.Path]::Combine('TestResults', 'Phase10', 'replay-plan.json'))) 'evidence path remains under TestResults'
$traversalRejected = $false
try { [void](Resolve-DrillEvidencePath -Path 'TestResults/../../outside.json' -Label 'test' -RepositoryRoot $repositoryRoot) } catch { $traversalRejected = $true }
Assert-True $traversalRejected 'evidence path traversal outside TestResults is refused'

$testResultsRoot = Join-Path $repositoryRoot 'TestResults'
$linkName = 'replay-path-safety-' + [guid]::NewGuid().ToString('N')
$linkPath = Join-Path $testResultsRoot $linkName
$externalTarget = Join-Path ([IO.Path]::GetTempPath()) $linkName
try {
    New-Item -ItemType Directory -Path $testResultsRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $externalTarget -ErrorAction Stop | Out-Null
    New-Item -ItemType Junction -Path $linkPath -Target $externalTarget -ErrorAction Stop | Out-Null
    $reparseRejected = $false
    try {
        [void](Resolve-DrillEvidencePath -Path (Join-Path 'TestResults' (Join-Path $linkName 'evidence.json')) -Label 'test' -RepositoryRoot $repositoryRoot)
    } catch { $reparseRejected = $_.Exception.Message -match 'symbolic link or reparse point' }
    Assert-True $reparseRejected 'evidence path through a junction is refused'
} finally {
    if (Test-Path -LiteralPath $linkPath) { Remove-Item -LiteralPath $linkPath -Force }
    if (Test-Path -LiteralPath $externalTarget) { Remove-Item -LiteralPath $externalTarget -Force -Recurse }
}

$manifest = @{ replayRequestId = '22222222-2222-4222-8222-222222222222' }
$completionEvidence = @{
    status = 'PASS'; environment = 'dev'; subscriptionId = '00000000-0000-4000-8000-000000000001'
    replayRequestId = $manifest.replayRequestId; publisherCheckpointed = $true; pendingReplayRequestCount = 0
}
Assert-ReplayCompletionEvidence -Evidence $completionEvidence -Manifest $manifest -SubscriptionId $completionEvidence.subscriptionId
$incompleteEvidenceRejected = $false
$completionEvidence.pendingReplayRequestCount = 1
try { Assert-ReplayCompletionEvidence -Evidence $completionEvidence -Manifest $manifest -SubscriptionId $completionEvidence.subscriptionId } catch { $incompleteEvidenceRejected = $true }
Assert-True $incompleteEvidenceRejected 'normal restore refuses to resume publisher when requests remain pending'

$source = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\phase10-azure-replay-drill-config.ps1') -Raw
Assert-True ($source -match "MUTATE AZURE DEV REPLAY SETTINGS" -and $source -match 'if \(-not \$Execute\).*Read-only plan only') 'live writes are opt-in and read-only is the default'
Assert-True ($source -match 'ShouldProcess' -and $source -match 'Recovery manifest') 'mutation requires ShouldProcess and recovery evidence'
Write-Output 'Phase 10 Azure replay-drill config helper tests passed (9 assertions).'
