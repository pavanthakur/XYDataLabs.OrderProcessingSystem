Set-StrictMode -Version Latest

function ConvertTo-Phase10EntraTestUserManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$InputObject, [Parameter(Mandatory)][guid]$ExpectedDirectoryId)

    if ($InputObject.schemaVersion -ne 1 -or $InputObject.environment -cne 'dev') {
        throw 'Manifest must use schemaVersion 1 and environment dev.'
    }
    $directoryId = [guid]::Empty
    if (-not [guid]::TryParse([string]$InputObject.directoryId, [ref]$directoryId) -or $directoryId -ne $ExpectedDirectoryId) {
        throw 'Manifest directoryId does not match the explicitly confirmed Entra directory.'
    }
    $apiClientId = [guid]::Empty
    if (-not [guid]::TryParse([string]$InputObject.apiClientId, [ref]$apiClientId)) {
        throw 'Manifest apiClientId must be a valid API application client ID.'
    }
    $users = @($InputObject.users)
    if ($users.Count -eq 0) { throw 'Manifest must contain one regular-user mapping for every active tenant.' }
    $normalized = @()
    foreach ($user in $users) {
        $tenantCode = ([string]$user.tenantCode).Trim()
        $email = ([string]$user.email).Trim()
        if ([string]::IsNullOrWhiteSpace($tenantCode) -or $tenantCode -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$') {
            throw 'Manifest contains an invalid tenant code.'
        }
        if ($email -notmatch '^[^\s@]+@[^\s@]+\.[^\s@]+$') { throw "Manifest email for tenant $tenantCode is invalid." }
        $objectId = ''
        if (-not [string]::IsNullOrWhiteSpace([string]$user.objectId)) {
            $parsedObjectId = [guid]::Empty
            if (-not [guid]::TryParse([string]$user.objectId, [ref]$parsedObjectId)) { throw "Manifest objectId for tenant $tenantCode is invalid." }
            $objectId = $parsedObjectId.ToString('D')
        }
        $normalized += [pscustomobject]@{ tenantCode = $tenantCode; email = $email; objectId = $objectId }
    }
    $duplicateTenants = @($normalized | Group-Object { $_.tenantCode.ToLowerInvariant() } | Where-Object Count -gt 1)
    $duplicateEmails = @($normalized | Group-Object { $_.email.ToLowerInvariant() } | Where-Object Count -gt 1)
    $duplicateIds = @($normalized | Where-Object objectId | Group-Object objectId | Where-Object Count -gt 1)
    if ($duplicateTenants.Count -gt 0 -or $duplicateEmails.Count -gt 0 -or $duplicateIds.Count -gt 0) {
        throw 'Manifest contains duplicate tenant, email, or directory-object mappings.'
    }
    return [pscustomobject]@{
        schemaVersion = 1
        environment = 'dev'
        directoryId = $directoryId.ToString('D')
        apiClientId = $apiClientId.ToString('D')
        users = @($normalized | Sort-Object tenantCode)
    }
}

function Get-Phase10EntraExtensionPropertyName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][guid]$ApiClientId)
    return "extension_$($ApiClientId.ToString('N'))_applicationTenantCode"
}

function Assert-Phase10EntraApiIdentityConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Application,
        [Parameter(Mandatory)][object[]]$ExtensionProperties,
        [Parameter(Mandatory)][guid]$ApiClientId
    )
    $extensionName = Get-Phase10EntraExtensionPropertyName -ApiClientId $ApiClientId
    $accessTokenClaims = @($Application.optionalClaims.accessToken | ForEach-Object { [string]$_.name })
    $hasTenantClaim = $accessTokenClaims -contains $extensionName
    $scopes = @($Application.api.oauth2PermissionScopes | Where-Object { $_.isEnabled -eq $true } | ForEach-Object { [string]$_.value })
    $registeredExtension = @($ExtensionProperties | Where-Object { $_.name -ceq $extensionName -and @($_.targetObjects) -contains 'User' })
    if (-not $hasTenantClaim -or 'access_as_user' -notin $scopes -or $registeredExtension.Count -ne 1) {
        throw 'API app is missing the required user directory extension, API access token claim, or access_as_user delegated scope. No user writes are allowed.'
    }
    return $extensionName
}

function Get-Phase10ActiveTenantCodesFromRuntimeResponse {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Response)

    $runtime = $Response
    if ($Response.PSObject.Properties.Name -contains 'data' -and $null -ne $Response.data) { $runtime = $Response.data }
    if ($runtime.PSObject.Properties.Name -notcontains 'availableTenants') {
        throw 'Runtime response is missing availableTenants.'
    }
    $codes = @($runtime.availableTenants | ForEach-Object { ([string]$_.tenantCode).Trim() } | Where-Object { $_ })
    if ($codes.Count -eq 0) { throw 'Runtime response contains no active tenants.' }
    if (@($codes | Group-Object { $_.ToLowerInvariant() } | Where-Object Count -gt 1).Count -gt 0) {
        throw 'Runtime response contains duplicate tenant codes.'
    }
    return $codes
}

function New-Phase10EntraTestUserPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Manifest,
        [Parameter(Mandatory)][string[]]$ActiveTenantCodes,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$DirectoryUsers
    )

    $active = @($ActiveTenantCodes | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Sort-Object -Unique)
    if ($active.Count -eq 0) { throw 'Runtime discovery returned no active tenants.' }
    $configured = @($Manifest.users | ForEach-Object { $_.tenantCode } | Sort-Object -Unique)
    $missing = @($active | Where-Object { $_ -notin $configured })
    $extra = @($configured | Where-Object { $_ -notin $active })
    if ($missing.Count -gt 0 -or $extra.Count -gt 0) {
        throw 'Manifest must map exactly one account to every active tenant; topology and manifest differ.'
    }

    $plan = @()
    foreach ($mapping in $Manifest.users) {
        $matches = @($DirectoryUsers | Where-Object {
            ($mapping.objectId -and [string]$_.id -eq $mapping.objectId) -or
            ([string]$_.email -and [string]$_.email -ieq $mapping.email) -or
            ([string]$_.mail -and [string]$_.mail -ieq $mapping.email) -or
            ([string]$_.userPrincipalName -and [string]$_.userPrincipalName -ieq $mapping.email)
        } | Sort-Object id -Unique)
        if ($matches.Count -gt 1) { throw "Multiple Entra users match the manifest mapping for $($mapping.tenantCode); operator review required." }
        if ($matches.Count -eq 0) {
            if ($mapping.objectId) { throw "Recorded Entra object for $($mapping.tenantCode) no longer resolves; refusing to create a replacement." }
            $plan += [pscustomobject]@{ tenantCode = $mapping.tenantCode; action = 'invite-guest-and-assign-tenant'; status = 'planned'; objectId = '' }
            continue
        }

        $directoryUser = $matches[0]
        if ($directoryUser.accountEnabled -eq $false) { throw "Entra user for $($mapping.tenantCode) is disabled; do not enable automatically." }
        $assignedTenant = [string]$directoryUser.applicationTenantCode
        if ($assignedTenant -and $assignedTenant -cne $mapping.tenantCode) {
            throw "Entra user for $($mapping.tenantCode) already has a conflicting tenant assignment; no overwrite is allowed."
        }
        $roles = @($directoryUser.apiRoles | ForEach-Object { [string]$_ })
        if ($roles -contains 'platform-admin' -or $roles -contains 'phase10-operator') {
            throw "Entra user for $($mapping.tenantCode) has a privileged API role; remove it through separate review before regular-user testing."
        }
        if ([string]$directoryUser.userType -ceq 'Guest' -and [string]$directoryUser.externalUserState -cne 'Accepted') {
            $plan += [pscustomobject]@{ tenantCode = $mapping.tenantCode; action = 'await-invitation-redemption'; status = 'pending-redemption'; objectId = [string]$directoryUser.id }
            continue
        }
        $action = if ($assignedTenant -ceq $mapping.tenantCode) { 'no-change' } else { 'assign-tenant-claim' }
        $plan += [pscustomobject]@{ tenantCode = $mapping.tenantCode; action = $action; status = 'planned'; objectId = [string]$directoryUser.id }
    }
    return @($plan | Sort-Object tenantCode)
}

Export-ModuleMember -Function ConvertTo-Phase10EntraTestUserManifest, Get-Phase10EntraExtensionPropertyName, Assert-Phase10EntraApiIdentityConfiguration, Get-Phase10ActiveTenantCodesFromRuntimeResponse, New-Phase10EntraTestUserPlan
