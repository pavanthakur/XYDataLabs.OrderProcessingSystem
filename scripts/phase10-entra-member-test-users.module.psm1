Set-StrictMode -Version Latest

function ConvertTo-Phase10EntraMemberTestManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$InputObject, [Parameter(Mandatory)][guid]$ExpectedDirectoryId)

    if ($InputObject.schemaVersion -ne 1 -or $InputObject.environment -cne 'dev' -or $InputObject.identityType -cne 'member') {
        throw 'Manifest must use schemaVersion 1, environment dev, and identityType member.'
    }
    $directoryId = [guid]::Empty
    $apiClientId = [guid]::Empty
    if (-not [guid]::TryParse([string]$InputObject.directoryId, [ref]$directoryId) -or $directoryId -ne $ExpectedDirectoryId) {
        throw 'Manifest directoryId does not match the explicitly confirmed Entra directory.'
    }
    if (-not [guid]::TryParse([string]$InputObject.apiClientId, [ref]$apiClientId)) { throw 'Manifest apiClientId must be a valid API application client ID.' }
    $domain = ([string]$InputObject.signInDomain).Trim().TrimStart('@').ToLowerInvariant()
    if ($domain -notmatch '^(?=.{1,253}$)[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$') {
        throw 'Manifest signInDomain must be a verified Entra sign-in domain.'
    }
    $users = @()
    foreach ($user in @($InputObject.users)) {
        $tenantCode = ([string]$user.tenantCode).Trim()
        $upn = ([string]$user.userPrincipalName).Trim().ToLowerInvariant()
        $displayName = ([string]$user.displayName).Trim()
        if ($tenantCode -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$') { throw 'Manifest contains an invalid tenant code.' }
        if ($upn -notmatch '^[A-Za-z0-9.!#$%&''*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+$' -or $upn.Split('@')[-1] -cne $domain -or $upn -match '#ext#') {
            throw "Manifest sign-in UPN for $tenantCode must use the configured verified organizational domain; guest/MSA identities are not accepted."
        }
        if ([string]::IsNullOrWhiteSpace($displayName) -or $displayName.Length -gt 128) { throw "Manifest displayName for $tenantCode is invalid." }
        $objectId = ''
        if (-not [string]::IsNullOrWhiteSpace([string]$user.objectId)) {
            $parsed = [guid]::Empty
            if (-not [guid]::TryParse([string]$user.objectId, [ref]$parsed)) { throw "Manifest objectId for $tenantCode is invalid." }
            $objectId = $parsed.ToString('D')
        }
        $users += [pscustomobject]@{ tenantCode = $tenantCode; userPrincipalName = $upn; displayName = $displayName; objectId = $objectId }
    }
    if ($users.Count -eq 0) { throw 'Manifest must contain a regular member identity for each active tenant.' }
    if (@($users | Group-Object { $_.tenantCode.ToLowerInvariant() } | Where-Object Count -gt 1).Count -gt 0 -or
        @($users | Group-Object { $_.userPrincipalName.ToLowerInvariant() } | Where-Object Count -gt 1).Count -gt 0 -or
        @($users | Where-Object objectId | Group-Object objectId | Where-Object Count -gt 1).Count -gt 0) {
        throw 'Manifest contains duplicate tenant, UPN, or directory-object mappings.'
    }
    return [pscustomobject]@{ schemaVersion = 1; environment = 'dev'; identityType = 'member'; directoryId = $directoryId.ToString('D'); apiClientId = $apiClientId.ToString('D'); signInDomain = $domain; users = @($users | Sort-Object tenantCode) }
}

function New-Phase10EntraMemberTestUserPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Manifest,
        [Parameter(Mandatory)][string[]]$ActiveTenantCodes,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$DirectoryUsers
    )
    $active = @($ActiveTenantCodes | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Sort-Object -Unique)
    if ($active.Count -eq 0) { throw 'Runtime discovery returned no active tenants.' }
    $configured = @($Manifest.users | ForEach-Object { $_.tenantCode } | Sort-Object -Unique)
    if (@($active | Where-Object { $_ -notin $configured }).Count -gt 0 -or @($configured | Where-Object { $_ -notin $active }).Count -gt 0) {
        throw 'Manifest must map exactly one organizational member account to every active tenant.'
    }
    $plan = @()
    foreach ($mapping in $Manifest.users) {
        $matches = @($DirectoryUsers | Where-Object {
            ($mapping.objectId -and [string]$_.id -eq $mapping.objectId) -or
            ([string]$_.userPrincipalName -and [string]$_.userPrincipalName -ieq $mapping.userPrincipalName)
        } | Sort-Object id -Unique)
        if ($matches.Count -gt 1) { throw "Multiple Entra objects match the organizational account for $($mapping.tenantCode)." }
        if ($matches.Count -eq 0) {
            if ($mapping.objectId) { throw "Pinned Entra object for $($mapping.tenantCode) no longer resolves; refusing to replace it." }
            $plan += [pscustomobject]@{ tenantCode = $mapping.tenantCode; userPrincipalName = $mapping.userPrincipalName; action = 'create-member-and-assign-tenant'; status = 'planned'; objectId = '' }
            continue
        }
        $user = $matches[0]
        if ([string]$user.userType -cne 'Member') { throw "Account for $($mapping.tenantCode) is not an organizational Member; guest/MSA accounts are not accepted." }
        if ($user.accountEnabled -eq $false) { throw "Account for $($mapping.tenantCode) is disabled; do not enable automatically." }
        $assignedTenant = [string]$user.applicationTenantCode
        if ($assignedTenant -and $assignedTenant -cne $mapping.tenantCode) { throw "Account for $($mapping.tenantCode) has a conflicting tenant claim; no overwrite is allowed." }
        $roles = @($user.apiRoles | ForEach-Object { [string]$_ })
        if ($roles | Where-Object { $_ -in @('platform-admin','phase10-operator') }) { throw "Account for $($mapping.tenantCode) has a privileged API role; resolve separately before isolation testing." }
        $action = if ($assignedTenant -ceq $mapping.tenantCode) { 'no-change' } else { 'assign-tenant-claim' }
        $plan += [pscustomobject]@{ tenantCode = $mapping.tenantCode; userPrincipalName = $mapping.userPrincipalName; action = $action; status = 'planned'; objectId = [string]$user.id }
    }
    return @($plan | Sort-Object tenantCode)
}

function Get-Phase10GraphNextLink {
    param([Parameter(Mandatory)][object]$Page)
    $property = $Page.PSObject.Properties['@odata.nextLink']
    if ($null -eq $property -or [string]::IsNullOrWhiteSpace([string]$property.Value)) { return $null }
    return [string]$property.Value
}

Export-ModuleMember -Function ConvertTo-Phase10EntraMemberTestManifest, New-Phase10EntraMemberTestUserPlan, Get-Phase10GraphNextLink
