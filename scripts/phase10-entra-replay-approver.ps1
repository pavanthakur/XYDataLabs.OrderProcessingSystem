#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = 'ExplicitSubscription')]
param(
    [ValidateSet('Plan','Apply','Verify')][string]$Mode = 'Plan',
    [string]$ManifestPath = (Join-Path $env:LOCALAPPDATA 'XYDataLabs/phase10-replay-approver/phase10-replay-approver.dev.json'),
    [Parameter(Mandatory,ParameterSetName='ExplicitSubscription')][guid]$ExpectedSubscriptionId,
    [Parameter(Mandatory,ParameterSetName='PromptSubscription')][switch]$PromptForExpectedSubscriptionId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'phase10-entra-replay-approver.module.psm1') -Force

function Invoke-AzJson {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $output = & az @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Azure CLI request failed; command output is suppressed.' }
    return (@($output | ForEach-Object { [string]$_ }) -join "`n") | ConvertFrom-Json
}

function Invoke-Graph {
    param([Parameter(Mandatory)][ValidateSet('GET','POST')][string]$Method,
          [Parameter(Mandatory)][string]$Uri, [object]$Body)
    $headers = @{ Authorization = "Bearer $script:graphAccessToken" }
    try {
        if ($null -eq $Body) { return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -TimeoutSec 30 }
        $json = ConvertTo-Json -InputObject $Body -Depth 8 -Compress
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -ContentType 'application/json' -Body $json -TimeoutSec 30
    }
    catch { throw "Microsoft Graph $Method request failed; response details are suppressed." }
}

function Get-GraphItems {
    param([Parameter(Mandatory)][string]$Uri)
    $items = @(); $next = $Uri
    while ($next) {
        $page = Invoke-Graph -Method GET -Uri $next
        if ($null -eq $page.value) { throw 'Microsoft Graph returned an invalid collection.' }
        $items += @($page.value)
        $linkProperty = $page.PSObject.Properties['@odata.nextLink']
        $next = if ($null -eq $linkProperty) { $null } else { [string]$linkProperty.Value }
    }
    return $items
}

if (-not $IsWindows -or -not [Environment]::UserInteractive) { throw 'Run this operator in an interactive Windows PowerShell 7 session.' }
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI is required; no Graph request was made.' }
$manifestFullPath = [IO.Path]::GetFullPath($ManifestPath)
$repoPrefix = [IO.Path]::GetFullPath($repoRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$privateDirectory = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'XYDataLabs/phase10-replay-approver')).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($manifestFullPath.StartsWith($repoPrefix,[StringComparison]::OrdinalIgnoreCase) -or
    -not $manifestFullPath.StartsWith($privateDirectory,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'Keep the approver manifest only in its dedicated per-user LocalAppData directory, outside the repository.'
}
if (-not (Test-Path -LiteralPath $manifestFullPath -PathType Leaf)) { throw 'Private replay-approver manifest is missing.' }

$account = Invoke-AzJson @('account','show','--query','{id:id,tenantId:tenantId,state:state}','-o','json')
if ($PromptForExpectedSubscriptionId) {
    Write-Host "Active Azure CLI subscription ID: $($account.id)"
    $answer = Read-Host 'Verify the ID above against the approved Azure-dev subscription GUID, then paste the approved GUID here (blank cancels)'
    if ([string]::IsNullOrWhiteSpace($answer) -or [guid]$answer.Trim() -ne [guid]$account.id) { throw 'Subscription confirmation failed; no Graph request was made.' }
    $ExpectedSubscriptionId = [guid]$account.id
}
if ($account.state -ne 'Enabled' -or [guid]$account.id -ne $ExpectedSubscriptionId) { throw 'Active Azure CLI subscription does not match the explicitly approved Azure-dev subscription.' }
$inputManifest = Get-Content -LiteralPath $manifestFullPath -Raw | ConvertFrom-Json
$manifest = ConvertTo-Phase10ReplayApproverManifest -InputObject $inputManifest -ExpectedDirectoryId ([guid]$account.tenantId) -ExpectedSubscriptionId $ExpectedSubscriptionId

$graphTokenOutput = & az account get-access-token --resource-type ms-graph --query accessToken -o tsv 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$graphTokenOutput)) { throw 'Could not acquire the interactive Microsoft Graph token; no directory changes were made.' }
$script:graphAccessToken = ([string]$graphTokenOutput).Trim(); $graphTokenOutput = $null
$stage = 'validate-graph-token'
$tokenPayload = $script:graphAccessToken.Split('.')[1].Replace('-','+').Replace('_','/')
if ($tokenPayload.Length % 4) { $tokenPayload += '=' * (4 - ($tokenPayload.Length % 4)) }
$tokenClaims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($tokenPayload)) | ConvertFrom-Json
$graphGrants = @()
$scopeClaim = $tokenClaims.PSObject.Properties['scp']
if ($null -ne $scopeClaim -and -not [string]::IsNullOrWhiteSpace([string]$scopeClaim.Value)) { $graphGrants += ([string]$scopeClaim.Value -split ' ') }
$rolesClaim = $tokenClaims.PSObject.Properties['roles']
if ($null -ne $rolesClaim) { $graphGrants += @($rolesClaim.Value | ForEach-Object { [string]$_ }) }
if ($Mode -eq 'Apply' -and 'AppRoleAssignment.ReadWrite.All' -notin $graphGrants) { throw 'The interactive Graph token lacks AppRoleAssignment.ReadWrite.All; no directory writes were made.' }
$reportRoot = Join-Path $repoRoot ('TestResults/Phase10/entra-replay-approver/' + (Get-Date -AsUTC -Format 'yyyyMMddTHHmmssZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
[void][IO.Directory]::CreateDirectory($reportRoot)
$reportPath = Join-Path $reportRoot 'assignment-summary.json'
$stage = 'preflight'
try {
    $ownerAssignments = Invoke-AzJson @('role','assignment','list','--subscription',$ExpectedSubscriptionId.ToString('D'),'--assignee-object-id',$manifest.approverObjectId,'--include-inherited','--fill-principal-name','false','--query','[].{role:roleDefinitionName}','-o','json')
    $hasOwner = @($ownerAssignments | Where-Object { $_.role -eq 'Owner' }).Count -gt 0

    $apiApps = @(Get-GraphItems -Uri "https://graph.microsoft.com/v1.0/applications?`$filter=appId eq '$($manifest.apiClientId)'&`$select=id,appId")
    if ($apiApps.Count -ne 1) { throw 'Expected exactly one API application registration in the approved Entra directory.' }
    $apiSpRows = @(Get-GraphItems -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$($manifest.apiClientId)'&`$select=id,appId,appRoles")
    if ($apiSpRows.Count -ne 1) { throw 'Expected exactly one API service principal in the approved Entra directory.' }
    $apiSp = $apiSpRows[0]
    $operatorRoles = @($apiSp.appRoles | Where-Object { $_.isEnabled -eq $true -and $_.value -ceq 'phase10-operator' })
    if ($operatorRoles.Count -ne 1 -or $operatorRoles[0].allowedMemberTypes -notcontains 'User') { throw 'API must define one enabled phase10-operator user app role.' }
    $roleById = @{}; foreach ($role in @($apiSp.appRoles | Where-Object isEnabled)) { $roleById[[string]$role.id] = [string]$role.value }
    $allAssignments = @(Get-GraphItems -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($apiSp.id)/appRoleAssignedTo?`$select=principalId,principalType,appRoleId")
    $privilegedGroupAssignments = @($allAssignments | Where-Object {
        $_.principalType -eq 'Group' -and $roleById.ContainsKey([string]$_.appRoleId) -and $roleById[[string]$_.appRoleId] -in @('platform-admin','phase10-operator')
    })
    if ($privilegedGroupAssignments.Count -gt 0) { throw 'A privileged API role is assigned to a group; review group membership before provisioning a direct approver.' }

    $extensionName = "extension_$($manifest.apiClientId.Replace('-',''))_applicationTenantCode"
    $approver = Invoke-Graph -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$($manifest.approverObjectId)?`$select=id,userType,accountEnabled,$extensionName"
    $approverAssignments = @($allAssignments | Where-Object { $_.principalType -eq 'User' -and [string]$_.principalId -eq $manifest.approverObjectId } | ForEach-Object {
        [pscustomobject]@{ principalId=[string]$_.principalId; principalType='User'; roleValue=$roleById[[string]$_.appRoleId] }
    })
    $plan = New-Phase10ReplayApproverPlan -Manifest $manifest -Approver $approver -TenantClaimValue ([string]$approver.$extensionName) -ApiRoleAssignments $approverAssignments -HasSubscriptionOwner $hasOwner

    if ($Mode -eq 'Apply') {
        if (-not $PSBoundParameters.ContainsKey('Confirm')) { throw 'Apply requires the explicit -Confirm switch.' }
        $phrase = Read-Host 'This grants only the dev API phase10-operator role to the pinned human approver. Type ASSIGN DEV PHASE10 OPERATOR to continue'
        if ($phrase -cne 'ASSIGN DEV PHASE10 OPERATOR') { throw 'Apply cancelled; no directory changes were made.' }
        if ($plan.action -eq 'assign-phase10-operator') {
            if (-not $PSCmdlet.ShouldProcess('Pinned non-Owner human approver','Assign API app role phase10-operator')) { throw 'Apply stopped by ShouldProcess; no role assignment was made.' }
            $stage = 'assign-api-role'
            $body = @{ principalId=$manifest.approverObjectId; resourceId=[string]$apiSp.id; appRoleId=[string]$operatorRoles[0].id }
            [void](Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$($manifest.approverObjectId)/appRoleAssignments" -Body $body)
            $allAssignments = @(Get-GraphItems -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($apiSp.id)/appRoleAssignedTo?`$select=principalId,principalType,appRoleId")
            if (@($allAssignments | Where-Object { $_.principalType -eq 'User' -and $_.principalId -eq $manifest.approverObjectId -and $_.appRoleId -eq $operatorRoles[0].id }).Count -ne 1) {
                throw 'Post-write verification failed; inspect Entra state before retrying.'
            }
        }
    }
    if ($Mode -eq 'Verify' -and $plan.action -ne 'no-change') { throw 'The pinned human approver does not have the direct phase10-operator role assignment.' }
    $status = if ($Mode -eq 'Verify' -or $Mode -eq 'Apply') { 'passed' } else { [string]$plan.status }
    $assignmentVerified = ($plan.action -eq 'no-change' -or ($Mode -eq 'Apply' -and $stage -eq 'assign-api-role'))
    $summary = [ordered]@{ schema='phase10-entra-replay-approver-v1'; mode=$Mode.ToLowerInvariant(); status=$status; environment='dev'; tenantCode=$manifest.tenantCode; role='phase10-operator'; action=$plan.action; statusDetail=$status; directUserAssignment=$assignmentVerified; hasSubscriptionOwner=$false; privilegedRoleGroupAssignments=0; objectIdsRecorded=$false; upnsRecorded=$false; credentialsRecorded=$false }
    $summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM -Confirm:$false
    [pscustomobject]@{tenantCode=$manifest.tenantCode;role='phase10-operator';action=$plan.action;status=$status} | Format-Table -AutoSize
    Write-Host "Sanitized report: $reportPath"
}
catch {
    [ordered]@{schema='phase10-entra-replay-approver-v1';mode=$Mode.ToLowerInvariant();status='failed-or-verify-required';environment='dev';tenantCode=$manifest.tenantCode;role='phase10-operator';action=$stage;objectIdsRecorded=$false;upnsRecorded=$false;credentialsRecorded=$false;error='Operation stopped. Inspect Entra and the sanitized report before retrying.'} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM -Confirm:$false
    Write-Host "Sanitized report: $reportPath"
    throw 'Replay approver provisioning stopped; inspect Entra and the sanitized report before retrying.'
}
finally { $script:graphAccessToken = $null; $tokenClaims=$null; $tokenPayload=$null; $graphGrants=$null }
