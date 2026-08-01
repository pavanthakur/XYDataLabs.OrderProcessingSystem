#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('http')]
    [string]$Profile,

    [switch]$ReturnWhenReady,

    [switch]$ReuseExistingStack,

    [switch]$SkipStartIfNeeded
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$apiScriptPath = Join-Path $PSScriptRoot 'start-local-api-profile.ps1'
$frontendScriptPath = Join-Path $PSScriptRoot 'start-local-frontend-profile.ps1'
$dockerInfraScriptPath = Join-Path $PSScriptRoot 'start-phase10-docker-dev.ps1'
$statusWriter = Join-Path $PSScriptRoot 'write-playwright-run-status.ps1'
$logRoot = Join-Path $workspaceRoot 'TestResults\Playwright\phase10-local-http'
$latestPointerPath = Join-Path $logRoot 'latest-playwright-profile.txt'
$rootMarkerPath = Join-Path $workspaceRoot 'TestResults\Playwright\latest-playwright-run.txt'
$runStamp = "$(Get-Date -Format 'yyyyMMdd-HHmmss')_profile"
$runDir = Join-Path $logRoot $runStamp
$startupLogPath = Join-Path $runDir '00-start-profile.log'
$progressLogPath = Join-Path $runDir '01-env-ready.log'
$summaryPath = Join-Path $runDir 'summary.json'
$sequenceEnvironmentKey = 'phase10-local-http'
$apiReadyUrl = 'http://localhost:5010/health/ready'
$uiReadyUrl = 'http://localhost:5173/'

function Get-EnvLocalValue {
    param([Parameter(Mandatory = $true)][string]$Name)

    $environmentValue = [Environment]::GetEnvironmentVariable($Name)
    if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
        return $environmentValue.Trim()
    }

    $envFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local'
    if (-not (Test-Path -LiteralPath $envFile)) {
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

    if ($value.StartsWith("'") -and $value.EndsWith("'") -and $value.Length -ge 2) {
        $value = $value.Substring(1, $value.Length - 2)
    }

    return $value.Trim()
}

function Resolve-Phase10InfrastructureProfile {
    $serviceBusEnabled = Get-EnvLocalValue -Name 'LOCAL_SERVICEBUS_ENABLED'
    if ($serviceBusEnabled -eq 'true') {
        return 'messaging'
    }

    return 'infrastructure'
}

function Test-HttpReady {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    try {
        $invokeParams = @{
            Uri = $Url
            TimeoutSec = 5
            Method = 'Get'
            ErrorAction = 'Stop'
        }

        $response = Invoke-WebRequest @invokeParams
        return $response.StatusCode -ge 200 -and $response.StatusCode -lt 400
    }
    catch {
        return $false
    }
}

function Start-ChildProfileProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $true)]
        [string]$ProfileName,

        [switch]$DisableStartupDdl,

        [switch]$Phase10DockerBacking
    )

    Write-Host "Starting $Name for '$ProfileName' profile..."
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $stdoutPath = Join-Path $runDir ("00-start-profile-{0}-stdout.log" -f $Name.ToLowerInvariant())
    $stderrPath = Join-Path $runDir ("00-start-profile-{0}-stderr.log" -f $Name.ToLowerInvariant())

    $argumentList = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        $ScriptPath
        '-Profile'
        $ProfileName
    )

    if ($DisableStartupDdl)
    {
        $argumentList += '-DisableStartupDdl'
    }

    if ($Phase10DockerBacking)
    {
        $argumentList += '-Phase10DockerBacking'
    }

    return Start-Process `
        -FilePath 'pwsh' `
        -ArgumentList $argumentList `
        -WorkingDirectory $workspaceRoot `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -WindowStyle Hidden `
        -PassThru
}

$profileBecameReady = $false
$reusedExistingStack = $false
$startupDeadline = (Get-Date).AddSeconds(120)

try
{
    New-Item -ItemType Directory -Path $runDir -Force | Out-Null
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Split-Path -Parent $rootMarkerPath) -Force | Out-Null
    Set-Content -Path $latestPointerPath -Value $runDir -Encoding utf8
    Set-Content -Path $rootMarkerPath -Value $runDir -Encoding utf8
    Set-Content -Path (Join-Path $runDir 'run-plan.txt') -Value @(
        'Phase 10 Local HTTP profile run',
        'Goal: start the Phase 10 local profile against the Phase 10 Docker backing stack.',
        'Stages:',
        '1. Bring up the Phase 10 Docker backing services and database bootstrap.',
        '2. Start the local API and UI against the Docker-backed Phase 10 dev databases.',
        '3. Wait for ready endpoints.',
        '4. Write summary.json and update latest pointers.'
    ) -Encoding utf8
    Set-Content -Path $startupLogPath -Value "[$(Get-Date -Format o)] Phase 10 local profile startup`n" -Encoding utf8
    Set-Content -Path $progressLogPath -Value "Phase 10 local profile readiness log initialized.`n" -Encoding utf8

    $summary = [ordered]@{
        target = 'phase10-local-http'
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
        finishedUtc = $null
        status = 'running'
        runDir = $runDir
        latestPointerPath = $latestPointerPath
    }

    & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey $sequenceEnvironmentKey -TaskName 'phase10-local-http-env-ready' -Status started -Message $Profile

    $apiReady = Test-HttpReady -Url $apiReadyUrl
    $uiReady = Test-HttpReady -Url $uiReadyUrl

    if (-not $ReuseExistingStack)
    {
        Add-Content -Path $progressLogPath -Value 'Starting Phase 10 local HTTP stack in clean mode.'
        & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'stop-local-dev-sessions.ps1') -Profile $Profile | Out-Null
        $infrastructureProfile = Resolve-Phase10InfrastructureProfile
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $dockerInfraScriptPath -Action up -Profile $infrastructureProfile -HealthTimeoutSec 300
        if ($LASTEXITCODE -ne 0)
        {
            throw "Failed to start the Phase 10 Docker backing stack for profile '$infrastructureProfile'."
        }
        Start-ChildProfileProcess -Name 'API' -ScriptPath $apiScriptPath -ProfileName $Profile -DisableStartupDdl -Phase10DockerBacking | Out-Null
        Start-ChildProfileProcess -Name 'UI' -ScriptPath $frontendScriptPath -ProfileName $Profile | Out-Null
        Write-Host "Phase 10 local '$Profile' profile bootstrap is running in clean mode."
    }
    elseif (-not ($apiReady -and $uiReady))
    {
        if ($SkipStartIfNeeded)
        {
            throw 'Phase 10 local HTTP stack is not reachable. Start the local profile or omit -SkipStartIfNeeded to let the launcher bring the stack up.'
        }

        Add-Content -Path $progressLogPath -Value 'Phase 10 local HTTP stack was not reachable; starting it now in reuse mode.'
        $infrastructureProfile = Resolve-Phase10InfrastructureProfile
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $dockerInfraScriptPath -Action up -Profile $infrastructureProfile -HealthTimeoutSec 300
        if ($LASTEXITCODE -ne 0)
        {
            throw "Failed to start the Phase 10 Docker backing stack for profile '$infrastructureProfile'."
        }
        Start-ChildProfileProcess -Name 'API' -ScriptPath $apiScriptPath -ProfileName $Profile -DisableStartupDdl -Phase10DockerBacking | Out-Null
        Start-ChildProfileProcess -Name 'UI' -ScriptPath $frontendScriptPath -ProfileName $Profile | Out-Null
        Write-Host "Phase 10 local '$Profile' profile bootstrap is running in reuse mode."
    }
    else
    {
        $reusedExistingStack = $true
        Add-Content -Path $progressLogPath -Value 'Phase 10 local HTTP stack is already reachable. Reusing the live stack.'
        Write-Host "Phase 10 local '$Profile' profile is already reachable. Reusing the live stack."
    }

    Write-Host "Waiting for API readiness at $apiReadyUrl and UI readiness at $uiReadyUrl."

    while ($true)
    {
        if (-not $profileBecameReady)
        {
            if ((Test-HttpReady -Url $apiReadyUrl) -and (Test-HttpReady -Url $uiReadyUrl))
            {
                $profileBecameReady = $true
                Add-Content -Path $progressLogPath -Value 'Phase 10 local HTTP stack is ready.'
                Write-Host "Phase 10 local '$Profile' profile is ready at $apiReadyUrl and $uiReadyUrl."
                & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey $sequenceEnvironmentKey -TaskName 'phase10-local-http-env-ready' -Status passed -Message $Profile
                $summary.status = 'passed'
                $summary.reusedExistingStack = $reusedExistingStack
                if ($ReturnWhenReady) {
                    return
                }
                break
            }
            elseif ((Get-Date) -ge $startupDeadline)
            {
                & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey $sequenceEnvironmentKey -TaskName 'phase10-local-http-env-ready' -Status failed -Message $Profile
                throw "Timed out waiting for Phase 10 local '$Profile' profile readiness at $apiReadyUrl and $uiReadyUrl."
            }
        }
        elseif (-not ((Test-HttpReady -Url $apiReadyUrl) -and (Test-HttpReady -Url $uiReadyUrl)))
        {
            & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey $sequenceEnvironmentKey -TaskName 'phase10-local-http-env-ready' -Status failed -Message $Profile
            throw "Phase 10 local '$Profile' profile stopped responding at $apiReadyUrl or $uiReadyUrl."
        }

        Start-Sleep -Seconds 1
    }
}
finally
{
    if (-not $profileBecameReady) {
        $summary.status = 'failed'
    }

    if ($null -ne $summary) {
        $summary.finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
        Set-Content -Path $summaryPath -Value ($summary | ConvertTo-Json -Depth 5) -Encoding utf8
        Set-Content -Path $latestPointerPath -Value $runDir -Encoding utf8
        Set-Content -Path $rootMarkerPath -Value $runDir -Encoding utf8
    }

    if (-not $profileBecameReady)
    {
        try
        {
            & (Join-Path $PSScriptRoot 'stop-local-dev-sessions.ps1') -Profile $Profile | Out-Null
        }
        catch
        {
        }
    }
}
