[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Auto','xy-phase10','docker')][string]$Project = 'Auto',
    [string]$SettingsPath = (Join-Path $PSScriptRoot '../Resources/Docker/.env.local')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'phase10-docker-safety.ps1')
$settings = Get-Phase10LocalSettings -Path $SettingsPath
$password = $settings.KEYCLOAK_TENANT_ADMIN_PASSWORD
if ([string]::IsNullOrWhiteSpace($password) -or $password.StartsWith('__')) { throw 'Configure the private local Keycloak administrator password.' }
# Fixed loopback target, verified against the expected Compose project/service.
$filterArgs = @('--filter', 'label=com.docker.compose.service=keycloak-local')
if ($Project -ne 'Auto') { $filterArgs += @('--filter', "label=com.docker.compose.project=$Project") }
$ids = @(& docker ps @filterArgs --format '{{.ID}}')
if ($LASTEXITCODE -ne 0 -or $ids.Count -ne 1) { throw 'Exactly one running project-owned local Keycloak container is required.' }
$owner = & docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' $ids[0]
if ($LASTEXITCODE -ne 0 -or $owner -notin @('xy-phase10','docker')) { throw 'Local Keycloak is not owned by an approved project.' }
$Project = $owner
$port = & docker port $ids[0] 8080/tcp
if ($LASTEXITCODE -ne 0 -or !($port -match ':8081$')) { throw 'The local identity port does not match the expected container.' }
$base = 'http://localhost:8081'
$seed = Get-Content -Raw (Join-Path $PSScriptRoot '../Resources/Keycloak/realm-export.json') | ConvertFrom-Json -AsHashtable
$realm = $seed.realm
try {
    $stage = 'verify-realm'
    $publicRealm = Invoke-RestMethod "$base/realms/$realm" -TimeoutSec 15
    if ($publicRealm.realm -ne $realm) { throw 'Unexpected realm.' }
    $admin = if ($env:LOCAL_KEYCLOAK_ADMIN) { $env:LOCAL_KEYCLOAK_ADMIN } else { 'admin' }
    $token = Invoke-RestMethod "$base/realms/master/protocol/openid-connect/token" -Method Post -ContentType 'application/x-www-form-urlencoded' -Body @{
        grant_type='password'; client_id='admin-cli'; username=$admin; password=($env:LOCAL_KEYCLOAK_ADMIN_PASSWORD ?? $password)
    } -TimeoutSec 15
    $headers = @{ Authorization = "Bearer $($token.access_token)" }
    function Invoke-IdentityApi([string]$Path, [string]$Method='Get', $Body=$null) {
        $arguments = @{ Uri="$base/admin/realms/$realm/$Path"; Method=$Method; Headers=$headers; TimeoutSec=15 }
        if ($null -ne $Body) { $arguments.ContentType='application/json'; $arguments.Body=ConvertTo-Json -InputObject $Body -Depth 20 -Compress }
        $response = Invoke-RestMethod @arguments
        if ($response -is [Array]) { foreach ($item in $response) { $item } } elseif ($null -ne $response) { $response }
    }
    $roles = @(Invoke-IdentityApi 'roles')
    foreach ($role in $seed.roles.realm) {
        if ($role.name -notin $roles.name -and $PSCmdlet.ShouldProcess("$Project/$realm/role/$($role.name)", 'Create seed role')) {
            Invoke-IdentityApi 'roles' 'Post' $role | Out-Null
        }
    }
    $stage = 'tenant-attribute-profile'
    $profile = Invoke-IdentityApi 'users/profile'
    $tenantAttribute = $profile.attributes | Where-Object name -eq 'tenant_code'
    if ($tenantAttribute -and ('user' -in $tenantAttribute.permissions.edit -or $tenantAttribute.multivalued -eq $true)) {
        throw 'The tenant assignment attribute must be administrator-managed and single-valued; operator review is required.'
    }
    if ('tenant_code' -notin $profile.attributes.name -and $PSCmdlet.ShouldProcess("$Project/$realm/user-profile", 'Register admin-managed tenant_code attribute')) {
        $profile.attributes = @($profile.attributes) + @(@{ name='tenant_code'; displayName='Application tenant'; permissions=@{ view=@('admin'); edit=@('admin') }; multivalued=$false })
        Invoke-IdentityApi 'users/profile' 'Put' $profile | Out-Null
    }
    foreach ($userSeed in $seed.users) {
        $name = $userSeed.username
        $stage = "seed-user/$name"
        $users = @(Invoke-IdentityApi "users?username=$([Uri]::EscapeDataString($name))&exact=true")
        if ($users.Count -gt 1) { throw 'Ambiguous seeded identity.' }
        if ($users.Count -eq 0) {
            if (!$PSCmdlet.ShouldProcess("$Project/$realm/user/$name", 'Create missing local seed identity')) { continue }
            # Only newly created local accounts receive an initial password.
            $create = @{}
            foreach ($key in $userSeed.Keys) { $create[$key] = $userSeed[$key] }
            $create.credentials = @(@{ type='password'; value=$password; temporary=$false })
            $create.Remove('realmRoles')
            Invoke-IdentityApi 'users' 'Post' $create | Out-Null
            $users = @(Invoke-IdentityApi "users?username=$([Uri]::EscapeDataString($name))&exact=true")
            $stage = "verify-created-user/$name"
        }
        $user = Invoke-IdentityApi "users/$($users[0].id)"
        $profileDefaults = @{}
        foreach ($field in @('firstName','lastName','email')) {
            if ([string]::IsNullOrWhiteSpace($user.$field) -and $userSeed[$field]) { $profileDefaults[$field] = $userSeed[$field] }
        }
        if ($profileDefaults.Count -gt 0 -and $PSCmdlet.ShouldProcess("$Project/$realm/user/$name", 'Complete missing seed profile fields')) {
            Invoke-IdentityApi "users/$($user.id)" 'Put' $profileDefaults | Out-Null
        }
        # Conflicting existing tenant assignments require operator review, not a silent rewrite.
        $existingTenant = [string](@($user.attributes.tenant_code) | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($existingTenant)) {
            if ($PSCmdlet.ShouldProcess("$Project/$realm/user/$name", 'Initialize missing seed tenant assignment')) {
                $userAttributes = @{}
                if ($user.attributes) { foreach ($property in $user.attributes.PSObject.Properties) { $userAttributes[$property.Name] = $property.Value } }
                $userAttributes['tenant_code'] = $userSeed.attributes.tenant_code
                Invoke-IdentityApi "users/$($user.id)" 'Put' @{ attributes=$userAttributes } | Out-Null
            }
        } elseif ($existingTenant -ne $userSeed.attributes.tenant_code[0]) { throw 'An existing seed user has a conflicting tenant assignment.' }
        $assigned = @(Invoke-IdentityApi "users/$($user.id)/role-mappings/realm")
        if ($name -ne 'tenant-admin' -and 'platform-admin' -in $assigned.name) { throw 'A regular seed account has global access; operator review is required.' }
        foreach ($roleName in $userSeed.realmRoles) {
            if ($roleName -notin $assigned.name -and $PSCmdlet.ShouldProcess("$Project/$realm/user/$name", "Assign seed role $roleName")) {
                $role = Invoke-IdentityApi "roles/$roleName"
                Invoke-IdentityApi "users/$($user.id)/role-mappings/realm" 'Post' @($role) | Out-Null
            }
        }
    }
    $stage = 'web-client'
    $clients = @(Invoke-IdentityApi 'clients?clientId=xy-order-processing-local-web')
    if ($clients.Count -ne 1) { throw 'Expected exactly one local web client.' }
    $client = $clients[0]
    $clientSeed = $seed.clients | Where-Object clientId -eq 'xy-order-processing-local-web'
    if (!$client.attributes) { $client | Add-Member attributes @{} }
    $logoutValue = $clientSeed.attributes.'post.logout.redirect.uris'
    if ($client.attributes.'post.logout.redirect.uris' -ne $logoutValue -and $PSCmdlet.ShouldProcess("$Project/$realm/web-client", 'Register exact local logout URLs')) {
        $attributes = @{}
        foreach ($property in $client.attributes.PSObject.Properties) { $attributes[$property.Name] = $property.Value }
        $attributes['post.logout.redirect.uris'] = $logoutValue
        Invoke-IdentityApi "clients/$($client.id)" 'Put' @{ attributes=$attributes } | Out-Null
    }
    Write-Host 'Local identity seed reconciliation completed. Existing passwords and unrelated resources were preserved.'
} catch {
    # HTTP exception payloads can contain request credentials; never print them.
    throw "Local identity reconciliation failed at $stage ($($_.Exception.GetType().Name), line $($_.InvocationInfo.ScriptLineNumber), code $($_.FullyQualifiedErrorId)). Check local administrator access, project/port ownership, realm readiness and seed-account assignments. No reset was attempted."
} finally {
    $headers = $null; $token = $null; $password = $null
}
