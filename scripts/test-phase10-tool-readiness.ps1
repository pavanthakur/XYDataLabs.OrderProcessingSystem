#Requires -Version 7.0

param(
    [string]$ArtifactRoot = 'TestResults\Phase10\local-setup'
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$globalJsonPath = Join-Path $workspaceRoot 'global.json'
$dockerEnvExamplePath = Join-Path $workspaceRoot 'Resources\Docker\.env.local.example'
$dockerEnvPath = Join-Path $workspaceRoot 'Resources\Docker\.env.local'
$dockerConfigRoot = Join-Path $workspaceRoot '.tmp\docker-config'
$runStartedAt = Get-Date
$runStamp = $runStartedAt.ToString('yyyyMMdd-HHmmss')
$runDir = Join-Path $workspaceRoot (Join-Path $ArtifactRoot "${runStamp}_environment-readiness")
$progressLogPath = Join-Path $runDir 'progress.log'
$summaryPath = Join-Path $runDir 'summary.json'
$latestPointerPath = Join-Path $workspaceRoot (Join-Path $ArtifactRoot 'latest-environment-readiness.txt')

New-Item -ItemType Directory -Path $runDir -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $latestPointerPath) -Force | Out-Null
Set-Content -LiteralPath $latestPointerPath -Value $runDir -Encoding utf8

function Write-RunLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $line = "[{0}] {1}" -f (Get-Date).ToString('o'), $Message
    Write-Host $line
    Add-Content -LiteralPath $progressLogPath -Value $line -Encoding utf8
}

function Write-RunSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Status,

        [string]$Message = ''
    )

    [ordered]@{
        status = $Status
        task = 'phase10-local-setup-environment-readiness'
        startedAtIst = $runStartedAt.ToString('o')
        completedAtIst = (Get-Date).ToString('o')
        message = $Message
        reportDirectory = $runDir
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $summaryPath -Encoding utf8
}

Write-RunLog 'Phase 10 environment readiness started.'
Write-RunSummary -Status 'running' -Message 'Environment readiness checks are running.'

New-Item -ItemType Directory -Path $dockerConfigRoot -Force | Out-Null
$previousDockerConfig = $env:DOCKER_CONFIG
$env:DOCKER_CONFIG = $dockerConfigRoot

function Resolve-ToolPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string[]]$FallbackPaths = @()
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    foreach ($fallbackPath in $FallbackPaths) {
        if (Test-Path -LiteralPath $fallbackPath) {
            return $fallbackPath
        }
    }

    return $Name
}

function Invoke-ToolCheck {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Command
    )

    Write-RunLog "Checking $Name..."
    & $Command | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "$Name check failed."
    }

    Write-RunLog "$Name check passed."
}

Push-Location $workspaceRoot
try {
    Invoke-ToolCheck -Name '.NET SDK' -Command { dotnet --info }
    Invoke-ToolCheck -Name 'PowerShell' -Command { pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' }
    Invoke-ToolCheck -Name 'Node.js' -Command { node --version }
    Invoke-ToolCheck -Name 'npm' -Command { npm --version }
    Invoke-ToolCheck -Name 'Docker Compose' -Command { docker compose version }
    Invoke-ToolCheck -Name 'Azure CLI' -Command { az account show }
    Invoke-ToolCheck -Name 'Bicep CLI' -Command { az bicep version }
    $funcPath = Resolve-ToolPath -Name 'func' -FallbackPaths @(
        'C:\Program Files\Microsoft\Azure Functions Core Tools\func.exe',
        'C:\Program Files\Microsoft\Azure Functions Core Tools\in-proc8\func.exe'
    )
    Invoke-ToolCheck -Name 'Azure Functions Core Tools' -Command { & $funcPath --version }
    Invoke-ToolCheck -Name 'GitHub CLI' -Command { gh auth status }

    if (-not (Test-Path -LiteralPath $globalJsonPath)) {
        throw "global.json is required before Phase 10 implementation starts."
    }
    Write-RunLog 'global.json exists.'

    if (-not (Test-Path -LiteralPath $dockerEnvPath)) {
        throw "Resources/Docker/.env.local is required for Docker-backed Phase 10 profiles. Copy Resources/Docker/.env.local.example and set local-only values."
    }
    Write-RunLog 'Resources/Docker/.env.local exists.'

    Write-RunLog 'Validating Phase 10 Docker Compose app profile set.'
    & docker compose --env-file $dockerEnvExamplePath --env-file $dockerEnvPath -f (Join-Path $workspaceRoot 'compose\docker-compose.phase10.yml') --profile data --profile identity --profile storage --profile apps config --quiet
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker Compose config validation failed for the Phase 10 local app profile set.'
    }
    Write-RunLog 'Docker Compose app profile config validation passed.'

    Write-RunSummary -Status 'passed' -Message 'Phase 10 environment readiness passed.'
    Write-RunLog "Phase 10 environment readiness passed. reportDirectory=$runDir"
}
catch {
    Write-RunSummary -Status 'failed' -Message $_.Exception.Message
    Write-RunLog "Phase 10 environment readiness failed: $($_.Exception.Message)"
    throw
}
finally {
    if ([string]::IsNullOrWhiteSpace($previousDockerConfig)) {
        Remove-Item Env:DOCKER_CONFIG -ErrorAction SilentlyContinue
    }
    else {
        $env:DOCKER_CONFIG = $previousDockerConfig
    }

    Pop-Location
}
