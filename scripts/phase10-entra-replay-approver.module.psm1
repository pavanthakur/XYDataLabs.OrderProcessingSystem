Set-StrictMode -Version Latest

function ConvertTo-Phase10ReplayApproverManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$InputObject,
        [Parameter(Mandatory)][guid]$ExpectedDirectoryId,
        [Parameter(Mandatory)][guid]$ExpectedSubscriptionId
    )

    if ($InputObject.schemaVersion -ne 1 -or $InputObject.environment -cne 'dev' -or $InputObject.identityType -cne 'replay-approver') {
        throw 'Manifest must use schemaVersion 1, environment dev, and identityType replay-approver.'
    }
    $directoryId = [guid]::Empty
    $subscriptionId = [guid]::Empty
    $apiClientId = [guid]::Empty
    $approverObjectId = [guid]::Empty
    $runnerObjectId = [guid]::Empty
    if (-not [guid]::TryParse([string]$InputObject.directoryId, [ref]$directoryId) -or $directoryId -ne $ExpectedDirectoryId) {
        throw 'Manifest directoryId does not match the explicitly confirmed Entra directory.'
    }
    if (-not [guid]::TryParse([string]$InputObject.subscriptionId, [ref]$subscriptionId) -or $subscriptionId -ne $ExpectedSubscriptionId) {
        throw 'Manifest subscriptionId does not match the explicitly confirmed Azure-dev subscription.'
    }
    if (-not [guid]::TryParse([string]$InputObject.apiClientId, [ref]$apiClientId) -or
        -not [guid]::TryParse([string]$InputObject.approverObjectId, [ref]$approverObjectId) -or
        -not [guid]::TryParse([string]$InputObject.replayRunnerObjectId, [ref]$runnerObjectId)) {
        throw 'Manifest API, approver, and replay-runner IDs must be valid GUIDs.'
    }
    $tenantCode = ([string]$InputObject.tenantCode).Trim()
    if ($tenantCode -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$') { throw 'Manifest tenantCode is invalid.' }
    $testUserIds = @()
    foreach ($rawId in @($InputObject.tenantTestUserObjectIds)) {
        $testUserId = [guid]::Empty
        if (-not [guid]::TryParse([string]$rawId, [ref]$testUserId)) { throw 'Manifest contains an invalid tenant-test-user object ID.' }
        $testUserIds += $testUserId.ToString('D')
    }
    $approverId = $approverObjectId.ToString('D')
    if ($approverId -eq $runnerObjectId.ToString('D') -or $approverId -in $testUserIds) {
        throw 'Approver must be distinct from the replay runner and every tenant test user.'
    }
    return [pscustomobject]@{
        schemaVersion = 1; environment = 'dev'; identityType = 'replay-approver'
        directoryId = $directoryId.ToString('D'); subscriptionId = $subscriptionId.ToString('D')
        apiClientId = $apiClientId.ToString('D'); approverObjectId = $approverId
        replayRunnerObjectId = $runnerObjectId.ToString('D'); tenantCode = $tenantCode
        tenantTestUserObjectIds = @($testUserIds | Sort-Object -Unique)
    }
}

function New-Phase10ReplayApproverPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Manifest,
        [Parameter(Mandatory)][object]$Approver,
        [Parameter(Mandatory)][string]$TenantClaimValue,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$ApiRoleAssignments,
        [Parameter(Mandatory)][bool]$HasSubscriptionOwner
    )

    if ([string]$Approver.id -cne [string]$Manifest.approverObjectId) { throw 'Resolved approver does not match the pinned manifest object ID.' }
    if ([string]$Approver.userType -cne 'Member' -or $Approver.accountEnabled -ne $true) {
        throw 'Replay approver must be an enabled organizational Member; guests and disabled users are not accepted.'
    }
    if ($HasSubscriptionOwner) { throw 'Replay approver has Azure subscription Owner access; choose a non-Owner human approver.' }
    if ([string]$TenantClaimValue -cne [string]$Manifest.tenantCode) { throw 'Replay approver API tenant claim does not match the single tenant in the private manifest.' }
    $roles = @($ApiRoleAssignments | ForEach-Object { [string]$_.roleValue })
    if ($roles -contains 'platform-admin') { throw 'Replay approver has platform-admin; use a dedicated least-privileged approver identity.' }
    if ($roles -contains 'phase10-operator' -and @($ApiRoleAssignments | Where-Object { $_.roleValue -eq 'phase10-operator' -and $_.principalType -eq 'User' -and [string]$_.principalId -eq [string]$Manifest.approverObjectId }).Count -eq 0) {
        throw 'phase10-operator is inherited from a group; direct user assignment is required for auditable least-privilege provisioning.'
    }
    $hasDirectRole = @($ApiRoleAssignments | Where-Object {
        $_.roleValue -eq 'phase10-operator' -and $_.principalType -eq 'User' -and [string]$_.principalId -eq [string]$Manifest.approverObjectId
    }).Count -gt 0
    return [pscustomobject]@{
        tenantCode = [string]$Manifest.tenantCode
        action = if ($hasDirectRole) { 'no-change' } else { 'assign-phase10-operator' }
        status = if ($hasDirectRole) { 'verified' } else { 'planned' }
        role = 'phase10-operator'
    }
}

Export-ModuleMember -Function ConvertTo-Phase10ReplayApproverManifest, New-Phase10ReplayApproverPlan
