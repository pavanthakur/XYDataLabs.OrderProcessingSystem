#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = 'ExplicitSubscription')]
param(
    [ValidateSet('Plan','Apply','Verify','ResendInvitations','CreateRedemptionLink')][string]$Mode = 'Plan',
    [string]$TenantCode,
    [string]$ManifestPath = (Join-Path $env:LOCALAPPDATA 'XYDataLabs/phase10-entra-test-users.dev.json'),
    [guid]$ExpectedDirectoryId = [guid]::Empty,
    [Parameter(Mandatory,ParameterSetName='ExplicitSubscription')][guid]$ExpectedSubscriptionId,
    [Parameter(Mandatory,ParameterSetName='PromptSubscription')][switch]$PromptForExpectedSubscriptionId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'phase10-entra-test-users.module.psm1') -Force

$azLauncher = Get-Command az -ErrorAction Stop
if ($IsWindows -and $azLauncher.Source -match '\.cmd$') {
    # Azure CLI's batch shim can split Graph URLs at '&' before Python receives them.
    $candidatePython = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $azLauncher.Source) '..\python.exe'))
    if (-not (Test-Path -LiteralPath $candidatePython -PathType Leaf)) { throw 'Azure CLI Python launcher was not found; refusing unsafe batch URL invocation.' }
    $script:Phase10AzExecutable = $candidatePython
    $script:Phase10AzPrefixArguments = @('-IBm','azure.cli')
}
else {
    $script:Phase10AzExecutable = $azLauncher.Source
    $script:Phase10AzPrefixArguments = @()
}

function Invoke-Phase10AzCli {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $allArguments = @($script:Phase10AzPrefixArguments) + @($Arguments)
    & $script:Phase10AzExecutable @allArguments
}

function Invoke-AzJson {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $result = Invoke-Phase10AzCli -Arguments $Arguments 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Azure CLI request failed; command output is suppressed to protect identity data.' }
    $raw = (@($result | ForEach-Object { [string]$_ }) -join "`n").Trim()
    if (-not $raw) { return $null }
    try { return $raw | ConvertFrom-Json -AsHashtable } catch { throw 'Azure CLI returned invalid JSON.' }
}

function Invoke-GraphJson {
    param([Parameter(Mandatory)][ValidateSet('GET','POST','PATCH')][string]$Method,
          [Parameter(Mandatory)][string]$Uri,
          [object]$Body)
    $arguments = @('rest','--method',$Method,'--url',$Uri,'--only-show-errors')
    if ($null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth 12 -Compress
        $arguments += @('--headers','Content-Type=application/json','--body',$json)
    }
    $result = Invoke-Phase10AzCli -Arguments $arguments 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Microsoft Graph $Method request failed; response details are suppressed." }
    $raw = (@($result | ForEach-Object { [string]$_ }) -join "`n").Trim()
    if (-not $raw) { return $null }
    try { return $raw | ConvertFrom-Json -AsHashtable } catch { throw 'Microsoft Graph returned invalid JSON.' }
}

function Get-GraphCollection {
    param([Parameter(Mandatory)][string]$Uri)
    $items = @()
    $next = $Uri
    while ($next) {
        $page = Invoke-GraphJson -Method GET -Uri $next
        if ($page -isnot [System.Collections.IDictionary] -or -not $page.Contains('value')) {
            throw 'Microsoft Graph returned an invalid collection response.'
        }
        $items += @($page['value'])
        $next = if ($page.Contains('@odata.nextLink')) { [string]$page['@odata.nextLink'] } else { '' }
    }
    return $items
}

function Resolve-AzureDevOrigins {
    $catalogPath = Join-Path $repoRoot 'automation/config/runtime-targets.json'
    $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
    $target = @($catalog.targets | Where-Object key -eq 'azure-dev')
    if ($target.Count -ne 1) { throw 'Runtime-target catalog must contain exactly one azure-dev target.' }
    $resourceGroup = [string]$target[0].azureResourceGroupName
    $environmentName = [string]$target[0].azureManagedEnvironmentName
    $gatewayName = [string]$target[0].azureGatewayContainerAppName
    $uiName = [string]$target[0].azureUiContainerAppName
    $domain = Invoke-Phase10AzCli -Arguments @('containerapp','env','show','--resource-group',$resourceGroup,'--name',$environmentName,'--query','properties.defaultDomain','-o','tsv','--only-show-errors') 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$domain)) { throw 'Could not resolve the current Azure-dev generated domain.' }
    $gateway = Invoke-Phase10AzCli -Arguments @('containerapp','show','--resource-group',$resourceGroup,'--name',$gatewayName,'--query','properties.configuration.ingress.fqdn','-o','tsv','--only-show-errors') 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$gateway)) { throw 'Could not resolve the current Azure-dev API hostname.' }
    $ui = Invoke-Phase10AzCli -Arguments @('containerapp','show','--resource-group',$resourceGroup,'--name',$uiName,'--query','properties.configuration.ingress.fqdn','-o','tsv','--only-show-errors') 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$ui)) { throw 'Could not resolve the current Azure-dev UI hostname.' }
    $resolved = & node (Join-Path $PSScriptRoot 'resolve-phase10-azure-generated-urls.mjs') --target azure-dev --default-domain ([string]$domain) --gateway-fqdn ([string]$gateway) --ui-fqdn ([string]$ui) --require-live-apps
    if ($LASTEXITCODE -ne 0) { throw 'Generated Azure-dev origin validation failed.' }
    return ($resolved | ConvertFrom-Json)
}

function Get-ActiveTenantCodes {
    param([Parameter(Mandatory)][string]$ApiOrigin)
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $runtimeResponse = Invoke-RestMethod -Method Get -Uri "$ApiOrigin/api/v1/Info/runtime-configuration" -TimeoutSec 20
            $codes = @(Get-Phase10ActiveTenantCodesFromRuntimeResponse -Response $runtimeResponse)
            if ($codes.Count -gt 0) { return $codes }
        }
        catch {
            if ($attempt -eq 3) { throw 'Could not discover the active Azure-dev tenant set from the live runtime after three read-only attempts; provisioning is blocked.' }
        }
        if ($attempt -lt 3) { Start-Sleep -Seconds 2 }
    }
    throw 'The live Azure-dev runtime returned no active tenant codes after three read-only attempts; provisioning is blocked.'
}

function Get-UserMatches {
    param([Parameter(Mandatory)][object]$Mapping, [Parameter(Mandatory)][string]$ExtensionName)
    if ($Mapping.objectId) {
        $escapedId = [uri]::EscapeDataString([string]$Mapping.objectId)
        $user = Invoke-GraphJson -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$escapedId`?`$select=id,mail,userPrincipalName,userType,externalUserState,accountEnabled,$ExtensionName"
        return @($user)
    }
    $escapedEmail = ([string]$Mapping.email).Replace("'", "''")
    $filter = [uri]::EscapeDataString("mail eq '$escapedEmail' or userPrincipalName eq '$escapedEmail' or otherMails/any(alias:alias eq '$escapedEmail')")
    $uri = "https://graph.microsoft.com/v1.0/users?`$filter=$filter&`$select=id,mail,userPrincipalName,userType,externalUserState,accountEnabled,$ExtensionName"
    return @(Get-GraphCollection -Uri $uri)
}

function Save-PrivateManifest {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][object]$Manifest)
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $Manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporary -Encoding utf8NoBOM -Confirm:$false
        Move-Item -LiteralPath $temporary -Destination $Path -Force -Confirm:$false
    }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -Confirm:$false } }
}

function Set-CurrentUserProtectedFileAcl {
    param([Parameter(Mandatory)][string]$Path, [switch]$Directory)
    if (-not $IsWindows) { throw 'Secure redemption-link files are supported only on Windows.' }
    $currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $inheritance = if ($Directory) { '(OI)(CI)F' } else { 'F' }
    $arguments = @($Path, '/inheritance:r', '/grant:r', ("*$currentSid`:$inheritance"), '*S-1-5-18:F')
    if ($Directory) { $arguments[-1] = '*S-1-5-18:(OI)(CI)F' }
    & icacls.exe @arguments *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Could not restrict redemption-link file access to the current Windows user and SYSTEM.' }
    $acl = Get-Acl -LiteralPath $Path
    if (@($acl.Access | Where-Object IsInherited).Count -gt 0) { throw 'Redemption-link path still inherits permissions; refusing to write the link.' }
    foreach ($rule in @($acl.Access)) {
        $ruleSid = $rule.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value
        if ($rule.AccessControlType -eq 'Allow' -and $ruleSid -notin @($currentSid, 'S-1-5-18')) {
            throw 'Redemption-link path is accessible to an unexpected principal; refusing to write the link.'
        }
    }
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI is required; no Graph request was made.' }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js is required to validate generated Azure-dev URLs.' }
$manifestFullPath = [IO.Path]::GetFullPath($ManifestPath)
$repoFullPath = [IO.Path]::GetFullPath($repoRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($manifestFullPath.StartsWith($repoFullPath, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The test-user manifest contains personal data and must be stored outside the repository.'
}
if (-not (Test-Path -LiteralPath $manifestFullPath -PathType Leaf)) { throw 'Private test-user manifest was not found.' }

$account = Invoke-AzJson -Arguments @('account','show','--query','{id:id,tenantId:tenantId,state:state}','-o','json')
if ($account.state -ne 'Enabled') { throw 'Azure subscription is not enabled.' }
$manifestInput = Get-Content -LiteralPath $manifestFullPath -Raw | ConvertFrom-Json
if ($ExpectedDirectoryId -eq [guid]::Empty) { $ExpectedDirectoryId = [guid]$manifestInput.directoryId }
if ($ExpectedDirectoryId -eq [guid]::Empty -or [guid]$account.tenantId -ne $ExpectedDirectoryId) { throw 'Active Azure CLI directory does not match the expected directory in the private manifest.' }
if ($PromptForExpectedSubscriptionId) {
    Write-Host "Active Azure CLI subscription ID: $($account.id)"
    $answer = Read-Host 'Verify the ID above against your approved Azure-dev subscription GUID, then paste the approved GUID here (blank cancels)'
    if ([string]::IsNullOrWhiteSpace($answer)) { throw 'Cancelled before Graph or runtime queries.' }
    $ExpectedSubscriptionId = [guid]::Empty
    if (-not [guid]::TryParse($answer.Trim(), [ref]$ExpectedSubscriptionId)) { throw 'Enter the approved Azure subscription GUID, not a directory/object ID.' }
}
if ($ExpectedSubscriptionId -eq [guid]::Empty -or [guid]$account.id -ne $ExpectedSubscriptionId) { throw 'Active Azure CLI subscription does not match the explicitly confirmed dev subscription.' }
$manifest = ConvertTo-Phase10EntraTestUserManifest -InputObject $manifestInput -ExpectedDirectoryId $ExpectedDirectoryId
$extensionName = Get-Phase10EntraExtensionPropertyName -ApiClientId ([guid]$manifest.apiClientId)
if ($Mode -eq 'CreateRedemptionLink') {
    # A redemption link must return to the actual dev app. Resolve it from the
    # current deployment; never redirect guests to My Apps or a guessed origin.
    $origins = Resolve-AzureDevOrigins
    $activeTenants = @($manifest.users | ForEach-Object { [string]$_.tenantCode } | Sort-Object -Unique)
}
else {
    $origins = Resolve-AzureDevOrigins
    $activeTenants = @(Get-ActiveTenantCodes -ApiOrigin ([string]$origins.apiOrigin))
}

$applications = @(Get-GraphCollection -Uri "https://graph.microsoft.com/v1.0/applications?`$filter=appId eq '$($manifest.apiClientId)'&`$select=id,appId,api,optionalClaims")
if ($applications.Count -ne 1) { throw 'Expected exactly one API application registration; identity preflight is blocked.' }
$extensions = @(Get-GraphCollection -Uri "https://graph.microsoft.com/v1.0/applications/$($applications[0].id)/extensionProperties?`$select=id,name,targetObjects")
$extensionName = Assert-Phase10EntraApiIdentityConfiguration -Application $applications[0] -ExtensionProperties $extensions -ApiClientId ([guid]$manifest.apiClientId)
$apiServicePrincipals = @(Get-GraphCollection -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$($manifest.apiClientId)'&`$select=id,appId,appRoles")
if ($apiServicePrincipals.Count -ne 1) { throw 'Expected exactly one API service principal; role-assignment preflight is blocked.' }
$apiServicePrincipal = $apiServicePrincipals[0]
$roleById = @{}
foreach ($role in @($apiServicePrincipal.appRoles | Where-Object { $_.isEnabled -eq $true })) { $roleById[[string]$role.id] = [string]$role.value }
$apiRoleAssignments = @(Get-GraphCollection -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($apiServicePrincipal.id)/appRoleAssignedTo?`$select=principalId,principalType,appRoleId")
$privilegedRoleIds = @($apiRoleAssignments | Where-Object {
    $roleById.ContainsKey([string]$_.appRoleId) -and $roleById[[string]$_.appRoleId] -in @('platform-admin','phase10-operator')
})
if (@($privilegedRoleIds | Where-Object principalType -eq 'Group').Count -gt 0) {
    throw 'A privileged API role is assigned to a group. Resolve group membership through a separately reviewed directory process before provisioning regular test users.'
}
$directoryUsers = @()
foreach ($mapping in $manifest.users) {
    foreach ($user in @(Get-UserMatches -Mapping $mapping -ExtensionName $extensionName)) {
        $normalizedUser = [pscustomobject]@{
            id = [string]$user.id
            email = [string]$mapping.email
            mail = [string]$user.mail
            userPrincipalName = [string]$user.userPrincipalName
            userType = [string]$user.userType
            externalUserState = [string]$user.externalUserState
            accountEnabled = $user.accountEnabled
            applicationTenantCode = [string]$user.$extensionName
            apiRoles = @($apiRoleAssignments | Where-Object {
                $_.principalType -eq 'User' -and [string]$_.principalId -eq [string]$user.id -and
                $roleById.ContainsKey([string]$_.appRoleId)
            } | ForEach-Object { $roleById[[string]$_.appRoleId] })
        }
        $directoryUsers += $normalizedUser
    }
}
$plan = @(New-Phase10EntraTestUserPlan -Manifest $manifest -ActiveTenantCodes $activeTenants -DirectoryUsers $directoryUsers)
$pendingRedemption = @($plan | Where-Object action -eq 'await-invitation-redemption')

$reportRoot = Join-Path $repoRoot ('TestResults/Phase10/entra-test-users/' + (Get-Date -AsUTC -Format 'yyyyMMddTHHmmssZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
[void][IO.Directory]::CreateDirectory($reportRoot)
$reportPath = Join-Path $reportRoot 'provisioning-summary.json'
$reportRows = @($plan | ForEach-Object { [ordered]@{ tenantCode = $_.tenantCode; action = $_.action; status = if ($_.action -eq 'no-change') { 'verified' } elseif ($_.action -eq 'await-invitation-redemption') { 'pending-redemption' } else { 'planned' } } })

if ($Mode -eq 'Plan' -or $Mode -eq 'Verify') {
    $summary = [ordered]@{ schema = 'phase10-entra-test-user-provisioning-v1'; mode = $Mode.ToLowerInvariant(); status = if (@($plan | Where-Object action -ne 'no-change').Count -eq 0) { 'passed' } elseif ($Mode -eq 'Plan') { 'planned' } else { 'failed' }; environment = 'dev'; directoryId = $ExpectedDirectoryId.ToString('D'); activeTenantCodes = @($activeTenants | Sort-Object -Unique); accounts = $reportRows; invitationsSent = 0; rolesAssigned = 0 }
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM -Confirm:$false
    $displayRows = @(foreach ($row in $reportRows) { [pscustomobject]@{ tenantCode=[string]$row['tenantCode']; action=[string]$row['action']; status=[string]$row['status'] } })
    $displayRows | Format-Table tenantCode, action, status -AutoSize
    Write-Host "Sanitized report: $reportPath"
    if ($Mode -eq 'Verify' -and $summary.status -ne 'passed') { exit 1 }
    exit 0
}

if ($Mode -eq 'ResendInvitations') {
    # Resending is deliberately separate from provisioning: it must not create users,
    # alter claims/roles, or reset an invitation that has already been redeemed.
    $notPending = @($plan | Where-Object action -ne 'await-invitation-redemption')
    if ($notPending.Count -gt 0 -or $plan.Count -ne $activeTenants.Count) {
        throw 'Resend is allowed only when every active-tenant mapping resolves to one pending guest invitation. No writes were performed.'
    }
    if (-not $PSBoundParameters.ContainsKey('Confirm')) { throw 'ResendInvitations requires the explicit PowerShell -Confirm switch.' }
    if (-not [Environment]::UserInteractive) { throw 'ResendInvitations is restricted to an interactive operator session.' }
    $phrase = Read-Host 'This resends guest invitations to all mapped tenant users. Type RESEND DEV TENANT INVITATIONS to continue'
    if ($phrase -cne 'RESEND DEV TENANT INVITATIONS') { throw 'Resend cancelled; no invitation emails were requested.' }

    $results = @()
    $invitationsSent = 0
    $currentStage = 'resend-start'
    try {
        foreach ($row in $plan) {
            $currentStage = "recheck-pending:$($row.tenantCode)"
            $mapping = @($manifest.users | Where-Object tenantCode -ceq $row.tenantCode)[0]
            $userId = [string]$row.objectId
            if (-not $userId) { throw "Pending guest for $($row.tenantCode) has no pinned object ID; no invitation was sent for this tenant." }
            $escapedId = [uri]::EscapeDataString($userId)
            $currentUser = Invoke-GraphJson -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$escapedId`?`$select=id,mail,userPrincipalName,userType,externalUserState,accountEnabled,$extensionName"
            if ([string]$currentUser.id -cne $userId -or [string]$currentUser.userType -cne 'Guest' -or
                [string]$currentUser.externalUserState -cne 'PendingAcceptance' -or $currentUser.accountEnabled -eq $false) {
                throw "Guest state for $($row.tenantCode) changed or is not eligible; no resend was attempted for this tenant."
            }
            $currentEmail = [string]$currentUser.mail
            if ($currentEmail -and $currentEmail -ine [string]$mapping.email) {
                throw "Guest address for $($row.tenantCode) does not match the approved manifest; no resend was attempted for this tenant."
            }
            $currentStage = "resend-invitation:$($row.tenantCode)"
            if (-not $PSCmdlet.ShouldProcess("Pending Entra dev guest for $($row.tenantCode)", 'Reset redemption and resend invitation email')) {
                throw 'Invitation resend was not approved.'
            }
            # Keep the existing guest object and current address. Graph returns a
            # redemption URL; intentionally keep it in memory only and never log it.
            $invite = Invoke-GraphJson -Method POST -Uri 'https://graph.microsoft.com/v1.0/invitations' -Body @{
                invitedUserEmailAddress = [string]$mapping.email
                invitedUser = @{ id = $userId }
                inviteRedirectUrl = [string]$origins.uiOrigin
                resetRedemption = $true
                sendInvitationMessage = $true
            }
            if ([string]$invite.invitedUser.id -cne $userId -or [string]$invite.status -cne 'PendingAcceptance') {
                throw "Graph did not confirm a pending invitation for $($row.tenantCode); inspect the directory before retrying."
            }
            $invitationsSent++
            $results += [ordered]@{ tenantCode = $row.tenantCode; action = 'resend-pending-invitation'; status = 'email-request-accepted-pending-redemption' }
        }
        $summary = [ordered]@{ schema = 'phase10-entra-test-user-provisioning-v1'; mode = 'resend-invitations'; status = 'resend-requested-pending-redemption'; environment = 'dev'; directoryId = $ExpectedDirectoryId.ToString('D'); activeTenantCodes = @($activeTenants | Sort-Object -Unique); accounts = $results; invitationsSent = $invitationsSent; rolesAssigned = 0; claimsChanged = 0; deliveryVerified = $false; note = 'Graph accepted invitation resend requests; email delivery and guest redemption are not verified.' }
        $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM -Confirm:$false
        $displayRows = @(foreach ($row in $results) { [pscustomobject]@{ tenantCode=[string]$row['tenantCode']; action=[string]$row['action']; status=[string]$row['status'] } })
        $displayRows | Format-Table tenantCode, action, status -AutoSize
        Write-Host "Sanitized report: $reportPath"
    }
    catch {
        $failed = [ordered]@{ schema = 'phase10-entra-test-user-provisioning-v1'; mode = 'resend-invitations'; status = 'partial-failure'; environment = 'dev'; directoryId = $ExpectedDirectoryId.ToString('D'); activeTenantCodes = @($activeTenants | Sort-Object -Unique); accounts = $results; invitationsSent = $invitationsSent; rolesAssigned = 0; claimsChanged = 0; deliveryVerified = $false; failedStage = $currentStage; error = 'Resend stopped. Review the sanitized report and current guest states before retrying.' }
        $failed | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM -Confirm:$false
        Write-Host "Sanitized partial-failure report: $reportPath"
        throw 'Entra invitation resend stopped. Review the sanitized report and verify each guest state before retrying.'
    }
    exit 0
}

if ($Mode -eq 'CreateRedemptionLink') {
    if ([string]::IsNullOrWhiteSpace($TenantCode)) { throw 'CreateRedemptionLink requires one exact -TenantCode; it never operates across the tenant set.' }
    $targetRows = @($plan | Where-Object tenantCode -ceq $TenantCode.Trim())
    if ($targetRows.Count -ne 1 -or $targetRows[0].action -ne 'await-invitation-redemption' -or -not $targetRows[0].objectId) {
        throw 'The selected tenant must resolve to exactly one existing pending guest with a pinned object ID. No writes were performed.'
    }
    if (-not $PSBoundParameters.ContainsKey('Confirm')) { throw 'CreateRedemptionLink requires the explicit PowerShell -Confirm switch.' }
    if (-not [Environment]::UserInteractive) { throw 'CreateRedemptionLink is restricted to an interactive operator session.' }
    $phrase = Read-Host "This resets redemption for $TenantCode and creates a private local link without sending email. Type CREATE DEV REDEMPTION LINK $($TenantCode.Trim()) to continue"
    if ($phrase -cne "CREATE DEV REDEMPTION LINK $($TenantCode.Trim())") { throw 'Redemption-link creation cancelled; no directory changes were made.' }

    $mapping = @($manifest.users | Where-Object tenantCode -ceq $TenantCode.Trim())[0]
    $row = $targetRows[0]
    $secureDirectory = Join-Path $env:LOCALAPPDATA 'XYDataLabs/phase10-entra-redemption-links'
    [void][IO.Directory]::CreateDirectory($secureDirectory)
    Set-CurrentUserProtectedFileAcl -Path $secureDirectory -Directory
    $linkPath = Join-Path $secureDirectory ("$($TenantCode.Trim())-" + (Get-Date -AsUTC -Format 'yyyyMMddTHHmmssZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.txt')
    [void][IO.File]::WriteAllText($linkPath, 'Pending secure invitation link generation.', [Text.UTF8Encoding]::new($false))
    Set-CurrentUserProtectedFileAcl -Path $linkPath

    $userId = [string]$row.objectId
    $escapedId = [uri]::EscapeDataString($userId)
    $currentUser = Invoke-GraphJson -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$escapedId`?`$select=id,mail,userType,externalUserState,accountEnabled,$extensionName"
    if ([string]$currentUser.id -cne $userId -or [string]$currentUser.userType -cne 'Guest' -or
        [string]$currentUser.externalUserState -cne 'PendingAcceptance' -or $currentUser.accountEnabled -eq $false -or
        ([string]$currentUser.mail -and [string]$currentUser.mail -ine [string]$mapping.email)) {
        throw 'Tenant guest identity changed or no longer matches the approved pending guest; no redemption reset was attempted.'
    }
    if (-not $PSCmdlet.ShouldProcess("Pending Entra dev guest for $($TenantCode.Trim())", 'Reset redemption and create a local-only invitation link')) {
        throw 'Redemption-link creation was not approved.'
    }

    $currentStage = "create-redemption-link:$($TenantCode.Trim())"
    try {
        $invite = Invoke-GraphJson -Method POST -Uri 'https://graph.microsoft.com/v1.0/invitations' -Body @{
            invitedUserEmailAddress = [string]$mapping.email
            invitedUser = @{ id = $userId }
            inviteRedirectUrl = [string]$origins.uiOrigin
            resetRedemption = $true
            sendInvitationMessage = $false
        }
        $redeemUri = [uri]::new([string]$invite.inviteRedeemUrl)
        if (-not $redeemUri.IsAbsoluteUri -or $redeemUri.Scheme -cne 'https' -or $redeemUri.Host -cne 'login.microsoftonline.com' -or
            [string]$invite.invitedUser.id -cne $userId -or [string]$invite.status -cne 'PendingAcceptance' -or
            $invite.sendInvitationMessage -ne $false) {
            throw 'Graph response did not satisfy the expected no-email, same-guest redemption contract.'
        }
        [IO.File]::WriteAllText($linkPath, [string]$invite.inviteRedeemUrl, [Text.UTF8Encoding]::new($false))
        Set-CurrentUserProtectedFileAcl -Path $linkPath
        $summary = [ordered]@{ schema = 'phase10-entra-test-user-provisioning-v1'; mode = 'create-redemption-link'; status = 'link-created-awaiting-redemption'; environment = 'dev'; directoryId = $ExpectedDirectoryId.ToString('D'); tenantCode = $TenantCode.Trim(); tenantTopologySource = 'live Azure dev deployment outputs'; redirectDestination = [string]$origins.uiOrigin; guestObjectPreserved = $true; emailSent = $false; linkStoredInUserOnlyLocalFile = $true; tenantClaimsChanged = 0; rolesAssigned = 0; reportContainsRedemptionUrl = $false }
        $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM -Confirm:$false
        Write-Host "Private redemption link file created: $linkPath"
        Write-Host 'Open that local file, copy the link into a private browser session, complete normal sign-in/consent, then delete the file after redemption.'
        Write-Host "Sanitized report: $reportPath"
    }
    catch {
        $failed = [ordered]@{ schema = 'phase10-entra-test-user-provisioning-v1'; mode = 'create-redemption-link'; status = 'failed-or-uncertain'; environment = 'dev'; directoryId = $ExpectedDirectoryId.ToString('D'); tenantCode = $TenantCode.Trim(); emailSent = $false; tenantClaimsChanged = 0; rolesAssigned = 0; reportContainsRedemptionUrl = $false; failedStage = $currentStage; error = 'Link creation stopped. Inspect the guest state and protected local link file before any retry.' }
        $failed | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM -Confirm:$false
        Write-Host "Sanitized partial-failure report: $reportPath"
        throw 'Tenant redemption-link creation failed or is uncertain. Do not retry until the guest and local link-file state are reviewed.'
    }
    exit 0
}

if ($Mode -eq 'Apply' -and $pendingRedemption.Count -gt 0) {
    $blocked = [ordered]@{ schema = 'phase10-entra-test-user-provisioning-v1'; mode = 'apply'; status = 'blocked-pending-redemption'; environment = 'dev'; directoryId = $ExpectedDirectoryId.ToString('D'); activeTenantCodes = @($activeTenants | Sort-Object -Unique); accounts = $reportRows; invitationsSent = 0; rolesAssigned = 0; error = 'No writes performed: wait for existing guest invitations to be redeemed, then run Verify.' }
    $blocked | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM -Confirm:$false
    Write-Host "Sanitized report: $reportPath"
    throw 'Guest invitation redemption is pending. No invitation or claim changes were made; wait for redemption and run Verify.'
}

if (-not $PSBoundParameters.ContainsKey('Confirm')) { throw 'Apply requires the explicit PowerShell -Confirm switch.' }
if (-not [Environment]::UserInteractive) { throw 'Apply is restricted to an interactive operator session.' }
$phrase = Read-Host 'This may email external guests and assign tenant claims. Type APPLY DEV TENANT TEST USERS to continue'
if ($phrase -cne 'APPLY DEV TENANT TEST USERS') { throw 'Apply cancelled; no invitations or claim updates were sent.' }

$results = @()
$invitationsSent = 0
$currentStage = 'apply-start'
try {
    foreach ($row in $plan) {
        $currentStage = "resolve-user:$($row.tenantCode)"
        $mapping = @($manifest.users | Where-Object tenantCode -ceq $row.tenantCode)[0]
        $directoryUser = $directoryUsers | Where-Object { $_.id -and ($_.id -eq $row.objectId -or $_.email -ieq $mapping.email) } | Select-Object -First 1
        $resultIndex = -1
        if ($row.action -eq 'invite-guest-and-assign-tenant') {
            $currentStage = "invite-guest:$($row.tenantCode)"
            if (-not $PSCmdlet.ShouldProcess("Entra dev guest for $($row.tenantCode)", 'Send invitation email')) { throw 'Invitation was not approved.' }
            $invite = Invoke-GraphJson -Method POST -Uri 'https://graph.microsoft.com/v1.0/invitations' -Body @{
                invitedUserEmailAddress = $mapping.email
                inviteRedirectUrl = [string]$origins.uiOrigin
                sendInvitationMessage = $true
            }
            $userId = [string]$invite.invitedUser.id
            if (-not $userId) { throw "Invitation for $($row.tenantCode) did not return a guest object ID." }
            $invitationsSent++
            $mapping.objectId = $userId
            $directoryUser = [pscustomobject]@{ id = $userId; email = [string]$mapping.email; applicationTenantCode = '' }
            Save-PrivateManifest -Path $manifestFullPath -Manifest $manifest
            $directoryUsers += $directoryUser
            $reportRows | Where-Object tenantCode -ceq $row.tenantCode | ForEach-Object { $_.status = 'invited' }
            $results += [ordered]@{ tenantCode = $row.tenantCode; action = $row.action; status = 'invited-claim-pending' }
            $resultIndex = $results.Count - 1
        }
        elseif ($row.action -eq 'assign-tenant-claim') {
            if (-not $directoryUser) { throw "Existing Entra user for $($row.tenantCode) could not be resolved again." }
            $userId = [string]$directoryUser.id
        }
        else {
            if (-not $mapping.objectId -and $row.objectId) {
                # Pin the verified directory object locally so the browser run can prove it signed in as this exact identity.
                $mapping.objectId = [string]$row.objectId
                Save-PrivateManifest -Path $manifestFullPath -Manifest $manifest
            }
            $results += [ordered]@{ tenantCode = $row.tenantCode; action = 'no-change'; status = 'verified' }
            continue
        }

        $currentStage = "assign-tenant-claim:$($row.tenantCode)"
        if (-not $PSCmdlet.ShouldProcess("Entra user for $($row.tenantCode)", 'Set applicationTenantCode claim')) { throw 'Tenant claim update was not approved.' }
        $patchBody = @{}; $patchBody[$extensionName] = $row.tenantCode
        [void](Invoke-GraphJson -Method PATCH -Uri "https://graph.microsoft.com/v1.0/users/$userId" -Body $patchBody)
        $mapping.objectId = $userId
        Save-PrivateManifest -Path $manifestFullPath -Manifest $manifest
        if ($resultIndex -ge 0) { $results[$resultIndex].status = 'claim-set' }
        else { $results += [ordered]@{ tenantCode = $row.tenantCode; action = $row.action; status = 'claim-set' } }
    }
    $summary = [ordered]@{ schema = 'phase10-entra-test-user-provisioning-v1'; mode = 'apply'; status = 'applied-pending-verify'; environment = 'dev'; directoryId = $ExpectedDirectoryId.ToString('D'); activeTenantCodes = @($activeTenants | Sort-Object -Unique); accounts = $results; invitationsSent = $invitationsSent; rolesAssigned = 0; note = 'Invitation redemption and Verify mode are required before browser testing.' }
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM -Confirm:$false
    $displayRows = @(foreach ($row in $results) { [pscustomobject]@{ tenantCode=[string]$row['tenantCode']; action=[string]$row['action']; status=[string]$row['status'] } })
    $displayRows | Format-Table tenantCode, action, status -AutoSize
    Write-Host "Sanitized report: $reportPath"
}
catch {
    $failed = [ordered]@{ schema = 'phase10-entra-test-user-provisioning-v1'; mode = 'apply'; status = 'partial-failure'; environment = 'dev'; directoryId = $ExpectedDirectoryId.ToString('D'); activeTenantCodes = @($activeTenants | Sort-Object -Unique); accounts = $results; invitationsSent = $invitationsSent; rolesAssigned = 0; failedStage = $currentStage; error = 'Apply stopped. Re-run Plan/Verify; no guest is automatically deleted or reinvited.' }
    $failed | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM -Confirm:$false
    Write-Host "Sanitized partial-failure report: $reportPath"
    throw 'Entra test-user apply stopped. Review the sanitized report, then rerun Plan/Verify before any retry.'
}
