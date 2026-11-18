$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../phase10-run-id.ps1')

$valid = Resolve-Phase10DockerE2ERunId -RunId 'phase10-docker-http-20261117-132501007'
if ($valid -cne 'phase10-docker-http-20261117-132501007') { throw 'Valid canonical run ID changed unexpectedly.' }
$generated = Resolve-Phase10DockerE2ERunId
if ($generated -notmatch '^phase10-docker-http-\d{8}-\d{9}$') { throw 'Generated run ID is not canonical.' }
$workflowId = 'phase10-docker-dev-http-123456789-2'
if ((Resolve-Phase10DockerE2ERunId -RunId $workflowId) -cne $workflowId) { throw 'Workflow 99 packet ID changed unexpectedly.' }

foreach ($invalid in @('bad-run', '../phase10-docker-http-20261117-132501007', 'phase10-docker-http-20261317-132501007', 'phase10-docker-http-20261117-13250100x', 'phase10-docker-dev-http-123456789-2/../other')) {
    $rejected = $false
    try { Resolve-Phase10DockerE2ERunId -RunId $invalid | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw "Malformed run ID was accepted: $invalid" }
}
Write-Host 'PASS canonical run IDs accept valid timestamps and reject malformed/path-like values.'
