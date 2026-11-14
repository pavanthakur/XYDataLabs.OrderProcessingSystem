$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'phase10-azure-firewall-lease.ps1')
$script:rules = @{}
$script:createMode = 'success'
$script:deleteMode = 'success'
$script:lookupMode = 'success'

function Invoke-MockAz {
    param([string[]]$Arguments)
    $verb = $Arguments[3]
    $name = $Arguments[($Arguments.IndexOf('--name') + 1)]
    switch ($verb) {
        'show' {
            if ($script:lookupMode -eq 'error') { $global:LASTEXITCODE = 1; return 'AuthorizationFailed' }
            if (-not $script:rules.ContainsKey($name)) { $global:LASTEXITCODE = 1; return 'ResourceNotFound' }
            $global:LASTEXITCODE = 0
            return ($script:rules[$name] | ConvertTo-Json -Compress)
        }
        'create' {
            if ($script:createMode -eq 'fail-before') { $global:LASTEXITCODE = 1; return 'simulated error' }
            $ip = $Arguments[($Arguments.IndexOf('--start-ip-address') + 1)]
            $script:rules[$name] = [pscustomobject]@{ name = $name; startIpAddress = $ip; endIpAddress = $ip }
            if ($script:createMode -eq 'ambiguous') { $global:LASTEXITCODE = 1; return 'timeout' }
            $global:LASTEXITCODE = 0
            return 'created'
        }
        'delete' {
            if ($script:deleteMode -eq 'fail') { $global:LASTEXITCODE = 1; return 'simulated delete failure' }
            $script:rules.Remove($name) | Out-Null
            $global:LASTEXITCODE = 0
            return 'deleted'
        }
        default { throw "Unexpected mocked az operation '$verb'." }
    }
}

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) "phase10-firewall-tests-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    $manifest = Join-Path $testRoot 'lease.json'
    $lease = New-Phase10FirewallLease -Environment dev -SubscriptionId sub-test -ResourceGroup rg-dev -Server sql-dev -PublicIp 203.0.113.4 -RunId 123 -Attempt 1 -InvocationId abc -ManifestPath $manifest -InvokeAz ${function:Invoke-MockAz}
    Assert-True ($script:rules.ContainsKey($lease.RuleName)) 'Lease creation did not create the owned rule.'
    $manifestRecord = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    Assert-True ($manifestRecord.subscriptionId -eq 'sub-test') 'Lease manifest omitted its Azure subscription binding.'
    Remove-Phase10FirewallLease -ManifestPath $manifest -InvokeAz ${function:Invoke-MockAz}
    Assert-True (-not $script:rules.ContainsKey($lease.RuleName)) 'Lease cleanup left the owned rule behind.'
    Remove-Phase10FirewallLease -ManifestPath $manifest -InvokeAz ${function:Invoke-MockAz}

    $script:createMode = 'ambiguous'
    $ambiguousManifest = Join-Path $testRoot 'ambiguous.json'
    $ambiguous = New-Phase10FirewallLease -Environment dev -SubscriptionId sub-test -ResourceGroup rg-dev -Server sql-dev -PublicIp 203.0.113.5 -RunId 124 -Attempt 1 -InvocationId def -ManifestPath $ambiguousManifest -InvokeAz ${function:Invoke-MockAz}
    Remove-Phase10FirewallLease -ManifestPath $ambiguousManifest -InvokeAz ${function:Invoke-MockAz}
    Assert-True (-not $script:rules.ContainsKey($ambiguous.RuleName)) 'Ambiguous create was not reconciled and cleaned.'

    $script:createMode = 'success'
    $collisionName = Get-Phase10FirewallRuleName -Environment dev -RunId 125 -Attempt 1 -InvocationId ghi
    $script:rules[$collisionName] = [pscustomobject]@{ name = $collisionName; startIpAddress = '198.51.100.2'; endIpAddress = '198.51.100.2' }
    $collisionManifest = Join-Path $testRoot 'collision.json'
    $collisionFailed = $false
    try { New-Phase10FirewallLease -Environment dev -SubscriptionId sub-test -ResourceGroup rg-dev -Server sql-dev -PublicIp 203.0.113.6 -RunId 125 -Attempt 1 -InvocationId ghi -ManifestPath $collisionManifest -InvokeAz ${function:Invoke-MockAz} | Out-Null } catch { $collisionFailed = $true }
    Assert-True $collisionFailed 'Existing rule collision was not rejected.'
    Assert-True ($script:rules[$collisionName].startIpAddress -eq '198.51.100.2') 'Collision handling modified a pre-existing rule.'

    $script:createMode = 'fail-before'
    $failureManifest = Join-Path $testRoot 'failed-create.json'
    $creationFailed = $false
    try { New-Phase10FirewallLease -Environment dev -SubscriptionId sub-test -ResourceGroup rg-dev -Server sql-dev -PublicIp 203.0.113.7 -RunId 126 -Attempt 1 -InvocationId jkl -ManifestPath $failureManifest -InvokeAz ${function:Invoke-MockAz} | Out-Null } catch { $creationFailed = $true }
    Assert-True $creationFailed 'Failed create did not stop the operation.'

    $script:createMode = 'success'
    $ownedManifest = Join-Path $testRoot 'owned.json'
    $owned = New-Phase10FirewallLease -Environment dev -SubscriptionId sub-test -ResourceGroup rg-dev -Server sql-dev -PublicIp 203.0.113.8 -RunId 127 -Attempt 1 -InvocationId mno -ManifestPath $ownedManifest -InvokeAz ${function:Invoke-MockAz}
    $script:rules[$owned.RuleName] = [pscustomobject]@{ name = $owned.RuleName; startIpAddress = '203.0.113.99'; endIpAddress = '203.0.113.99' }
    $mismatchFailed = $false
    try { Remove-Phase10FirewallLease -ManifestPath $ownedManifest -InvokeAz ${function:Invoke-MockAz} } catch { $mismatchFailed = $true }
    Assert-True $mismatchFailed 'Changed firewall rule was not rejected during cleanup.'
    Assert-True ($script:rules.ContainsKey($owned.RuleName)) 'Mismatched rule was deleted despite ownership mismatch.'

    $script:rules[$owned.RuleName] = [pscustomobject]@{ name = $owned.RuleName; startIpAddress = '203.0.113.8'; endIpAddress = '203.0.113.8' }
    $script:deleteMode = 'fail'
    $deleteFailed = $false
    try { Remove-Phase10FirewallLease -ManifestPath $ownedManifest -InvokeAz ${function:Invoke-MockAz} -MaxAttempts 1 } catch { $deleteFailed = $true }
    Assert-True $deleteFailed 'Cleanup failure was incorrectly treated as success.'
    $pending = Get-Content -LiteralPath $ownedManifest -Raw | ConvertFrom-Json
    Assert-True ($pending.state -eq 'cleanup-pending') 'Failed cleanup did not preserve a recovery manifest.'

    $script:deleteMode = 'success'
    $script:lookupMode = 'error'
    $unknownFailed = $false
    try { Remove-Phase10FirewallLease -ManifestPath $ownedManifest -InvokeAz ${function:Invoke-MockAz} -MaxAttempts 1 } catch { $unknownFailed = $true }
    Assert-True $unknownFailed 'Unknown Azure state was not treated as a failure.'
    Assert-True ($script:rules.ContainsKey($owned.RuleName)) 'Unknown-state handling deleted an unverified rule.'

    $transportScript = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'run-phase10-azure-transport-smoke.ps1') -Raw
    $programSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\tools\Phase10.TransportSmoke\Program.cs') -Raw
    Assert-True ($transportScript -notmatch "'--connection-string'\s*,\s*\x24ConnectionString") 'Transport script still puts the Service Bus secret on the command line.'
    Assert-True ($programSource -match 'PHASE10_TRANSPORT_SERVICEBUS_CONNECTION_STRING') 'Transport tool does not read the Service Bus secret from the environment.'
    $cleanupScript = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'cleanup-phase10-azure-firewall-lease.ps1') -Raw
    Assert-True ($cleanupScript -match 'activeSubscription.*manifest\.subscriptionId') 'Recovery script does not bind cleanup to the active Azure subscription.'

    Write-Output 'PASS: firewall lease ownership, ambiguous creation, collision/mismatch refusal, unknown-state failure, cleanup recovery, idempotency and secret-argument contract.'
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
