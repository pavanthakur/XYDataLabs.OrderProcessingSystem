param(
    [ValidateRange(30, 600)]
    [int]$StartupTimeoutSeconds = 180
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local'
$dockerRoot = Join-Path $workspaceRoot 'Resources\Docker'
$authorityUrl = 'http://localhost:8081/realms/xy-phase9/.well-known/openid-configuration'
$dockerConfigRoot = Join-Path $workspaceRoot '.tmp\docker-config'
$composeArgs = @(
    'compose'
    '--env-file'
    '.env.local'
    '-f'
    'docker-compose.dev.yml'
    '--profile'
    'identity'
    'up'
    '-d'
    'keycloak-local'
)

Write-Host 'Starting local Keycloak container for Phase 9.5...'
New-Item -ItemType Directory -Path $dockerConfigRoot -Force | Out-Null
$previousDockerConfig = $env:DOCKER_CONFIG
$env:DOCKER_CONFIG = $dockerConfigRoot

function Get-EnvLocalValue {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not (Test-Path $envFile)) {
        return $null
    }

    $line = Get-Content -LiteralPath $envFile |
        Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*=" } |
        Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($line)) {
        return $null
    }

    $value = (($line -split '=', 2)[1]).Trim()
    if ($value.StartsWith('"') -and $value.EndsWith('"') -and $value.Length -ge 2) {
        $value = $value.Substring(1, $value.Length - 2)
    }

    return $value
}

function Set-ProcessEnvIfMissing {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $currentValue = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if ([string]::IsNullOrWhiteSpace($currentValue)) {
        [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
    }
}

$keycloakTenantAdminPassword =
    $env:LOCAL_KEYCLOAK_ADMIN_PASSWORD ??
    $env:KEYCLOAK_TENANT_ADMIN_PASSWORD ??
    (Get-EnvLocalValue -Name 'KEYCLOAK_TENANT_ADMIN_PASSWORD') ??
    'Admin100@'

$keycloakAdmin =
    $env:LOCAL_KEYCLOAK_ADMIN ??
    'admin'

$keycloakBackendClientId =
    $env:LOCAL_KEYCLOAK_BACKEND_CLIENT_ID ??
    'xy-order-processing-backend'

$keycloakWebClientId =
    $env:LOCAL_KEYCLOAK_WEB_CLIENT_ID ??
    'xy-order-processing-local-web'

Set-ProcessEnvIfMissing -Name 'LOCAL_KEYCLOAK_ADMIN' -Value $keycloakAdmin
Set-ProcessEnvIfMissing -Name 'LOCAL_KEYCLOAK_ADMIN_PASSWORD' -Value $keycloakTenantAdminPassword
Set-ProcessEnvIfMissing -Name 'KEYCLOAK_TENANT_ADMIN_PASSWORD' -Value $keycloakTenantAdminPassword
Set-ProcessEnvIfMissing -Name 'LOCAL_KEYCLOAK_TEST_PASSWORD' -Value $keycloakTenantAdminPassword
Set-ProcessEnvIfMissing -Name 'LOCAL_KEYCLOAK_BACKEND_CLIENT_ID' -Value $keycloakBackendClientId
Set-ProcessEnvIfMissing -Name 'LOCAL_KEYCLOAK_WEB_CLIENT_ID' -Value $keycloakWebClientId

try
{
    $response = Invoke-WebRequest -UseBasicParsing -Uri $authorityUrl -TimeoutSec 5
    if ($response.StatusCode -eq 200)
    {
        Write-Host 'Local Keycloak is already reachable; reusing the existing instance.'
        return
    }
}
catch
{
}

Push-Location $dockerRoot
try
{
    docker @composeArgs
    if ($LASTEXITCODE -ne 0)
    {
        throw 'docker compose failed while starting keycloak-local.'
    }
}
finally
{
    Pop-Location
    if ($null -ne $previousDockerConfig) {
        $env:DOCKER_CONFIG = $previousDockerConfig
    }
    else {
        Remove-Item Env:DOCKER_CONFIG -ErrorAction SilentlyContinue
    }
}

$deadline = (Get-Date).AddSeconds($StartupTimeoutSeconds)
while ((Get-Date) -lt $deadline)
{
    try
    {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $authorityUrl -TimeoutSec 5
        if ($response.StatusCode -eq 200)
        {
            Write-Host 'Local Keycloak is ready.'
            return
        }
    }
    catch
    {
    }

    Start-Sleep -Seconds 2
}

throw "Timed out waiting for Keycloak readiness at $authorityUrl."
