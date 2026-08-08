#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [ValidateRange(30, 900)]
    [int]$TimeoutSeconds = 300,

    [ValidateRange(1, 60)]
    [int]$PollIntervalSeconds = 10
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $workspaceRoot 'compose\docker-compose.phase10.yml'
$envExampleFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local.example'
$envFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local'
$composeArguments = @(
    'compose',
    '--env-file', $envExampleFile,
    '--env-file', $envFile,
    '-f', $composeFile,
    '--profile', 'data',
    '--profile', 'storage',
    '--profile', 'messaging',
    '--profile', 'functions'
)

$containerIdOutput = & docker @composeArguments ps -q functions 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Unable to query the Phase 10 Functions container state. Docker output: $([string]::Join([Environment]::NewLine, @($containerIdOutput)))"
}

$containerId = ([string]::Join('', @($containerIdOutput))).Trim()
if ([string]::IsNullOrWhiteSpace($containerId)) {
    throw 'The Phase 10 Functions container is not running.'
}

function Get-FunctionsDiscoveryProofText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerId
    )

    $metadata = & docker exec $ContainerId sh -lc 'if [ -f /home/site/wwwroot/functions.metadata ]; then cat /home/site/wwwroot/functions.metadata; fi' 2>&1
    if ($LASTEXITCODE -eq 0) {
        $metadataText = [string]::Join([Environment]::NewLine, @($metadata))
        if (-not [string]::IsNullOrWhiteSpace($metadataText)) {
            return $metadataText
        }
    }

    $logs = & docker @composeArguments logs --no-color functions 2>&1
    return [string]::Join([Environment]::NewLine, @($logs))
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$logText = ''
while ((Get-Date) -lt $deadline) {
    $logText = Get-FunctionsDiscoveryProofText -ContainerId $containerId
    Set-Content -LiteralPath $OutputPath -Value $logText -Encoding utf8

    $discoveredAll = $true
    foreach ($functionName in @('DlqIntakeFunction', 'DlqReplayFunction')) {
        if ($logText -notmatch [regex]::Escape($functionName)) {
            $discoveredAll = $false
            break
        }
    }

    if ($discoveredAll) {
        break
    }

    Start-Sleep -Seconds $PollIntervalSeconds
}

foreach ($functionName in @('DlqIntakeFunction', 'DlqReplayFunction')) {
    if ($logText -notmatch [regex]::Escape($functionName)) {
        throw "Function '$functionName' was not discovered. See $OutputPath."
    }
}

Write-Host "Discovered DlqIntakeFunction and DlqReplayFunction in container $containerId."
