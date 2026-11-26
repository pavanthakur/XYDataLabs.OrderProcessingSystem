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

function Invoke-AzJson {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $output = & az @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Azure CLI request failed; command output is suppressed.' }
    return (@($output | ForEach-Object { [string]$_ }) -join "`n") | ConvertFrom-Json
}

function Invoke-Graph {
    param([Parameter(Mandatory)][ValidateSet('GET','POST','PATCH')][string]$Method,
          [Parameter(Mandatory)][string]$Uri, [object]$Body)
    $headers = @{ Authorization = "Bearer $script:graphAccessToken" }
    try {
        if ($null -eq $Body) { return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -TimeoutSec 30 }
        $json = ConvertTo-Json -InputObject $Body -Depth 8 -Compress
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -ContentType 'application/json' -Body $json -TimeoutSec 30
    } catch { throw "Microsoft Graph $Method request failed; response details are suppressed." }
}

function Set-PrivateAcl {
    param([Parameter(Mandatory)][string]$Path, [switch]$Directory)
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
    Set-PrivateAcl -Path $parent -Directory
    $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temp -Encoding utf8NoBOM -Confirm:$false
        Set-PrivateAcl -Path $temp
        Move-Item -LiteralPath $temp -Destination $Path -Force -Confirm:$false
        Set-PrivateAcl -Path $Path
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -Confirm:$false } }
}

function Read-TemporaryPassword {
    $secure = Read-Host 'Enter a unique temporary password for the replay approver (not echoed; do not reuse another account password)' -AsSecureString
    $plain = [Net.NetworkCredential]::new('', $secure).Password
    if ($plain.Length -lt 16 -or -not ($plain -cmatch '[A-Z]') -or -not ($plain -cmatch '[a-z]') -or -not ($plain -match '\d') -or -not ($plain -match '[^A-Za-z0-9]')) {
        $secure.Dispose(); $plain = $null
        throw 'Temporary password must be at least 16 characters and include upper, lower, number, and symbol. No user was created.'
    }
    return @{ Secure = $secure; Plain = $plain }
}

if (-not $IsWindows -or -not [Environment]::UserInteractive) { throw 'Run this provisioner in an interactive Windows PowerShell 7 session.' }
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI is required; no Graph request was made.' }
$manifestFullPath = [IO.Path]::GetFullPath($ManifestPath)
$repoPrefix = [IO.Path]::GetFullPath($repoRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$privateDirectory = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'XYDataLabs/phase10-replay-approver')).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($manifestFullPath.StartsWith($repoPrefix,[StringComparison]::OrdinalIgnoreCase) -or -not $manifestFullPath.StartsWith($privateDirectory,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'Keep the identity manifest only in its dedicated per-user LocalAppData directory.'
}
if (-not (Test-Path -LiteralPath $manifestFullPath -PathType Leaf)) { throw 'Private replay-approver manifest is missing; copy the example and fill its non-secret fields first.' }
$manifest = Get-Content -LiteralPath $manifestFullPath -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.environment -cne 'dev' -or $manifest.identityType -cne 'replay-approver' -or $manifest.tenantCode -cne 'TenantA') { throw 'Manifest must identify the Phase 10 TenantA replay approver in dev.' }
$directoryId = [guid]::Empty; $subscriptionId = [guid]::Empty; $apiClientId = [guid]::Empty; $runnerId = [guid]::Empty
if (-not [guid]::TryParse([string]$manifest.directoryId,[ref]$directoryId) -or -not [guid]::TryParse([string]$manifest.subscriptionId,[ref]$subscriptionId) -or -not [guid]::TryParse([string]$manifest.apiClientId,[ref]$apiClientId) -or -not [guid]::TryParse([string]$manifest.replayRunnerObjectId,[ref]$runnerId)) { throw 'Manifest directory, subscription, API, and runner IDs must be valid GUIDs.' }
$upn = ([string]$manifest.approverUserPrincipalName).Trim().ToLowerInvariant()
if ($upn -cne 'phase10-replay-approver@pavanthakurgmail.onmicrosoft.com' -or [string]::IsNullOrWhiteSpace([string]$manifest.approverDisplayName)) { throw 'Approver identity must match the explicitly reviewed dev account mapping.' }
if ($manifest.approverObjectId -and [string]$manifest.approverObjectId -eq [string]$manifest.replayRunnerObjectId) { throw 'Approver must be distinct from the replay runner.' }
foreach ($id in @($manifest.tenantTestUserObjectIds)) { if ([string]$id -eq [string]$manifest.approverObjectId) { throw 'Approver must be distinct from tenant-isolation test users.' } }
$account = Invoke-AzJson @('account','show','--query','{id:id,tenantId:tenantId,state:state}','-o','json')
if ($PromptForExpectedSubscriptionId) {
    Write-Host "Active Azure CLI subscription ID: $($account.id)"
    $answer = Read-Host 'Verify the ID above against the approved Azure-dev subscription GUID, then paste the approved GUID here (blank cancels)'
    if ([string]::IsNullOrWhiteSpace($answer) -or [guid]$answer.Trim() -ne [guid]$account.id) { throw 'Subscription confirmation failed; no Graph request was made.' }
    $ExpectedSubscriptionId = [guid]$account.id
}
if ($account.state -ne 'Enabled' -or [guid]$account.id -ne $ExpectedSubscriptionId -or [guid]$account.tenantId -ne $directoryId -or $subscriptionId -ne $ExpectedSubscriptionId) { throw 'Azure subscription or directory does not match the private dev manifest.' }
$reportRoot = Join-Path $repoRoot ('TestResults/Phase10/entra-replay-approver-account/' + (Get-Date -AsUTC -Format 'yyyyMMddTHHmmssZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
[void][IO.Directory]::CreateDirectory($reportRoot)
$reportPath = Join-Path $reportRoot 'account-summary.json'
$stage = 'preflight'
function Write-AccountStatus {
    param([Parameter(Mandatory)][string]$Status, [Parameter(Mandatory)][string]$Stage)
    [ordered]@{schema='phase10-entra-replay-approver-account-v1';mode=$Mode.ToLowerInvariant();status=$Status;environment='dev';tenantCode='TenantA';stage=$Stage;objectIdsRecorded=$false;upnsRecorded=$false;credentialsStored=$false;passwordLogged=$false} |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM -Confirm:$false
}
try {
    Write-Host '[Phase 10] Starting read-only Entra preflight for the replay approver account.'
    $stage = 'acquire-graph-token'
    Write-Host '[Phase 10] Acquiring the interactive Microsoft Graph token.'
    $token = & az account get-access-token --resource-type ms-graph --query accessToken -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$token)) { throw 'Could not obtain an interactive Microsoft Graph token; no directory writes were made.' }
    $script:graphAccessToken = ([string]$token).Trim(); $token = $null
    $stage = 'validate-graph-token'
    $tokenPayload = $script:graphAccessToken.Split('.')[1].Replace('-','+').Replace('_','/')
    if ($tokenPayload.Length % 4) { $tokenPayload += '=' * (4 - ($tokenPayload.Length % 4)) }
    $tokenClaims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($tokenPayload)) | ConvertFrom-Json
    $graphGrants = @()
    $scopeClaim = $tokenClaims.PSObject.Properties['scp']
    if ($null -ne $scopeClaim -and -not [string]::IsNullOrWhiteSpace([string]$scopeClaim.Value)) { $graphGrants += ([string]$scopeClaim.Value -split ' ') }
    $rolesClaim = $tokenClaims.PSObject.Properties['roles']
    if ($null -ne $rolesClaim) { $graphGrants += @($rolesClaim.Value | ForEach-Object { [string]$_ }) }
    if ($Mode -eq 'Apply' -and 'User.ReadWrite.All' -notin $graphGrants) { throw 'The interactive Graph token lacks User.ReadWrite.All; no directory writes were made.' }
    $stage = 'verify-sign-in-domain'
    Write-Host '[Phase 10] Checking the verified sign-in domain and API tenant-claim extension.'
    $domainName = $upn.Split('@')[1]
    $domain = Invoke-Graph -Method GET -Uri ('https://graph.microsoft.com/v1.0/domains/' + [uri]::EscapeDataString($domainName))
    if ($domain.isVerified -ne $true) { throw 'The configured approver sign-in domain is not verified in this directory.' }
    $extensionName = "extension_$($apiClientId.ToString('N'))_applicationTenantCode"
    $stage = 'verify-api-tenant-claim-extension'
    $apiApps = @(Invoke-Graph -Method GET -Uri "https://graph.microsoft.com/v1.0/applications?`$filter=appId%20eq%20%27$apiClientId%27&`$select=id,appId")
    if (@($apiApps.value).Count -ne 1) { throw 'Expected exactly one API application registration in the approved directory.' }
    $extensionRows = Invoke-Graph -Method GET -Uri "https://graph.microsoft.com/v1.0/applications/$($apiApps.value[0].id)/extensionProperties?`$select=name,targetObjects"
    $tenantExtensions = @($extensionRows.value | Where-Object { $_.name -ceq $extensionName -and $_.targetObjects -contains 'User' })
    if ($tenantExtensions.Count -ne 1) { throw 'The API-owned applicationTenantCode user extension is missing or ambiguous.' }
    $stage = 'lookup-approver-account'
    Write-Host '[Phase 10] Checking whether the dedicated approver account already exists.'
    $filter = [uri]::EscapeDataString("userPrincipalName eq '$upn'")
    $matches = Invoke-Graph -Method GET -Uri "https://graph.microsoft.com/v1.0/users?`$filter=$filter&`$select=id,userPrincipalName,userType,accountEnabled"
    if (@($matches.value).Count -gt 1) { throw 'The approver UPN resolved ambiguously.' }
    $existing = if (@($matches.value).Count -eq 1) { $matches.value[0] } else { $null }
    if ($existing -and ($existing.userType -cne 'Member' -or $existing.accountEnabled -ne $true)) { throw 'An existing account uses the approver UPN but is not an enabled organizational Member.' }
    if ($existing) {
        $existing = Invoke-Graph -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$($existing.id)?`$select=id,userPrincipalName,userType,accountEnabled,$extensionName"
        if ([string]$existing.$extensionName -and [string]$existing.$extensionName -cne 'TenantA') { throw 'Existing approver account has a conflicting application tenant claim.' }
        if ([string]$existing.id -eq [string]$runnerId -or [string]$existing.id -in @($manifest.tenantTestUserObjectIds | ForEach-Object { [string]$_ })) { throw 'Existing approver account conflicts with a replay runner or tenant-isolation test account.' }
    }
    $status = if ($existing -and [string]$existing.$extensionName -ceq 'TenantA') { 'already-provisioned' } elseif ($Mode -eq 'Plan') { 'planned' } elseif ($Mode -eq 'Verify') { 'failed' } else { 'planned' }
    if ($Mode -eq 'Apply' -and $status -ne 'already-provisioned') {
        if (-not $PSBoundParameters.ContainsKey('Confirm')) { throw 'Apply requires the explicit -Confirm switch.' }
        $stage = 'await-account-creation-confirmation'
        Write-AccountStatus -Status 'awaiting-operator-confirmation' -Stage $stage
        Write-Host '[Phase 10] Preflight passed. No directory changes have happened yet.'
        Write-Host '[Phase 10] The next prompt requires typing: CREATE DEV REPLAY APPROVER'
        $phrase = Read-Host 'This creates one DEV organizational Member for the replay approver and assigns only the TenantA application claim. Type CREATE DEV REPLAY APPROVER'
        if ($phrase -cne 'CREATE DEV REPLAY APPROVER') { throw 'Apply cancelled; no directory changes were made.' }
        Write-Host '[Phase 10] Phrase accepted. Next, approve the PowerShell ShouldProcess confirmation.'
        if (-not $PSCmdlet.ShouldProcess('Dedicated Phase 10 replay approver in Azure dev','Create Member and set TenantA application claim')) { throw 'Apply stopped by ShouldProcess; no directory changes were made.' }
        if (-not $existing) {
            $stage = 'create-member'
            Write-AccountStatus -Status 'awaiting-secure-password' -Stage $stage
            Write-Host '[Phase 10] Enter the unique temporary password at the secure prompt. It will not be echoed or saved.'
            $credential = Read-TemporaryPassword
            try {
                $created = Invoke-Graph -Method POST -Uri 'https://graph.microsoft.com/v1.0/users' -Body @{
                    accountEnabled=$true; displayName=[string]$manifest.approverDisplayName; mailNickname=$upn.Split('@')[0]; userPrincipalName=$upn
                    passwordProfile=@{password=$credential.Plain;forceChangePasswordNextSignIn=$true}
                }
            } finally { $credential.Secure.Dispose(); $credential.Plain=$null; $credential=$null }
            if (-not $created.id) { throw 'Graph did not return the created user ID; inspect Entra before retrying.' }
            $manifest.approverObjectId = [string]$created.id
            Save-PrivateManifest -Path $manifestFullPath -Value $manifest
            $existing = $created
            Write-AccountStatus -Status 'member-created-claim-pending' -Stage 'set-tenant-claim'
        }
        $stage = 'set-tenant-claim'
        $claimBody = @{}; $claimBody[$extensionName] = 'TenantA'
        [void](Invoke-Graph -Method PATCH -Uri "https://graph.microsoft.com/v1.0/users/$($existing.id)" -Body $claimBody)
        $verified = Invoke-Graph -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$($existing.id)?`$select=id,userPrincipalName,userType,accountEnabled,$extensionName"
        if ([string]$verified.id -cne [string]$existing.id -or $verified.userType -cne 'Member' -or $verified.accountEnabled -ne $true -or [string]$verified.$extensionName -cne 'TenantA') { throw 'Post-write verification failed; inspect Entra before retrying.' }
        $manifest.approverObjectId = [string]$verified.id
        Save-PrivateManifest -Path $manifestFullPath -Value $manifest
        $existing = $verified; $status = 'created-and-claim-verified'
    }
    if ($Mode -eq 'Verify' -and $status -ne 'already-provisioned') { throw 'Replay approver account is not yet created with the expected claim.' }
    $summary = [ordered]@{schema='phase10-entra-replay-approver-account-v1';mode=$Mode.ToLowerInvariant();status=$status;environment='dev';tenantCode='TenantA';accountPresent=[bool]$existing;claimVerified=($status -in @('already-provisioned','created-and-claim-verified'));accountIdStoredOnlyInPrivateManifest=($Mode -eq 'Apply' -and $status -eq 'created-and-claim-verified');emailsSent=0;credentialsStored=$false;passwordLogged=$false}
    $summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM -Confirm:$false
    [pscustomobject]@{tenantCode='TenantA';action=if($status -eq 'already-provisioned'){'no-change'}else{'create-member-and-assign-tenant-claim'};status=$status} | Format-Table -AutoSize
    if ($Mode -eq 'Apply' -and $status -eq 'created-and-claim-verified') { Write-Host 'Account is ready for the separate phase10-operator app-role Plan/Apply/Verify workflow. First sign-in and MFA must be completed by the account owner.' }
    Write-Host "Sanitized report: $reportPath"
    if ($Mode -eq 'Verify' -and $status -ne 'already-provisioned') { exit 1 }
} catch {
    Write-AccountStatus -Status 'failed-or-partial' -Stage $stage
    Write-Host "Sanitized report: $reportPath"
    throw 'Replay approver account provisioning stopped; inspect Entra and the sanitized report before retrying.'
} finally { $script:graphAccessToken=$null; $tokenClaims=$null; $tokenPayload=$null; $graphGrants=$null }
