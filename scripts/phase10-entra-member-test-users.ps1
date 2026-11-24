#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = 'ExplicitSubscription')]
param(
    [ValidateSet('Plan','Apply','Verify')][string]$Mode = 'Plan',
    [string]$ManifestPath = (Join-Path $env:LOCALAPPDATA 'XYDataLabs/phase10-entra-member-test-users/phase10-entra-member-test-users.dev.json'),
    [Parameter(Mandatory,ParameterSetName='ExplicitSubscription')][guid]$ExpectedSubscriptionId,
    [Parameter(Mandatory,ParameterSetName='PromptSubscription')][switch]$PromptForExpectedSubscriptionId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'phase10-entra-member-test-users.module.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'phase10-entra-test-users.module.psm1') -Force

function Invoke-AzText {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $output = & az @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Azure CLI request failed; command output is suppressed.' }
    return (@($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
}

function Invoke-Graph {
    param([Parameter(Mandatory)][ValidateSet('GET','POST','PATCH')][string]$Method,
          [Parameter(Mandatory)][string]$Uri, [object]$Body)
    $headers = @{ Authorization = "Bearer $script:graphAccessToken" }
    try {
        if ($null -eq $Body) { return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -TimeoutSec 30 }
        $json = ConvertTo-Json -InputObject $Body -Depth 12 -Compress
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
        $next = [string]$page.'@odata.nextLink'
    }
    return $items
}

function Resolve-DevOrigins {
    $catalog = Get-Content -LiteralPath (Join-Path $repoRoot 'automation/config/runtime-targets.json') -Raw | ConvertFrom-Json
    $matches = @($catalog.targets | Where-Object key -eq 'azure-dev')
    if ($matches.Count -ne 1) { throw 'Expected exactly one azure-dev runtime target.' }
    $target = $matches[0]
    $defaultDomain = Invoke-AzText @('containerapp','env','show','--resource-group',[string]$target.azureResourceGroupName,'--name',[string]$target.azureManagedEnvironmentName,'--query','properties.defaultDomain','-o','tsv','--only-show-errors')
    $gateway = Invoke-AzText @('containerapp','show','--resource-group',[string]$target.azureResourceGroupName,'--name',[string]$target.azureGatewayContainerAppName,'--query','properties.configuration.ingress.fqdn','-o','tsv','--only-show-errors')
    $ui = Invoke-AzText @('containerapp','show','--resource-group',[string]$target.azureResourceGroupName,'--name',[string]$target.azureUiContainerAppName,'--query','properties.configuration.ingress.fqdn','-o','tsv','--only-show-errors')
    $resolved = & node (Join-Path $PSScriptRoot 'resolve-phase10-azure-generated-urls.mjs') --target azure-dev --default-domain $defaultDomain --gateway-fqdn $gateway --ui-fqdn $ui --require-live-apps
    if ($LASTEXITCODE -ne 0) { throw 'Could not validate generated Azure-dev origins.' }
    return ($resolved | ConvertFrom-Json)
}

function Get-ActiveTenants {
    param([Parameter(Mandatory)][string]$ApiOrigin)
    for ($attempt=1; $attempt -le 3; $attempt++) {
        try {
            $response = Invoke-RestMethod -Method Get -Uri "$ApiOrigin/api/v1/Info/runtime-configuration" -TimeoutSec 20
            return @(Get-Phase10ActiveTenantCodesFromRuntimeResponse -Response $response)
        }
        catch { if ($attempt -eq 3) { throw 'Live Azure-dev tenant discovery failed; no directory writes were made.' }; Start-Sleep -Seconds 2 }
    }
}

function Set-PrivateFileAcl {
    param([Parameter(Mandatory)][string]$Path, [switch]$Directory)
    if (-not $IsWindows) { throw 'Member test-user provisioning is supported only on Windows PowerShell 7.' }
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $rights = if ($Directory) { '(OI)(CI)F' } else { 'F' }
    & icacls.exe $Path '/inheritance:r' '/grant:r' ("*$sid`:$rights") $(if ($Directory) { '*S-1-5-18:(OI)(CI)F' } else { '*S-1-5-18:F' }) *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Could not restrict the private manifest ACL.' }
    $acl = Get-Acl -LiteralPath $Path
    if (@($acl.Access | Where-Object IsInherited).Count -gt 0) { throw 'Private manifest still inherits permissions.' }
    foreach ($rule in @($acl.Access)) {
        $ruleSid = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
        if ($rule.AccessControlType -eq 'Allow' -and $ruleSid -notin @($sid,'S-1-5-18')) { throw 'Private manifest has an unexpected allowed principal.' }
    }
}

function Save-PrivateManifest {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][object]$Value)
    $parent = Split-Path -Parent $Path
    [void][IO.Directory]::CreateDirectory($parent)
    Set-PrivateFileAcl -Path $parent -Directory
    $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temp -Encoding utf8NoBOM -Confirm:$false
        Set-PrivateFileAcl -Path $temp
        Move-Item -LiteralPath $temp -Destination $Path -Force -Confirm:$false
        Set-PrivateFileAcl -Path $Path
    }
    finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -Confirm:$false } }
}

function Read-TemporaryPassword {
    param([Parameter(Mandatory)][string]$TenantCode)
    $secure = Read-Host "Enter a unique temporary password for $TenantCode (not echoed; do not reuse another account password)" -AsSecureString
    $plain = [Net.NetworkCredential]::new('', $secure).Password
    if ($plain.Length -lt 16 -or -not ($plain -cmatch '[A-Z]') -or -not ($plain -cmatch '[a-z]') -or -not ($plain -match '\d') -or -not ($plain -match '[^A-Za-z0-9]')) {
        $secure.Dispose(); $plain = $null
        throw 'Temporary password must be at least 16 characters and include upper, lower, number, and symbol. No user was created for this tenant.'
    }
    return @{ Secure = $secure; Plain = $plain }
}

if (-not $IsWindows -or -not [Environment]::UserInteractive) { throw 'Run this provisioner in an interactive Windows PowerShell 7 session.' }
if (-not (Get-Command az -ErrorAction SilentlyContinue) -or -not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Azure CLI and Node.js are required; no Graph request was made.' }
$manifestFullPath = [IO.Path]::GetFullPath($ManifestPath)
$repoPrefix = [IO.Path]::GetFullPath($repoRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($manifestFullPath.StartsWith($repoPrefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Member test-user manifest contains identity data and must be outside the repository.' }
$privateDirectory = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'XYDataLabs/phase10-entra-member-test-users')).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $manifestFullPath.StartsWith($privateDirectory,[StringComparison]::OrdinalIgnoreCase)) { throw 'Store the member-test manifest only in the dedicated per-user LocalAppData directory.' }
if (-not (Test-Path -LiteralPath $manifestFullPath -PathType Leaf)) { throw 'Private organizational-member manifest is missing.' }

$account = Invoke-AzText @('account','show','--query','{id:id,tenantId:tenantId,state:state}','-o','json') | ConvertFrom-Json
if ($PromptForExpectedSubscriptionId) {
    Write-Host "Active Azure CLI subscription ID: $($account.id)"
    $answer = Read-Host 'Verify the ID above against your approved Azure-dev subscription GUID, then paste the approved GUID here (blank cancels)'
    if ([string]::IsNullOrWhiteSpace($answer) -or [guid]$answer.Trim() -ne [guid]$account.id) { throw 'Subscription confirmation failed; no Graph or runtime request was made.' }
    $ExpectedSubscriptionId = [guid]$account.id
}
if ($account.state -ne 'Enabled' -or [guid]$account.id -ne $ExpectedSubscriptionId) { throw 'Active Azure CLI subscription does not match the explicitly approved dev subscription.' }
$inputManifest = Get-Content -LiteralPath $manifestFullPath -Raw | ConvertFrom-Json
$expectedDirectory = [guid]$inputManifest.directoryId
if ([guid]$account.tenantId -ne $expectedDirectory) { throw 'Active Entra directory does not match the private manifest.' }
$manifest = ConvertTo-Phase10EntraMemberTestManifest -InputObject $inputManifest -ExpectedDirectoryId $expectedDirectory

$graphTokenOutput = & az account get-access-token --resource-type ms-graph --query accessToken -o tsv 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$graphTokenOutput)) { throw 'Could not acquire an interactive Microsoft Graph token; no directory changes were made.' }
$script:graphAccessToken = ([string]$graphTokenOutput).Trim(); $graphTokenOutput = $null
$domainUri = 'https://graph.microsoft.com/v1.0/domains/' + [uri]::EscapeDataString($manifest.signInDomain)
$verifiedDomain = Invoke-Graph -Method GET -Uri $domainUri
if ($verifiedDomain.isVerified -ne $true) { throw 'The configured sign-in domain is not verified in this Entra directory.' }
$origins = Resolve-DevOrigins
$activeTenants = @(Get-ActiveTenants -ApiOrigin ([string]$origins.apiOrigin))
$apiApps = @(Get-GraphItems -Uri "https://graph.microsoft.com/v1.0/applications?`$filter=appId eq '$($manifest.apiClientId)'&`$select=id,appId,api,optionalClaims")
if ($apiApps.Count -ne 1) { throw 'Expected exactly one API application registration.' }
$extensions = @(Get-GraphItems -Uri "https://graph.microsoft.com/v1.0/applications/$($apiApps[0].id)/extensionProperties?`$select=id,name,targetObjects")
$extensionName = Assert-Phase10EntraApiIdentityConfiguration -Application $apiApps[0] -ExtensionProperties $extensions -ApiClientId ([guid]$manifest.apiClientId)
$servicePrincipals = @(Get-GraphItems -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$($manifest.apiClientId)'&`$select=id,appRoles")
if ($servicePrincipals.Count -ne 1) { throw 'Expected exactly one API service principal.' }
$apiSp = $servicePrincipals[0]
$roleById = @{}; foreach ($role in @($apiSp.appRoles | Where-Object isEnabled)) { $roleById[[string]$role.id] = [string]$role.value }
$assignments = @(Get-GraphItems -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($apiSp.id)/appRoleAssignedTo?`$select=principalId,principalType,appRoleId")
$privilegedRoleIds = @($assignments | Where-Object { $roleById.ContainsKey([string]$_.appRoleId) -and $roleById[[string]$_.appRoleId] -in @('platform-admin','phase10-operator') })
if (@($privilegedRoleIds | Where-Object principalType -eq 'Group').Count -gt 0) { throw 'A privileged API role is assigned to a group; group membership must be reviewed separately.' }

$directoryUsers = @()
foreach ($mapping in $manifest.users) {
    $matches = if ($mapping.objectId) {
        @(Invoke-Graph -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$([uri]::EscapeDataString($mapping.objectId))`?`$select=id,userPrincipalName,userType,accountEnabled,$extensionName")
    } else {
        $filter = [uri]::EscapeDataString("userPrincipalName eq '$($mapping.userPrincipalName.Replace("'","''"))'")
        @(Get-GraphItems -Uri "https://graph.microsoft.com/v1.0/users?`$filter=$filter&`$select=id,userPrincipalName,userType,accountEnabled,$extensionName")
    }
    foreach ($user in $matches) {
        $directoryUsers += [pscustomobject]@{
            id=[string]$user.id; userPrincipalName=[string]$user.userPrincipalName; userType=[string]$user.userType
            accountEnabled=$user.accountEnabled; applicationTenantCode=[string]$user.$extensionName
            apiRoles=@($assignments | Where-Object { $_.principalType -eq 'User' -and [string]$_.principalId -eq [string]$user.id -and $roleById.ContainsKey([string]$_.appRoleId) } | ForEach-Object { $roleById[[string]$_.appRoleId] })
        }
    }
}
$plan = @(New-Phase10EntraMemberTestUserPlan -Manifest $manifest -ActiveTenantCodes $activeTenants -DirectoryUsers $directoryUsers)
$reportRoot = Join-Path $repoRoot ('TestResults/Phase10/entra-member-test-users/' + (Get-Date -AsUTC -Format 'yyyyMMddTHHmmssZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
[void][IO.Directory]::CreateDirectory($reportRoot)
$reportPath = Join-Path $reportRoot 'provisioning-summary.json'

if ($Mode -eq 'Plan' -or $Mode -eq 'Verify') {
    $rows = @($plan | ForEach-Object { [ordered]@{ tenantCode=$_.tenantCode; action=$_.action; status=if ($_.action -eq 'no-change') {'verified'} else {'planned'} } })
    $status = if (@($plan | Where-Object action -ne 'no-change').Count -eq 0) {'passed'} elseif ($Mode -eq 'Plan') {'planned'} else {'failed'}
    [ordered]@{ schema='phase10-entra-member-test-user-provisioning-v1'; mode=$Mode.ToLowerInvariant(); status=$status; directoryId=$expectedDirectory.ToString('D'); activeTenantCodes=@($activeTenants | Sort-Object -Unique); accounts=$rows; emailsSent=0; privilegedRolesAssigned=0; passwordsStored=false } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM
    $plan | Select-Object tenantCode,action,status | Format-Table -AutoSize
    Write-Host "Sanitized report: $reportPath"
    if ($Mode -eq 'Verify' -and $status -ne 'passed') { exit 1 }
    exit 0
}

if (-not $PSBoundParameters.ContainsKey('Confirm')) { throw 'Apply requires the explicit -Confirm switch.' }
$phrase = Read-Host 'This creates/updates only the listed DEV member accounts and tenant claims; no invitations or email are sent. Type APPLY DEV MEMBER TEST USERS to continue'
if ($phrase -cne 'APPLY DEV MEMBER TEST USERS') { throw 'Apply cancelled; no directory changes were made.' }
$results = @(); $stage = 'apply-start'; $temporaryPasswordDigests = @{}
try {
    foreach ($row in $plan) {
        if ($row.action -eq 'no-change') { $results += [ordered]@{tenantCode=$row.tenantCode;action='no-change';status='verified'}; continue }
        $mapping = @($manifest.users | Where-Object tenantCode -ceq $row.tenantCode)[0]
        if (-not $PSCmdlet.ShouldProcess("Entra organizational test account for $($row.tenantCode)",$row.action)) { throw 'Apply stopped by ShouldProcess; review current directory state before retrying.' }
        $currentId = [string]$row.objectId
        if (-not $currentId) {
            $stage = "create-member:$($row.tenantCode)"
            $credential = Read-TemporaryPassword -TenantCode $row.tenantCode
            try {
                $passwordDigest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($credential.Plain)))
                if ($temporaryPasswordDigests.ContainsKey($passwordDigest)) { throw 'Use a distinct temporary password for each new test account.' }
                $temporaryPasswordDigests[$passwordDigest] = $true
                $alias = $mapping.userPrincipalName.Split('@')[0]
                $created = Invoke-Graph -Method POST -Uri 'https://graph.microsoft.com/v1.0/users' -Body @{
                    accountEnabled=$true; displayName=$mapping.displayName; mailNickname=$alias; userPrincipalName=$mapping.userPrincipalName
                    passwordProfile=@{ password=$credential.Plain; forceChangePasswordNextSignIn=$true }
                }
            }
            finally { $credential.Secure.Dispose(); $credential.Plain = $null; $credential = $null }
            $currentId = [string]$created.id
            if (-not $currentId) { throw "Graph did not return an object ID for $($row.tenantCode); inspect Entra before retrying." }
            $mapping.objectId = $currentId
            Save-PrivateManifest -Path $manifestFullPath -Value $manifest
            $results += [ordered]@{tenantCode=$row.tenantCode;action='create-member';status='created-password-change-required'}
        }
        $stage = "set-tenant-claim:$($row.tenantCode)"
        $patch = @{}; $patch[$extensionName] = $row.tenantCode
        [void](Invoke-Graph -Method PATCH -Uri "https://graph.microsoft.com/v1.0/users/$([uri]::EscapeDataString($currentId))" -Body $patch)
        $verifiedUser = Invoke-Graph -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$([uri]::EscapeDataString($currentId))`?`$select=id,userPrincipalName,userType,accountEnabled,$extensionName"
        if ([string]$verifiedUser.id -cne $currentId -or [string]$verifiedUser.userType -cne 'Member' -or $verifiedUser.accountEnabled -ne $true -or [string]$verifiedUser.$extensionName -cne $row.tenantCode) {
            throw "Post-write verification failed for $($row.tenantCode); stop and inspect the directory before retrying."
        }
        if ($row.action -eq 'assign-tenant-claim') { $results += [ordered]@{tenantCode=$row.tenantCode;action='assign-tenant-claim';status='verified'} }
        elseif ($row.action -eq 'create-member-and-assign-tenant') {
            $createdIndex = -1
            for ($i = 0; $i -lt $results.Count; $i++) { if ($results[$i].tenantCode -ceq $row.tenantCode) { $createdIndex = $i } }
            if ($createdIndex -lt 0) { throw 'Created member was not recorded in the operation ledger.' }
            $results[$createdIndex]['status'] = 'created-and-claim-verified'
        }
    }
    $summary = [ordered]@{schema='phase10-entra-member-test-user-provisioning-v1';mode='apply';status='applied-verify-before-browser';directoryId=$expectedDirectory.ToString('D');activeTenantCodes=@($activeTenants | Sort-Object -Unique);accounts=$results;emailsSent=0;privilegedRolesAssigned=0;passwordsStored=$false;note='Temporary passwords were neither logged nor stored. Each new account requires password change and normal MFA at first sign-in.'}
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM
    $results | ForEach-Object { [pscustomobject]@{tenantCode=$_.tenantCode;action=$_.action;status=$_.status} } | Format-Table -AutoSize
    Write-Host "Sanitized report: $reportPath"
    Write-Host 'Run Verify before the no-payment browser isolation task.'
}
catch {
    [ordered]@{schema='phase10-entra-member-test-user-provisioning-v1';mode='apply';status='partial-failure';directoryId=$expectedDirectory.ToString('D');activeTenantCodes=@($activeTenants | Sort-Object -Unique);accounts=$results;emailsSent=0;privilegedRolesAssigned=0;passwordsStored=$false;failedStage=$stage;error='Provisioning stopped. Inspect sanitized report and current directory state before retrying.'} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM
    Write-Host "Sanitized partial-failure report: $reportPath"
    throw 'Member test-user provisioning stopped; inspect the directory and report before any retry.'
}
finally { $script:graphAccessToken = $null }
