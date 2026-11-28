#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Plan', 'Apply')][string]$Mode = 'Plan',
    [Parameter(Mandatory)][guid]$ExpectedSubscriptionId,
    [Parameter(Mandatory)][guid]$ExpectedDirectoryId
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repoRoot = Split-Path -Parent $PSScriptRoot
$repo = 'pavanthakur/XYDataLabs.OrderProcessingSystem'
$groupName = 'rg-orderprocessing-dev'
$location = 'centralindia'
$subscription = $ExpectedSubscriptionId.ToString()
$scope = "/subscriptions/$subscription/resourceGroups/$groupName"
$roleId = 'f58310d9-a9f6-439a-9e8d-f62e7b41a168'
$report = [ordered]@{
    schemaVersion = 1; environment = 'dev'; mode = $Mode; status = 'BLOCKED'
    subscriptionId = $subscription; directoryId = $ExpectedDirectoryId.ToString()
    resourceGroup = $groupName; location = $location; scope = $scope
    bootstrapPrincipalId = $null; replayRunnerPrincipalId = $null
    role = 'Role Based Access Control Administrator'; conditionProfile = $null
    allowedDelegations = @(); plan = @(); completed = @(); mutationAttempted = $false
    stage = 'validate-target'; reason = $null
}

function Read-NativeJson {
    param([string]$Command, [string[]]$Arguments, [string]$InputJson)
    $raw = if ($PSBoundParameters.ContainsKey('InputJson')) { $InputJson | & $Command @Arguments 2>$null } else { & $Command @Arguments 2>$null }
    if ($LASTEXITCODE -ne 0 -or -not $raw) { throw 'Command failed or returned no data.' }
    return ,(ConvertFrom-Json -InputObject ($raw -join "`n") -AsHashtable -NoEnumerate)
}

function Get-DevVariables {
    $pages = Read-NativeJson gh @('api', '--hostname', 'github.com', "repos/$repo/environments/dev/variables?per_page=100", '--paginate', '--slurp')
    if ($pages -isnot [array] -or $pages.Count -eq 0) { throw 'Incomplete GitHub variable inventory.' }
    $entries = @(foreach ($page in $pages) {
        if ($page.variables -isnot [array] -or $page.total_count -ne $pages[0].total_count) { throw 'Invalid GitHub variable page.' }
        $page.variables
    })
    if ($entries.Count -ne $pages[0].total_count) { throw 'Incomplete GitHub variable inventory.' }
    $values = @{}
    foreach ($name in @('AZURE_RBAC_BOOTSTRAP_PRINCIPAL_OBJECT_ID', 'PHASE10_REPLAY_DRILL_RUNNER_PRINCIPAL_OBJECT_ID', 'ENTRA_DIRECTORY_ID')) {
        $matches = @($entries | Where-Object { $_.name -ceq $name })
        if ($matches.Count -gt 1) { throw 'Ambiguous GitHub variable inventory.' }
        if ($matches.Count -eq 1) {
            $value = [guid]::Empty
            if (-not [guid]::TryParseExact([string]$matches[0].value, 'D', [ref]$value) -or $value -eq [guid]::Empty) { throw 'Invalid dev identity variable.' }
            $values[$name] = $value.ToString()
        }
    }
    if (-not $values['AZURE_RBAC_BOOTSTRAP_PRINCIPAL_OBJECT_ID'] -or $values['ENTRA_DIRECTORY_ID'] -ne $ExpectedDirectoryId.ToString()) {
        throw 'GitHub dev directory or bootstrap principal is not configured as expected.'
    }
    return $values
}

function Read-Group {
    $exists = Read-NativeJson az @('group', 'exists', '--name', $groupName, '--subscription', $subscription, '--output', 'json', '--only-show-errors')
    if ($exists -isnot [bool]) { throw 'Invalid group existence result.' }
    if (-not $exists) { return $false }
    $group = Read-NativeJson az @('group', 'show', '--name', $groupName, '--subscription', $subscription, '--output', 'json', '--only-show-errors')
    if ($group.id -ne $scope -or $group.location -ne $location -or $group.tags.env -ne 'dev' -or $group.tags.app -ne 'orderprocessing') {
        throw 'Existing resource group does not match the dev foundation identity, location or tags.'
    }
    return $true
}

function Read-BootstrapGrant {
    $assignments = Read-NativeJson az @('role', 'assignment', 'list', '--scope', $scope, '--include-inherited', '--fill-principal-name', 'false', '--subscription', $subscription, '--output', 'json', '--only-show-errors')
    if ($assignments -isnot [array]) { throw 'Invalid role inventory.' }
    $adminGrants = @($assignments | Where-Object { ([string]$_.roleDefinitionId).Split('/')[-1] -eq $roleId })
    # Refuse competing direct bootstrap administrators and inherited administrator access for the pinned identity.
    $candidates = @($adminGrants | Where-Object { $_.scope -eq $scope -or $_.principalId -eq $principal })
    $report.directBootstrapAdminCount = @($adminGrants | Where-Object scope -eq $scope).Count
    if (@($candidates | Where-Object principalId -ne $principal).Count -gt 0) {
        $report.reason = 'Another principal has direct bootstrap administrator access at the dev group. Review the competing IAM grant separately; 00b will not remove it.'
        throw 'Competing bootstrap administrator assignment.'
    }
    if ($candidates.Count -eq 0) { return $false }
    $approved = $false
    if ($candidates.Count -eq 1 -and $candidates[0].principalType -eq 'ServicePrincipal') {
        # The role name is derived from the validated built-in definition ID, not a CLI display name.
        $candidate = $candidates[0]
        $payload = @{
            assignment = @{
                principalId = $candidate.principalId; scope = $candidate.scope; roleDefinitionName = $report.role
                condition = $candidate.condition; conditionVersion = $candidate.conditionVersion
            }
            expected = @{ principalId = $principal; scope = $scope; replayRunnerPrincipalId = $runner }
        }
        $approved = Read-NativeJson node @('--input-type=module', '-e',
            'import fs from "node:fs"; const {hasApprovedBootstrapAssignment}=await import(process.argv[1]); const {assignment,expected}=JSON.parse(fs.readFileSync(0,"utf8")); console.log(JSON.stringify(hasApprovedBootstrapAssignment([assignment],expected)));', $builder) ($payload | ConvertTo-Json -Depth 8 -Compress)
    }
    if ($approved -isnot [bool] -or -not $approved) {
        $report.reason = 'Conflicting bootstrap administrator assignment. Review the existing principals, scope and condition separately; 00b will not edit or remove grants.'
        throw 'Conflicting bootstrap administrator assignment.'
    }
    return $true
}

try {
    $target = @((Get-Content -LiteralPath (Join-Path $repoRoot 'automation/config/runtime-targets.json') -Raw | ConvertFrom-Json).targets |
        Where-Object key -eq 'azure-dev')
    if ($target.Count -ne 1 -or $target[0].azureResourceGroupName -cne $groupName -or
        $ExpectedSubscriptionId -eq [guid]::Empty -or $ExpectedDirectoryId -eq [guid]::Empty) {
        throw 'The approved dev target could not be resolved.'
    }
    $account = Read-NativeJson az @('account', 'show', '--output', 'json', '--only-show-errors')
    if ($account.id -ne $subscription -or $account.tenantId -ne $ExpectedDirectoryId.ToString() -or
        $account.state -ne 'Enabled' -or $account.user.type -ne 'user') {
        throw 'Use an authorized interactive Azure CLI user in the approved subscription and directory.'
    }
    $report.stage = 'verify-dev-identities'
    $variables = Get-DevVariables
    $principal = $variables['AZURE_RBAC_BOOTSTRAP_PRINCIPAL_OBJECT_ID']
    $runner = [string]$variables['PHASE10_REPLAY_DRILL_RUNNER_PRINCIPAL_OBJECT_ID']
    $report.bootstrapPrincipalId = $principal
    $report.replayRunnerPrincipalId = if ($runner) { $runner } else { $null }
    $sp = Read-NativeJson az @('rest', '--method', 'get', '--url', "https://graph.microsoft.com/v1.0/servicePrincipals/${principal}?`$select=id,accountEnabled,servicePrincipalType", '--output', 'json', '--only-show-errors')
    if ($sp.id -ne $principal -or $sp.accountEnabled -ne $true -or $sp.servicePrincipalType -ne 'Application') {
        throw 'Configured dev bootstrap principal is not an enabled application service principal.'
    }
    if ($runner) {
        $user = Read-NativeJson az @('rest', '--method', 'get', '--url', "https://graph.microsoft.com/v1.0/users/${runner}?`$select=id,accountEnabled,userType", '--output', 'json', '--only-show-errors')
        if ($user.id -ne $runner -or $user.accountEnabled -ne $true -or $user.userType -ne 'Member') {
            throw 'Configured replay runner is not an enabled dev Member.'
        }
    }
    $builder = ([uri](Join-Path $PSScriptRoot 'phase10-azure-rbac-bootstrap-preflight.mjs')).AbsoluteUri
    $conditionJson = Read-NativeJson node @('--input-type=module', '-e',
        'const {buildBootstrapCondition}=await import(process.argv[1]); console.log(JSON.stringify(buildBootstrapCondition(process.argv[2])));', $builder, $runner)
    if ($conditionJson -isnot [string] -or -not $conditionJson) { throw 'Could not generate the canonical bootstrap condition.' }
    $condition = $conditionJson
    $report.conditionProfile = if ($runner) { 'storage-and-pinned-dev-replay' } else { 'storage-only' }
    $report.allowedDelegations = @('Storage Blob Data Owner for service principals')
    if ($runner) { $report.allowedDelegations += 'Service Bus Data Receiver and Data Sender for the pinned dev user' }

    $report.stage = 'inspect-foundation'
    $groupExists = Read-Group
    $grantExists = $groupExists -and (Read-BootstrapGrant)
    if (-not $groupExists) { $report.plan += 'create-dev-resource-group' }
    if (-not $grantExists) { $report.plan += 'create-constrained-bootstrap-assignment' }
    if ($report.plan.Count -eq 0) { $report.plan += 'no-change' }

    if ($Mode -eq 'Apply' -and -not $grantExists) {
        $report.stage = 'confirm-apply'
        Write-Host ($report | ConvertTo-Json -Depth 8)
        if ($PSCmdlet.ShouldProcess($scope, ($report.plan -join ', '))) {
            if ((Read-Host 'Type APPLY DEV FOUNDATION to authorize the listed actions') -cne 'APPLY DEV FOUNDATION') {
                throw 'Approval phrase not received; no change made.'
            }
            $report.stage = 'recheck-before-write'
            $currentVariables = Get-DevVariables
            if ($currentVariables['AZURE_RBAC_BOOTSTRAP_PRINCIPAL_OBJECT_ID'] -ne $principal -or
                [string]$currentVariables['PHASE10_REPLAY_DRILL_RUNNER_PRINCIPAL_OBJECT_ID'] -ne $runner -or
                (Read-Group) -ne $groupExists -or ($groupExists -and (Read-BootstrapGrant))) {
                throw 'Foundation or GitHub configuration changed since preview; rerun Plan.'
            }
            if (-not $groupExists) {
                $report.stage = 'create-dev-resource-group'
                $report.mutationAttempted = $true
                $null = Read-NativeJson az @('group', 'create', '--name', $groupName, '--location', $location,
                    '--tags', 'env=dev', 'app=orderprocessing', '--subscription', $subscription, '--output', 'json', '--only-show-errors')
                if (-not (Read-Group)) { throw 'Group creation was not verified.' }
                $report.completed += 'dev-resource-group-verified'
                if (Read-BootstrapGrant) { throw 'An assignment appeared concurrently; rerun Plan.' }
            }
            $report.stage = 'create-constrained-bootstrap-assignment'
            $report.mutationAttempted = $true
            $null = Read-NativeJson az @('role', 'assignment', 'create', '--role', $roleId, '--assignee-object-id', $principal,
                '--assignee-principal-type', 'ServicePrincipal', '--scope', $scope, '--condition', $condition,
                '--condition-version', '2.0', '--subscription', $subscription, '--output', 'json', '--only-show-errors')
            $report.stage = 'verify-assignment'
            if (-not (Read-BootstrapGrant)) { throw 'Assignment was not verified.' }
            $report.completed += 'constrained-bootstrap-assignment-verified'
        } else {
            # WhatIf and declined confirmation describe the plan, not a successful Apply.
            throw 'Apply was not confirmed; no change made.'
        }
    }
    $report.status = 'PASS'
    $report.stage = 'complete'
} catch {
    $report.status = if ($report.mutationAttempted) { 'FAIL' } else { 'BLOCKED' }
    $report.reason = if ($report.mutationAttempted) {
        'Write or read-back failed. The outcome may be partial; inspect the reported stage and run Plan before retrying. Nothing was rolled back.'
    } elseif ($report.reason) {
        $report.reason
    } else {
        'Read-only validation or confirmation failed at the reported stage. No write was attempted.'
    }
} finally {
    $report | ConvertTo-Json -Depth 8
}
if ($report.status -ne 'PASS') { throw "00b foundation bootstrap ${Mode}: $($report.status) at $($report.stage)." }
