param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('dev', 'stg', 'prod')]
    [string]$Environment,

    [Parameter(Mandatory = $true)]
    [ValidateSet('http', 'https')]
    [string]$Profile,

    [switch]$NoPrePull,

    [switch]$Reset,

    [switch]$Strict,

    [switch]$BootstrapDatabases
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$dockerScript = Join-Path $repoRoot 'Resources\Docker\start-docker.ps1'
$bootstrapScript = Join-Path $repoRoot 'scripts\ensure-phase9-docker-databases.ps1'

if (-not (Test-Path $dockerScript)) {
    throw "Docker startup script not found: $dockerScript"
}

if ($BootstrapDatabases -and -not (Test-Path $bootstrapScript)) {
    throw "Docker database bootstrap script not found: $bootstrapScript"
}

Write-Host "Starting Docker profile: $Environment/$Profile" -ForegroundColor Cyan

if ($BootstrapDatabases) {
    Write-Host "Bootstrapping Docker databases for $Environment before app startup..." -ForegroundColor Cyan
    $bootstrapArgs = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        $bootstrapScript
        '-Environment'
        $Environment
    )

    & pwsh @bootstrapArgs

    if ($LASTEXITCODE -ne 0) {
        throw "Docker database bootstrap failed for $Environment with exit code $LASTEXITCODE"
    }
}

$arguments = @(
    '-NoProfile'
    '-ExecutionPolicy'
    'Bypass'
    '-File'
    $dockerScript
    '-Environment'
    $Environment
    '-Profile'
    $Profile
)

if ($NoPrePull) {
    $arguments += '-NoPrePull'
}

if ($Reset) {
    $arguments += '-Reset'
}

if ($Strict) {
    $arguments += '-Strict'
}

& pwsh @arguments

if ($LASTEXITCODE -ne 0) {
    throw "Docker profile startup failed for $Environment/$Profile with exit code $LASTEXITCODE"
}

Write-Host "Docker profile startup completed: $Environment/$Profile" -ForegroundColor Green
