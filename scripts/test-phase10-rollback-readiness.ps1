#Requires -Version 7.0

param(
    [string]$ArtifactRoot = 'TestResults\Phase10\local-setup',

    [string]$CurrentImageName = 'ghcr.io/pavanthakur/orderprocessing-inventory:dev'
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$dockerEnvExamplePath = Join-Path $workspaceRoot 'Resources\Docker\.env.local.example'
$dockerEnvPath = Join-Path $workspaceRoot 'Resources\Docker\.env.local'
$dockerConfigRoot = Join-Path $workspaceRoot '.tmp\docker-config'
$runStartedAt = Get-Date
$runStamp = $runStartedAt.ToString('yyyyMMdd-HHmmss')
$artifactRootPath = if ([System.IO.Path]::IsPathRooted($ArtifactRoot)) {
    $ArtifactRoot
}
else {
    Join-Path $workspaceRoot $ArtifactRoot
}
$runDir = Join-Path $artifactRootPath "${runStamp}_rollback-readiness"
$progressLogPath = Join-Path $runDir 'progress.log'
$summaryPath = Join-Path $runDir 'summary.json'
$latestPointerPath = Join-Path $artifactRootPath 'latest-rollback-readiness.txt'

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

        [string]$Message = '',
        [string]$PreviousImageName = ''
    )

    [ordered]@{
        status = $Status
        task = 'phase10-rollback-readiness'
        startedAtIst = $runStartedAt.ToString('o')
        completedAtIst = (Get-Date).ToString('o')
        message = $Message
        reportDirectory = $runDir
        currentImageName = $CurrentImageName
        previousImageName = $PreviousImageName
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $summaryPath -Encoding utf8
}

function Get-EnvLocalValue {
    param([Parameter(Mandatory = $true)][string]$Name)

    $environmentValue = [Environment]::GetEnvironmentVariable($Name)
    if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
        return $environmentValue.Trim()
    }

    if (-not (Test-Path -LiteralPath $dockerEnvPath)) {
        return $null
    }

    $line = Get-Content -LiteralPath $dockerEnvPath |
        Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*=" } |
        Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($line)) {
        return $null
    }

    $value = (($line -split '=', 2)[1]).Trim()
    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
        ($value.StartsWith("'") -and $value.EndsWith("'"))) {
        $value = $value.Substring(1, $value.Length - 2)
    }

    return $value.Trim()
}

function Assert-DockerImageExists {
    param([Parameter(Mandatory = $true)][string]$ImageName)

    & docker image inspect $ImageName 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Required Docker image is not available locally: $ImageName"
    }
}

function Assert-DockerAvailable {
    try {
        $output = & docker ps 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw ([string]::Join([Environment]::NewLine, @($output | ForEach-Object { $_.ToString() }))).Trim()
        }
    }
    catch {
        throw "Docker is not reachable from this shell. Start Docker Desktop or rerun from a shell with Docker access. Details: $($_.Exception.Message)"
    }
}

Write-RunLog 'Phase 10 rollback readiness started.'
Write-RunSummary -Status 'running' -Message 'Rollback readiness checks are running.'

New-Item -ItemType Directory -Path $dockerConfigRoot -Force | Out-Null
$previousDockerConfig = $env:DOCKER_CONFIG
$env:DOCKER_CONFIG = $dockerConfigRoot

Push-Location $workspaceRoot
try {
    if (-not (Test-Path -LiteralPath $dockerEnvPath)) {
        throw "Resources/Docker/.env.local is required. Copy Resources/Docker/.env.local.example and set local-only values."
    }

    Assert-DockerAvailable

    $imageOwner = if ([string]::IsNullOrWhiteSpace($env:PHASE10_IMAGE_OWNER)) { 'pavanthakur' } else { $env:PHASE10_IMAGE_OWNER.Trim() }
    $currentImageTag = if ([string]::IsNullOrWhiteSpace($env:PHASE10_IMAGE_TAG)) { 'dev' } else { $env:PHASE10_IMAGE_TAG.Trim() }
    $resolvedCurrentImage = if ($CurrentImageName -eq 'ghcr.io/pavanthakur/orderprocessing-inventory:dev') {
        "ghcr.io/$imageOwner/orderprocessing-inventory:$currentImageTag"
    }
    else {
        $CurrentImageName
    }

    $previousImageTag = Get-EnvLocalValue -Name 'PHASE10_PREVIOUS_IMAGE_TAG'
    if ([string]::IsNullOrWhiteSpace($previousImageTag)) {
        $discoveredPreviousTag = & docker image ls --format '{{.Repository}}:{{.Tag}}' |
            Where-Object { $_ -match "^ghcr\.io/$([regex]::Escape($imageOwner))/orderprocessing-inventory:phase10-prev-" } |
            Select-Object -First 1
        if (-not [string]::IsNullOrWhiteSpace($discoveredPreviousTag)) {
            $previousImageTag = ($discoveredPreviousTag -split ':', 2)[1]
            Write-RunLog "Discovered previous rollback image tag: $previousImageTag"
        }
    }

    if ([string]::IsNullOrWhiteSpace($previousImageTag)) {
        throw 'Rollback prerequisite missing. Set PHASE10_PREVIOUS_IMAGE_TAG in Resources/Docker/.env.local or retain a local inventory image tagged with phase10-prev-*.'
    }

    $resolvedPreviousImage = "ghcr.io/$imageOwner/orderprocessing-inventory:$previousImageTag"
    Write-RunLog "Checking current rollback baseline image: $resolvedCurrentImage"
    Assert-DockerImageExists -ImageName $resolvedCurrentImage
    Write-RunLog "Checking previous rollback baseline image: $resolvedPreviousImage"
    Assert-DockerImageExists -ImageName $resolvedPreviousImage

    Write-RunSummary -Status 'passed' -Message 'Phase 10 rollback readiness passed.' -PreviousImageName $resolvedPreviousImage
    Write-RunLog "Phase 10 rollback readiness passed. previousImage=$resolvedPreviousImage reportDirectory=$runDir"
}
catch {
    Write-RunSummary -Status 'failed' -Message $_.Exception.Message
    Write-RunLog "Phase 10 rollback readiness failed: $($_.Exception.Message)"
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
