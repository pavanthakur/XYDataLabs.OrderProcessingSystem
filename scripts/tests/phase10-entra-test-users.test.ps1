#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'phase10-entra-test-users.module.psm1') -Force
$script:assertions = 0
function Assert-Equal($actual, $expected, [string]$message) {
    $script:assertions++
    if ($actual -cne $expected) { throw "Assertion failed: $message (expected '$expected', got '$actual')." }
}
function Assert-Throws([scriptblock]$Action, [string]$message) {
    $script:assertions++
    try { & $Action } catch { return }
    throw "Assertion failed: expected refusal for $message."
}

$directory = [guid]'2fc13fdf-ddcb-4adb-91d4-58f1632a1c6f'
$api = [guid]'4c9b3b48-5223-4de3-b572-d820e69f6321'
$manifest = [pscustomobject]@{
    schemaVersion = 1; environment = 'dev'; directoryId = $directory.ToString(); apiClientId = $api.ToString()
    users = @(
        [pscustomobject]@{ tenantCode = 'TenantA'; email = 'a@example.test'; objectId = '' },
        [pscustomobject]@{ tenantCode = 'TenantB'; email = 'b@example.test'; objectId = '' },
        [pscustomobject]@{ tenantCode = 'TenantC'; email = 'c@example.test'; objectId = '' }
    )
}
$normalized = ConvertTo-Phase10EntraTestUserManifest -InputObject $manifest -ExpectedDirectoryId $directory
Assert-Equal $normalized.users.Count 3 'manifest mappings retained'
$extensionName = Get-Phase10EntraExtensionPropertyName -ApiClientId $api
Assert-Equal $extensionName 'extension_4c9b3b4852234de3b572d820e69f6321_applicationTenantCode' 'API-owned directory extension name'
$apiApplication = [pscustomobject]@{
    optionalClaims = [pscustomobject]@{ accessToken = @([pscustomobject]@{ name = 'extension_4c9b3b4852234de3b572d820e69f6321_applicationTenantCode' }) }
    api = [pscustomobject]@{ oauth2PermissionScopes = @([pscustomobject]@{ value='access_as_user'; isEnabled=$true }) }
}
$extensionRows = @([pscustomobject]@{ name=$extensionName; targetObjects=@('User') })
Assert-Equal (Assert-Phase10EntraApiIdentityConfiguration -Application $apiApplication -ExtensionProperties $extensionRows -ApiClientId $api) $extensionName 'API-owned access-token claim and delegated scope'
Assert-Throws { Assert-Phase10EntraApiIdentityConfiguration -Application ([pscustomobject]@{ api=[pscustomobject]@{ oauth2PermissionScopes=@() }; optionalClaims=[pscustomobject]@{accessToken=@()} }) -ExtensionProperties @() -ApiClientId $api } 'missing API tenant claim configuration'
$directRuntime = [pscustomobject]@{ availableTenants=@([pscustomobject]@{tenantCode='TenantA'},[pscustomobject]@{tenantCode='TenantB'}) }
Assert-Equal (@(Get-Phase10ActiveTenantCodesFromRuntimeResponse -Response $directRuntime).Count) 2 'direct runtime response tenant discovery'
$wrappedRuntime = [pscustomobject]@{ data=$directRuntime }
Assert-Equal (@(Get-Phase10ActiveTenantCodesFromRuntimeResponse -Response $wrappedRuntime).Count) 2 'wrapped runtime response tenant discovery'
Assert-Throws { Get-Phase10ActiveTenantCodesFromRuntimeResponse -Response ([pscustomobject]@{ availableTenants=@() }) } 'empty active tenant response'

$tenants = @('TenantA','TenantB','TenantC')
$missingPlan = @(New-Phase10EntraTestUserPlan -Manifest $normalized -ActiveTenantCodes $tenants -DirectoryUsers @())
Assert-Equal (@($missingPlan | Where-Object action -eq 'invite-guest-and-assign-tenant').Count) 3 'missing users are planned for invitation'
Assert-Equal (@($missingPlan | Where-Object status -ne 'planned').Count) 0 'plan remains non-mutating'

$existingUsers = @(
    [pscustomobject]@{ id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; email = 'a@example.test'; mail = 'a@example.test'; userPrincipalName = 'a_example.test#EXT#@tenant.onmicrosoft.com'; userType = 'Member'; externalUserState = ''; accountEnabled = $true; applicationTenantCode = 'TenantA'; apiRoles = @() },
    [pscustomobject]@{ id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'; email = 'b@example.test'; mail = 'b@example.test'; userPrincipalName = 'b_example.test#EXT#@tenant.onmicrosoft.com'; userType = 'Member'; externalUserState = ''; accountEnabled = $true; applicationTenantCode = ''; apiRoles = @() },
    [pscustomobject]@{ id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'; email = 'c@example.test'; mail = 'c@example.test'; userPrincipalName = 'c_example.test#EXT#@tenant.onmicrosoft.com'; userType = 'Member'; externalUserState = ''; accountEnabled = $true; applicationTenantCode = 'TenantC'; apiRoles = @() }
)
$existingPlan = @(New-Phase10EntraTestUserPlan -Manifest $normalized -ActiveTenantCodes $tenants -DirectoryUsers $existingUsers)
Assert-Equal (@($existingPlan | Where-Object action -eq 'no-change').Count) 2 'correct assignments are preserved'
Assert-Equal (@($existingPlan | Where-Object action -eq 'assign-tenant-claim').Count) 1 'only a missing claim is planned'
$pendingGuest = @($existingUsers | ForEach-Object { if ($_.email -eq 'b@example.test') { $_.userType='Guest'; $_.externalUserState='PendingAcceptance'; $_.applicationTenantCode='TenantB' }; $_ })
$pendingPlan = @(New-Phase10EntraTestUserPlan -Manifest $normalized -ActiveTenantCodes $tenants -DirectoryUsers $pendingGuest)
Assert-Equal (@($pendingPlan | Where-Object action -eq 'await-invitation-redemption').Count) 1 'pending guest invitation blocks verification and repeat apply'
Assert-Equal ([bool](@($pendingPlan | Where-Object tenantCode -eq 'TenantB')[0].objectId)) $true 'pending guest is pinned for safe resend'

Assert-Throws { New-Phase10EntraTestUserPlan -Manifest $normalized -ActiveTenantCodes @('TenantA','TenantB','TenantC','TenantD') -DirectoryUsers @() } 'unmapped active tenant'
Assert-Throws { New-Phase10EntraTestUserPlan -Manifest $normalized -ActiveTenantCodes @('TenantA','TenantB') -DirectoryUsers @() } 'extra manifest tenant'
$conflict = @($existingUsers | ForEach-Object { if ($_.email -eq 'b@example.test') { $_.applicationTenantCode = 'TenantC' }; $_ })
Assert-Throws { New-Phase10EntraTestUserPlan -Manifest $normalized -ActiveTenantCodes $tenants -DirectoryUsers $conflict } 'conflicting assignment'
$privileged = @($existingUsers | ForEach-Object { if ($_.email -eq 'b@example.test') { $_.apiRoles = @('platform-admin') }; $_ })
Assert-Throws { New-Phase10EntraTestUserPlan -Manifest $normalized -ActiveTenantCodes $tenants -DirectoryUsers $privileged } 'privileged regular user'
$disabled = @($existingUsers | ForEach-Object { if ($_.email -eq 'b@example.test') { $_.accountEnabled = $false }; $_ })
Assert-Throws { New-Phase10EntraTestUserPlan -Manifest $normalized -ActiveTenantCodes $tenants -DirectoryUsers $disabled } 'disabled account'
$duplicates = @($existingUsers) + @($existingUsers[0])
Assert-Throws { New-Phase10EntraTestUserPlan -Manifest $normalized -ActiveTenantCodes $tenants -DirectoryUsers $duplicates } 'duplicate user matches'
$duplicateManifest = [pscustomobject]@{ schemaVersion=1; environment='dev'; directoryId=$directory.ToString(); apiClientId=$api.ToString(); users=@($manifest.users + $manifest.users[0]) }
Assert-Throws { ConvertTo-Phase10EntraTestUserManifest -InputObject $duplicateManifest -ExpectedDirectoryId $directory } 'duplicate manifest mapping'
Assert-Throws { ConvertTo-Phase10EntraTestUserManifest -InputObject $manifest -ExpectedDirectoryId ([guid]::NewGuid()) } 'wrong directory'

$entry = Get-Content (Join-Path (Split-Path -Parent $PSScriptRoot) 'phase10-entra-test-users.ps1') -Raw
Assert-Equal ([bool]($entry -match 'SupportsShouldProcess\s*=\s*\$true')) $true 'Apply has ShouldProcess protection'
Assert-Equal ([bool]($entry -match "ContainsKey\('Confirm'\)")) $true 'Apply requires explicit -Confirm'
Assert-Equal ([bool]($entry -match 'APPLY DEV TENANT TEST USERS')) $true 'Apply requires a typed phrase'
Assert-Equal ([bool]($entry -match 'RESEND DEV TENANT INVITATIONS')) $true 'resend requires a distinct typed phrase'
Assert-Equal ([bool]($entry -match "'ResendInvitations'")) $true 'resend is a distinct explicit mode'
Assert-Equal ([bool]($entry -match 'resetRedemption\s*=\s*\$true')) $true 'resend uses the existing guest identity'
Assert-Equal ([bool]($entry -match 'deliveryVerified\s*=\s*\$false')) $true 'resend does not claim email delivery'
Assert-Equal ([bool]($entry -match 'claimsChanged\s*=\s*0')) $true 'resend does not modify tenant claims'
Assert-Equal ([bool]($entry -match "ValidateSet\('Plan','Apply','Verify','ResendInvitations','CreateRedemptionLink'\)")) $true 'redemption link creation is explicit'
Assert-Equal ([bool]($entry -match 'sendInvitationMessage\s*=\s*\$false')) $true 'redemption link path never emails guests'
Assert-Equal ([bool]($entry -match 'Set-CurrentUserProtectedFileAcl')) $true 'redemption link file is ACL restricted'
Assert-Equal ([bool]($entry -match 'CREATE DEV REDEMPTION LINK')) $true 'redemption link reset requires target-specific typed phrase'
Assert-Equal ([bool]($entry -match 'reportContainsRedemptionUrl\s*=\s*\$false')) $true 'sanitized reports exclude redemption URL'
Assert-Equal ([bool]($entry -match 'sendInvitationMessage\s*=\s*\$true')) $true 'guest invitation email is explicit'
Assert-Equal ([bool]($entry -match 'rolesAssigned\s*=\s*0')) $true 'script does not assign API roles'
Assert-Equal ([bool]($entry -match 'must be stored outside the repository')) $true 'PII manifest is kept out of Git'
Assert-Equal ([regex]::Matches($entry, 'Verify the ID above against your approved Azure-dev subscription GUID').Count) 1 'subscription confirmation is asked only once'

Write-Host "Phase 10 Entra test-user provisioning tests passed ($script:assertions assertions)."
