param(
    [ValidateRange(30, 600)]
    [int]$StartupTimeoutSeconds = 180
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
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
