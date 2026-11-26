$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot '..\phase10-entra-replay-approver.module.psm1'
Import-Module $modulePath -Force
$roleScript = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\phase10-entra-replay-approver.ps1') -Raw

function Assert-True([bool]$Value, [string]$Message) { if (-not $Value) { throw "FAILED: $Message" } }
function Assert-Throws([scriptblock]$Action, [string]$Message) {
    try { & $Action; throw "FAILED: expected rejection: $Message" }
    catch { if ($_.Exception.Message -like 'FAILED:*') { throw }; Write-Host "PASS: $Message" }
}

$directory = [guid]'2fc13fdf-ddcb-4adb-91d4-58f1632a1c6f'
$subscription = [guid]'19f22d2f-1557-479b-a9b7-6dc6af67980c'
$api = [guid]'d0c92063-4ac8-4af9-9367-c937634c3d44'
$approver = [guid]'22222222-2222-4222-8222-222222222222'
$runner = [guid]'33333333-3333-4333-8333-333333333333'
$testA = [guid]'44444444-4444-4444-8444-444444444444'
$input = [pscustomobject]@{
    schemaVersion=1; environment='dev'; identityType='replay-approver'; directoryId=$directory.ToString('D')
    subscriptionId=$subscription.ToString('D'); apiClientId=$api.ToString('D'); approverObjectId=$approver.ToString('D')
    replayRunnerObjectId=$runner.ToString('D'); tenantCode='TenantA'; tenantTestUserObjectIds=@($testA.ToString('D'))
}
$manifest = ConvertTo-Phase10ReplayApproverManifest -InputObject $input -ExpectedDirectoryId $directory -ExpectedSubscriptionId $subscription
Assert-True ($manifest.approverObjectId -eq $approver.ToString('D')) 'valid pinned approver manifest is normalized'
Assert-Throws { ConvertTo-Phase10ReplayApproverManifest -InputObject $input -ExpectedDirectoryId ([guid]::NewGuid()) -ExpectedSubscriptionId $subscription } 'wrong directory is rejected'
Assert-Throws { ConvertTo-Phase10ReplayApproverManifest -InputObject $input -ExpectedDirectoryId $directory -ExpectedSubscriptionId ([guid]::NewGuid()) } 'wrong subscription is rejected'
$runnerReuse = $input | Select-Object *; $runnerReuse.approverObjectId=$runner.ToString('D')
Assert-Throws { ConvertTo-Phase10ReplayApproverManifest -InputObject $runnerReuse -ExpectedDirectoryId $directory -ExpectedSubscriptionId $subscription } 'runner cannot also be approver'
$testReuse = $input | Select-Object *; $testReuse.approverObjectId=$testA.ToString('D')
Assert-Throws { ConvertTo-Phase10ReplayApproverManifest -InputObject $testReuse -ExpectedDirectoryId $directory -ExpectedSubscriptionId $subscription } 'tenant test account cannot also be approver'

$user = [pscustomobject]@{ id=$approver.ToString('D'); userType='Member'; accountEnabled=$true }
$assignments = @()
$plan = New-Phase10ReplayApproverPlan -Manifest $manifest -Approver $user -TenantClaimValue 'TenantA' -ApiRoleAssignments $assignments -HasSubscriptionOwner $false
Assert-True ($plan.action -eq 'assign-phase10-operator') 'plan adds only the required API role'
Assert-Throws { New-Phase10ReplayApproverPlan -Manifest $manifest -Approver $user -TenantClaimValue 'TenantB' -ApiRoleAssignments $assignments -HasSubscriptionOwner $false } 'conflicting tenant claim is rejected'
Assert-Throws { New-Phase10ReplayApproverPlan -Manifest $manifest -Approver $user -TenantClaimValue 'TenantA' -ApiRoleAssignments $assignments -HasSubscriptionOwner $true } 'subscription Owner is rejected'
$guest = [pscustomobject]@{ id=$approver.ToString('D'); userType='Guest'; accountEnabled=$true }
Assert-Throws { New-Phase10ReplayApproverPlan -Manifest $manifest -Approver $guest -TenantClaimValue 'TenantA' -ApiRoleAssignments $assignments -HasSubscriptionOwner $false } 'guest account is rejected'
$disabled = [pscustomobject]@{ id=$approver.ToString('D'); userType='Member'; accountEnabled=$false }
Assert-Throws { New-Phase10ReplayApproverPlan -Manifest $manifest -Approver $disabled -TenantClaimValue 'TenantA' -ApiRoleAssignments $assignments -HasSubscriptionOwner $false } 'disabled account is rejected'
$platformAdmin = @([pscustomobject]@{principalId=$approver.ToString('D');principalType='User';roleValue='platform-admin'})
Assert-Throws { New-Phase10ReplayApproverPlan -Manifest $manifest -Approver $user -TenantClaimValue 'TenantA' -ApiRoleAssignments $platformAdmin -HasSubscriptionOwner $false } 'platform-admin account is rejected'
$groupRole = @([pscustomobject]@{principalId='55555555-5555-4555-8555-555555555555';principalType='Group';roleValue='phase10-operator'})
Assert-Throws { New-Phase10ReplayApproverPlan -Manifest $manifest -Approver $user -TenantClaimValue 'TenantA' -ApiRoleAssignments $groupRole -HasSubscriptionOwner $false } 'group-inherited operator role is rejected'
$directRole = @([pscustomobject]@{principalId=$approver.ToString('D');principalType='User';roleValue='phase10-operator'})
$verified = New-Phase10ReplayApproverPlan -Manifest $manifest -Approver $user -TenantClaimValue 'TenantA' -ApiRoleAssignments $directRole -HasSubscriptionOwner $false
Assert-True ($verified.action -eq 'no-change' -and $verified.status -eq 'verified') 'existing direct role is verified without another assignment'
Assert-True ([regex]::Matches($roleScript, 'Set-Content -LiteralPath \$reportPath -Encoding utf8NoBOM -Confirm:\$false').Count -ge 2) 'sanitized report writes do not trigger a redundant Apply confirmation'

Write-Host 'Phase 10 Entra replay approver tests passed.'
