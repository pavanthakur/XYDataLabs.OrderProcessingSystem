#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'phase10-entra-member-test-users.module.psm1'
Import-Module $modulePath -Force
$script:assertions = 0
function Assert-Equal($actual,$expected,[string]$label) { $script:assertions++; if ($actual -cne $expected) { throw "Assertion failed: $label." } }
function Assert-Throws([scriptblock]$action,[string]$label) { $script:assertions++; try { & $action } catch { return }; throw "Expected refusal: $label." }

$directory = [guid]'2fc13fdf-ddcb-4adb-91d4-58f1632a1c6f'
$api = [guid]'4c9b3b48-5223-4de3-b572-d820e69f6321'
$inputManifest = [pscustomobject]@{
    schemaVersion=1; environment='dev'; identityType='member'; directoryId=$directory.ToString(); apiClientId=$api.ToString(); signInDomain='tenant.onmicrosoft.com'
    users=@(
        [pscustomobject]@{tenantCode='TenantA';displayName='Phase 10 A';userPrincipalName='phase10-a@tenant.onmicrosoft.com';objectId=''},
        [pscustomobject]@{tenantCode='TenantB';displayName='Phase 10 B';userPrincipalName='phase10-b@tenant.onmicrosoft.com';objectId=''},
        [pscustomobject]@{tenantCode='TenantC';displayName='Phase 10 C';userPrincipalName='phase10-c@tenant.onmicrosoft.com';objectId=''}
    )
}
$manifest = ConvertTo-Phase10EntraMemberTestManifest -InputObject $inputManifest -ExpectedDirectoryId $directory
Assert-Equal $manifest.users.Count 3 'three distinct member accounts'
Assert-Equal $manifest.identityType 'member' 'identity type is explicit'
$guestManifest = $inputManifest | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$guestManifest.identityType='guest'
Assert-Throws { ConvertTo-Phase10EntraMemberTestManifest -InputObject $guestManifest -ExpectedDirectoryId $directory } 'guest manifest cannot enter member flow'
$badDomain = $inputManifest | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$badDomain.users[0].userPrincipalName='personal@gmail.com'
Assert-Throws { ConvertTo-Phase10EntraMemberTestManifest -InputObject $badDomain -ExpectedDirectoryId $directory } 'consumer Gmail UPN is rejected'
$badGuest = $inputManifest | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$badGuest.users[0].userPrincipalName='phase10-a_example.com#EXT#@tenant.onmicrosoft.com'
Assert-Throws { ConvertTo-Phase10EntraMemberTestManifest -InputObject $badGuest -ExpectedDirectoryId $directory } 'guest UPN is rejected'
$duplicate = $inputManifest | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$duplicate.users[1].userPrincipalName=$duplicate.users[0].userPrincipalName
Assert-Throws { ConvertTo-Phase10EntraMemberTestManifest -InputObject $duplicate -ExpectedDirectoryId $directory } 'duplicate sign-ins are rejected'
Assert-Throws { ConvertTo-Phase10EntraMemberTestManifest -InputObject $inputManifest -ExpectedDirectoryId ([guid]::NewGuid()) } 'wrong directory is rejected'

$active = @('TenantA','TenantB','TenantC')
$missing = @(New-Phase10EntraMemberTestUserPlan -Manifest $manifest -ActiveTenantCodes $active -DirectoryUsers @())
Assert-Equal (@($missing | Where-Object action -eq 'create-member-and-assign-tenant').Count) 3 'missing users are planned without writes'
$present = @(
    [pscustomobject]@{id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';userPrincipalName='phase10-a@tenant.onmicrosoft.com';userType='Member';accountEnabled=$true;applicationTenantCode='TenantA';apiRoles=@()},
    [pscustomobject]@{id='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';userPrincipalName='phase10-b@tenant.onmicrosoft.com';userType='Member';accountEnabled=$true;applicationTenantCode='';apiRoles=@()},
    [pscustomobject]@{id='cccccccc-cccc-cccc-cccc-cccccccccccc';userPrincipalName='phase10-c@tenant.onmicrosoft.com';userType='Member';accountEnabled=$true;applicationTenantCode='TenantC';apiRoles=@()}
)
$plan = @(New-Phase10EntraMemberTestUserPlan -Manifest $manifest -ActiveTenantCodes $active -DirectoryUsers $present)
Assert-Equal (@($plan | Where-Object action -eq 'no-change').Count) 2 'correct existing claims are preserved'
Assert-Equal (@($plan | Where-Object action -eq 'assign-tenant-claim').Count) 1 'only missing claim is proposed'
Assert-Throws { New-Phase10EntraMemberTestUserPlan -Manifest $manifest -ActiveTenantCodes @('TenantA','TenantB','TenantC','TenantD') -DirectoryUsers @() } 'unmapped active tenant blocks provisioning'
$guest = @($present | ForEach-Object { if ($_.userPrincipalName -eq 'phase10-b@tenant.onmicrosoft.com') { $_.userType='Guest' }; $_ })
Assert-Throws { New-Phase10EntraMemberTestUserPlan -Manifest $manifest -ActiveTenantCodes $active -DirectoryUsers $guest } 'existing guest is never converted'
$conflict = @($present | ForEach-Object { if ($_.userPrincipalName -eq 'phase10-b@tenant.onmicrosoft.com') { $_.applicationTenantCode='TenantC' }; $_ })
Assert-Throws { New-Phase10EntraMemberTestUserPlan -Manifest $manifest -ActiveTenantCodes $active -DirectoryUsers $conflict } 'conflicting tenant claim is not overwritten'
$privileged = @($present | ForEach-Object { if ($_.userPrincipalName -eq 'phase10-b@tenant.onmicrosoft.com') { $_.apiRoles=@('platform-admin') }; $_ })
Assert-Throws { New-Phase10EntraMemberTestUserPlan -Manifest $manifest -ActiveTenantCodes $active -DirectoryUsers $privileged } 'privileged account is rejected'

$runner = Get-Content (Join-Path (Split-Path -Parent $PSScriptRoot) 'phase10-entra-member-test-users.ps1') -Raw
Assert-Equal ([bool]($runner -match 'forceChangePasswordNextSignIn=\$true')) $true 'initial password rotation is required'
Assert-Equal ([bool]($runner -match 'Read-Host .*AsSecureString')) $true 'temporary password uses secure prompt'
Assert-Equal ([bool]($runner -match 'passwordsStored=\$false')) $true 'passwords are not persisted in reports'
Assert-Equal ([bool]($runner -match 'emailsSent=0')) $true 'member flow does not send invitations'
Assert-Equal ([bool]($runner -match 'APPLY DEV MEMBER TEST USERS')) $true 'writes require typed confirmation'
Assert-Equal ([bool]($runner -match 'UserPrincipalName.*must be stored outside the repository|must be outside the repository')) $true 'identity manifest remains outside source control'

Write-Host "Phase 10 Entra member test-user tests passed ($script:assertions assertions)."
