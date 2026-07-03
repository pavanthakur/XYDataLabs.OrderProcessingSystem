#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('http')]
    [string]$Profile,

    [switch]$ReturnWhenReady
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$apiScriptPath = Join-Path $PSScriptRoot 'start-local-api-profile.ps1'
$frontendScriptPath = Join-Path $PSScriptRoot 'start-local-frontend-profile.ps1'
$keycloakScriptPath = Join-Path $PSScriptRoot 'start-local-keycloak.ps1'
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
        [string]$ProfileName
    )

    Write-Host "Starting $Name for '$ProfileName' profile..."
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $stdoutPath = Join-Path $runDir ("00-start-profile-{0}-stdout.log" -f $Name.ToLowerInvariant())
    $stderrPath = Join-Path $runDir ("00-start-profile-{0}-stderr.log" -f $Name.ToLowerInvariant())

    return Start-Process `
        -FilePath 'pwsh' `
        -ArgumentList @(
            '-NoProfile'
            '-ExecutionPolicy'
            'Bypass'
            '-File'
            $ScriptPath
            "-Profile"
            $ProfileName
        ) `
        -WorkingDirectory $workspaceRoot `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -WindowStyle Hidden `
        -PassThru
}

$profileBecameReady = $false
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
    'Goal: start the Phase 10 local profile with SQL, Redis, and Keycloak.',
        'Stages:',
        '1. Bring up the profile.',
    '2. Wait Ready + Keycloak.',
        '3. Write summary.json and update latest pointers.'
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
    Add-Content -Path $progressLogPath -Value 'Starting Phase 10 local HTTP stack.'
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $keycloakScriptPath
    Start-ChildProfileProcess -Name 'API' -ScriptPath $apiScriptPath -ProfileName $Profile | Out-Null
    Start-ChildProfileProcess -Name 'UI' -ScriptPath $frontendScriptPath -ProfileName $Profile | Out-Null

    Write-Host "Phase 10 local '$Profile' profile bootstrap is running."
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
