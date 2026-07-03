#Requires -Version 7.0

param(
    [ValidateSet('local-http', 'local-https', 'docker-dev-http', 'docker-dev-https', 'docker-stg-http', 'docker-stg-https', 'docker-prod-http', 'docker-prod-https')]
    [string]$Target = 'local-http',

    [switch]$SkipProfileStart
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$logRoot = Join-Path $workspaceRoot ("TestResults\Playwright\{0}" -f ($Target -replace '[^a-z0-9-]+', '-'))
$latestPointerPath = Join-Path $logRoot 'latest-playwright-full-validation.txt'
$rootMarkerPath = Join-Path $workspaceRoot 'TestResults\Playwright\latest-playwright-run.txt'
$statusWriter = Join-Path $PSScriptRoot 'write-playwright-run-status.ps1'
$istZone = [System.TimeZoneInfo]::FindSystemTimeZoneById('India Standard Time')

function Get-IstTimestamp {
    return [System.TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $istZone).ToString('o')
}

function Format-IstStamp {
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$UtcDateTime
    )

    return (Convert-ToIstString -UtcDateTime $UtcDateTime) -replace '[:+,]', '-' -replace '\.', '-'
}

function Convert-ToIstString {
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$UtcDateTime
    )

    return [System.TimeZoneInfo]::ConvertTime(([datetimeoffset]::new($UtcDateTime.ToUniversalTime(), [TimeSpan]::Zero)), $istZone).ToString('o')
}

$runStartedAt = Get-Date
$runStamp = "$(Format-IstStamp -UtcDateTime $runStartedAt)_fullvalidation"
$runDir = Join-Path $logRoot $runStamp
$runPlanPath = Join-Path $runDir 'run-plan.txt'
$startupLogPath = Join-Path $runDir 'startup.log'
$progressLogPath = Join-Path $runDir 'progress.log'
$currentStepPath = Join-Path $runDir 'current-step.txt'

$environmentKey = switch ($Target) {
    'local-http' { 'local-http' }
    'local-https' { 'local-https' }
    'docker-dev-http' { 'docker-http' }
    'docker-dev-https' { 'docker-https' }
    'docker-stg-http' { 'docker-http' }
    'docker-stg-https' { 'docker-https' }
    'docker-prod-http' { 'docker-http' }
    'docker-prod-https' { 'docker-https' }
    default { 'local-http' }
}

New-Item -ItemType Directory -Path $runDir -Force | Out-Null
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $rootMarkerPath) -Force | Out-Null
Set-Content -Path $latestPointerPath -Value "$runDir" -Encoding utf8
Set-Content -Path $rootMarkerPath -Value "$runDir" -Encoding utf8
Set-Content -Path $runPlanPath -Value @(
    "Full validation run",
    "Target: $Target",
    "Goal: run profile, integration, smoke, and the real matrix for the selected environment.",
    "Stages:",
    "1. Execute the profile readiness path for the target environment.",
    "2. Execute the integration suite for the selected environment.",
    "3. Execute the smoke path for the target environment.",
    "4. Execute the full matrix path for all active tenants and providers.",
    "5. Write summary.json and update latest pointers."
) -Encoding utf8
Set-Content -Path $startupLogPath -Value "[$(Get-IstTimestamp)] Full validation startup`n" -Encoding utf8
Set-Content -Path $progressLogPath -Value "[$(Get-IstTimestamp)] Full validation progress log initialized.`n" -Encoding utf8
Set-Content -Path $currentStepPath -Value "initialized" -Encoding utf8
& pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey $environmentKey -TaskName "full-validation" -Status started -Message "runDir=$runDir"

$summaryPath = Join-Path $runDir 'summary.json'
$summary = [ordered]@{
    target = $Target
    environmentKey = $environmentKey
    startedUtc = $runStartedAt.ToUniversalTime().ToString('o')
    startedIst = Convert-ToIstString -UtcDateTime $runStartedAt
    finishedUtc = $null
    finishedIst = $null
    currentStep = 'initialized'
    steps = @()
}
$runFailed = $false
Set-Content -Path $summaryPath -Value ($summary | ConvertTo-Json -Depth 6) -Encoding utf8

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
    [scriptblock]$Command
    )

    $stepLogName = ((($Name -replace '[^a-z0-9-]+', '-').ToLowerInvariant()) + '.log')
    $stepLog = Join-Path $runDir $stepLogName
    Write-Host "Running $Name ..."
    Add-Content -Path $startupLogPath -Value "[$(Get-IstTimestamp)] Running $Name."
    Add-Content -Path $progressLogPath -Value "[$(Get-IstTimestamp)] Running $Name."
    Set-Content -Path $currentStepPath -Value $Name -Encoding utf8
    $summary.currentStep = $Name
    Set-Content -Path $summaryPath -Value ($summary | ConvertTo-Json -Depth 6) -Encoding utf8
    $started = Get-Date
    try {
        & $Command 2>&1 | Tee-Object -FilePath $stepLog
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            throw "$Name failed with exit code $exitCode"
        }

        $summary.steps += [ordered]@{
            name = $Name
            status = 'passed'
            startedUtc = $started.ToUniversalTime().ToString('o')
            finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
            startedIst = Convert-ToIstString -UtcDateTime $started
            finishedIst = Convert-ToIstString -UtcDateTime (Get-Date)
            log = [IO.Path]::GetFileName($stepLog)
        }
        Add-Content -Path $progressLogPath -Value "[$(Get-IstTimestamp)] $Name passed."
    }
    catch {
        $summary.steps += [ordered]@{
            name = $Name
            status = 'failed'
            startedUtc = $started.ToUniversalTime().ToString('o')
            finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
            startedIst = Convert-ToIstString -UtcDateTime $started
            finishedIst = Convert-ToIstString -UtcDateTime (Get-Date)
            log = [IO.Path]::GetFileName($stepLog)
            error = $_.Exception.Message
        }
        Add-Content -Path $progressLogPath -Value "[$(Get-IstTimestamp)] $Name failed: $($_.Exception.Message)"
        throw
    }
}

function Test-UrlReachable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [int]$TimeoutSec = 5
    )

    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec $TimeoutSec
        return $response.StatusCode -ge 200 -and $response.StatusCode -lt 500
    }
    catch {
        return $false
    }
}

try {
    if ($Target -eq 'local-http') {
        Invoke-Step -Name 'local-http-profile' -Command { pwsh -NoProfile -ExecutionPolicy Bypass -File 'scripts/start-local-profile.ps1' -Profile http -ReturnWhenReady }
        Invoke-Step -Name 'local-http-integration' -Command { pwsh -NoProfile -ExecutionPolicy Bypass -File 'scripts/run-integration-tests-local.ps1' }
        Invoke-Step -Name 'local-http-smoke' -Command { pwsh -NoProfile -ExecutionPolicy Bypass -File 'scripts/test-frontend-tenant-bootstrap.ps1' -Target local-http }
        Invoke-Step -Name 'local-http-matrix' -Command { npm --prefix automation run run:local:http:playwright-matrix }
    }
    elseif ($Target -eq 'local-https') {
        Invoke-Step -Name 'local-https-profile' -Command { pwsh -NoProfile -ExecutionPolicy Bypass -File 'scripts/start-local-profile.ps1' -Profile https -ReturnWhenReady }
        Invoke-Step -Name 'local-https-integration' -Command { pwsh -NoProfile -ExecutionPolicy Bypass -File 'scripts/run-integration-tests-local.ps1' }
        Invoke-Step -Name 'local-https-smoke' -Command { pwsh -NoProfile -ExecutionPolicy Bypass -File 'scripts/test-frontend-tenant-bootstrap.ps1' -Target local-https }
        Invoke-Step -Name 'local-https-matrix' -Command { npm --prefix automation run run:local:https:playwright-matrix }
    }
    else {
        $dockerEnvironment = switch ($Target) {
            'docker-dev-http' { 'dev' }
            'docker-dev-https' { 'dev' }
            'docker-stg-http' { 'stg' }
            'docker-stg-https' { 'stg' }
            'docker-prod-http' { 'prod' }
            'docker-prod-https' { 'prod' }
            default { 'dev' }
        }
        $dockerProfile = if ($Target -like '*https') { 'https' } else { 'http' }
        $targetAlive = $false
        if ($Target -eq 'docker-dev-http') {
            $targetAlive = Test-UrlReachable -Url 'http://localhost:5022/'
        }
        elseif ($Target -eq 'docker-dev-https') {
            $targetAlive = Test-UrlReachable -Url 'https://localhost:5023/'
        }
        elseif ($Target -eq 'docker-stg-http') {
            $targetAlive = Test-UrlReachable -Url 'http://localhost:5032/'
        }
        elseif ($Target -eq 'docker-stg-https') {
            $targetAlive = Test-UrlReachable -Url 'https://localhost:5033/'
        }
        elseif ($Target -eq 'docker-prod-http') {
            $targetAlive = Test-UrlReachable -Url 'http://localhost:5042/'
        }
        elseif ($Target -eq 'docker-prod-https') {
            $targetAlive = Test-UrlReachable -Url 'https://localhost:5043/'
        }

        if ($SkipProfileStart -or $targetAlive) {
            $reason = if ($SkipProfileStart) { 'requested by caller' } else { 'target already reachable' }
            Add-Content -Path $progressLogPath -Value "[$(Get-IstTimestamp)] Skipping $Target-profile because $reason."
            $summary.steps += [ordered]@{
                name = "$Target-profile"
                status = 'skipped'
                startedUtc = (Get-Date).ToUniversalTime().ToString('o')
                finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
                log = 'not-applicable'
            }
        }
        else {
            Invoke-Step -Name "$Target-stop-local-sessions" -Command { pwsh -NoProfile -ExecutionPolicy Bypass -File 'scripts/stop-local-dev-sessions.ps1' }
            Invoke-Step -Name "$Target-profile" -Command { pwsh -NoProfile -ExecutionPolicy Bypass -Command "& '.\\Resources\\Docker\\start-docker.ps1' -Environment $dockerEnvironment -Profile $dockerProfile -NoPrePull -LegacyBuild" }
        }
        Invoke-Step -Name "$Target-integration" -Command { pwsh -NoProfile -ExecutionPolicy Bypass -File 'scripts/run-integration-tests-docker.ps1' }
        Invoke-Step -Name "$Target-smoke" -Command { pwsh -NoProfile -ExecutionPolicy Bypass -File 'scripts/test-frontend-tenant-bootstrap.ps1' -Target $Target }
        Invoke-Step -Name "$Target-matrix" -Command { npm --prefix automation run run:docker:matrix -- --target $Target }
    }
}
catch {
    $runFailed = $true
    Add-Content -Path $progressLogPath -Value "[$(Get-IstTimestamp)] Full validation failed: $($_.Exception.Message)"
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey $environmentKey -TaskName "full-validation" -Status failed -Message $_.Exception.Message
    throw
}
finally {
    $summary.finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
    $summary.finishedIst = Get-IstTimestamp
    $summary.status = if ($runFailed) { 'failed' } else { 'passed' }
    $summary.currentStep = 'completed'
    Set-Content -Path $summaryPath -Value ($summary | ConvertTo-Json -Depth 6) -Encoding utf8
    Set-Content -Path $currentStepPath -Value 'completed' -Encoding utf8
    Add-Content -Path $progressLogPath -Value "[$(Get-IstTimestamp)] Full validation completed with status: $($summary.status)."
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey $environmentKey -TaskName "full-validation" -Status $summary.status -Message "summaryPath=$summaryPath"
}

Write-Host "Full validation completed: $Target"
