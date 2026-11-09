#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [ValidateRange(60, 900)]
    [int]$StabilizationDelaySeconds = 120,

    [ValidateSet('minimal', 'normal', 'detailed', 'quiet')]
    [string]$IntegrationConsoleVerbosity = 'minimal',

    [ValidateSet('sandbox', 'deterministic', 'both')]
    [string]$PaymentSuite = 'sandbox',

    [ValidateSet('baseline','extended')]
    [string]$AcceptanceProfile = 'baseline',

    [switch]$VerifyPersistence,

    [switch]$CleanupOnExit,

    [switch]$RemoveVolumes,

    [switch]$RemoveImages
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'phase10-docker-safety.ps1')
. (Join-Path $PSScriptRoot 'phase10-acceptance-report.ps1')
Assert-Phase10ComposeProject
if ($RemoveImages) { throw '-RemoveImages is retired. Review image cleanup separately; shared tags must not be force-deleted.' }
if ($RemoveVolumes -and -not $CleanupOnExit) { throw '-RemoveVolumes requires -CleanupOnExit.' }
if ($WhatIfPreference) { Write-Host 'Would validate xy-phase10. No changes made.'; return }
if ($RemoveVolumes) { Confirm-Phase10Reset -Approve { $PSCmdlet.ShouldProcess('xy-phase10 SQL/Azurite volumes', 'Delete trial data after E2E validation') } }
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $workspaceRoot 'compose\docker-compose.phase10.yml'
$envExampleFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local.example'
$envFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local'
Initialize-Phase10LogRedaction -Settings (Get-Phase10LocalSettings -Path $envFile)
$databaseBootstrapScript = Join-Path $workspaceRoot 'scripts\invoke-phase10-database-bootstrap.ps1'
$logRoot = Join-Path $workspaceRoot 'TestResults\Playwright\phase10-docker-http'
$dockerConfigRoot = Join-Path $workspaceRoot '.tmp\docker-config'
$runDir = if ([string]::IsNullOrWhiteSpace($env:PHASE10_RUN_ROOT)) {
    Join-Path $logRoot "$(Get-Date -Format 'yyyyMMdd-HHmmssfff')_endtoend"
}
else {
    $env:PHASE10_RUN_ROOT
}
$summaryPath = Join-Path $runDir 'e2e-summary.json'
$diagnosticsPath = Join-Path $runDir 'diagnostics.json'
$startupLogPath = Join-Path $runDir '00-end-to-end.log'
$progressLogPath = Join-Path $runDir 'progress.log'
$latestPointerPath = Join-Path $logRoot 'latest-playwright-full-validation.txt'
$latestFailurePointerPath = Join-Path $logRoot 'latest-playwright-failure.txt'
$rootMarkerPath = Join-Path $workspaceRoot 'TestResults\Playwright\latest-playwright-run.txt'

New-Item -ItemType Directory -Path $runDir -Force | Out-Null
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $rootMarkerPath) -Force | Out-Null
New-Item -ItemType Directory -Path $dockerConfigRoot -Force | Out-Null

$previousDockerConfig = $env:DOCKER_CONFIG
$env:DOCKER_CONFIG = $dockerConfigRoot

Set-Content -Path $latestPointerPath -Value $runDir -Encoding utf8
Set-Content -Path $rootMarkerPath -Value $runDir -Encoding utf8
Set-Content -Path (Join-Path $runDir 'end-to-end-run-plan.txt') -Value @(
    'Phase 10 local container stack end-to-end run',
    'Goal: validate the already-started Phase 10 local container stack and clean it up afterwards.',
    'Stages:',
    '1. Confirm gateway and UI readiness.',
    '2. Run smoke validation.',
    '3. Run integration suite.',
    '4. Verify integration left application metadata unchanged; apply only the approved OpenPay 3DS-off baseline.',
    '5. Discover active tenant topology from runtime/registry data and run the provider matrix across the resolved tenants.',
    '6. Preserve the stack by default so NFR and rollback proof can run.',
    '7. Tear down only when CleanupOnExit is explicitly selected.',
    '8. Write summary.json and update latest pointers.'
) -Encoding utf8
Set-Content -Path $startupLogPath -Value "[$(Get-Date -Format o)] Phase 10 end-to-end wrapper started`n" -Encoding utf8
Set-Content -Path $progressLogPath -Value "Phase 10 end-to-end progress log initialized.`n" -Encoding utf8

function Write-ProgressLine {
    param([Parameter(Mandatory = $true)][string]$Message)

    Add-Content -Path $progressLogPath -Value "[$(Get-Date -Format o)] $Message"
    Write-Host $Message
}

function Assert-DockerAvailable {
    Assert-Phase10PortOwnership -Ports @(5080, 5022, (Get-Phase10SqlHostPort))
    try {
        $output = & docker ps 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw ([string]::Join([Environment]::NewLine, @($output | ForEach-Object { $_.ToString() }))).Trim()
        }
    }
    catch {
        throw "Docker Desktop is not running or the Docker engine is unavailable. Start Docker Desktop and retry the Phase 10 local container stack task. Details: $($_.Exception.Message)"
    }
}

function Wait-ForUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [int]$TimeoutSec = 300
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 5
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
                return
            }
        }
        catch {
        }

        Start-Sleep -Seconds 2
    }

    throw "Timed out waiting for $Url after $TimeoutSec seconds."
}

function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Script
    )

    $logPath = Join-Path $runDir (($Name -replace '[^a-z0-9-]+', '-').ToLowerInvariant() + '.log')
    Write-ProgressLine "Running $Name..."
    try {
        & $Script 2>&1 | Protect-Phase10Log | Tee-Object -FilePath $logPath
        if ($LASTEXITCODE -ne 0) {
            throw "$Name failed with exit code $LASTEXITCODE"
        }
        Write-ProgressLine "$Name passed."
        return $true
    }
    catch {
        Write-ProgressLine "$Name failed: $($_.Exception.Message)"
        if (-not @($summary.steps | Where-Object name -eq $Name).Count) {
            $summary.steps += @{name=$Name;status='failed';log=[IO.Path]::GetFileName($logPath);error=$_.Exception.Message}
        }
        throw
    }
}

$summary = [ordered]@{
    target = 'phase10-docker-http'
    startedUtc = (Get-Date).ToUniversalTime().ToString('o')
    finishedUtc = $null
    status = 'running'
    runDir = $runDir
    latestPointerPath = $latestPointerPath
    steps = @()
}
$runFailed = $false
$runPartial = $false
$previousPaymentReportRoot = $env:PHASE10_PAYMENT_REPORT_ROOT
$paymentReportRoot = Join-Path $runDir 'payments'
$env:PHASE10_PAYMENT_REPORT_ROOT = $paymentReportRoot
$dockerAvailable = $false

try {
    Assert-DockerAvailable
    $dockerAvailable = $true
    Wait-ForUrl -Url 'http://localhost:5080/health/alive' -TimeoutSec 300
    Wait-ForUrl -Url 'http://localhost:5022/' -TimeoutSec 300
    $summary.steps += [ordered]@{
        name = 'readiness'
        status = 'passed'
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
        finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
        log = [IO.Path]::GetFileName($startupLogPath)
    }

    Invoke-LoggedCommand -Name 'foundations' -Script {
        & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'run-phase10-foundation-tests.ps1') -ArtifactDirectory (Join-Path $runDir 'foundations')
    } | Out-Null
    $summary.steps += @{name='foundations';status='passed'}
    Start-Sleep -Seconds $StabilizationDelaySeconds

    Invoke-LoggedCommand -Name 'smoke' -Script {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $workspaceRoot 'scripts\run-phase10-docker-dev-smoke.ps1') -StabilizationDelaySeconds $StabilizationDelaySeconds
    } | Out-Null
    $summary.steps += [ordered]@{
        name = 'smoke'
        status = 'passed'
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
        finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
        log = 'smoke.log'
    }

    Invoke-LoggedCommand -Name 'integration-prep' -Script {
        dotnet build-server shutdown
    } | Out-Null
    $summary.steps += [ordered]@{
        name = 'integration-prep'
        status = 'passed'
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
        finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
        log = 'integration-prep.log'
    }

    Invoke-LoggedCommand -Name 'integration' -Script {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $workspaceRoot 'scripts\run-integration-tests-docker.ps1') -ConsoleVerbosity $IntegrationConsoleVerbosity
    } | Out-Null
    $summary.steps += [ordered]@{
        name = 'integration'
        status = 'passed'
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
        finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
        log = 'integration.log'
    }

    Invoke-LoggedCommand -Name 'openpay-local-baseline' -Script {
        & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'set-local-openpay-3ds-baseline.ps1') -ArtifactPath (Join-Path $runDir 'openpay-3ds-baseline.json')
        if ($LASTEXITCODE -ne 0) { throw 'OpenPay 3DS-off baseline could not be applied and verified.' }
    } | Out-Null
    $summary.steps += @{name='openpay-local-baseline';status='passed';report='openpay-3ds-baseline.json'}

    Invoke-LoggedCommand -Name 'baseline-validation' -Script {
        & pwsh -NoProfile -File $databaseBootstrapScript -Profile apps -ValidateOnly -RunDir $runDir -ProgressLogPath $progressLogPath
        if ($LASTEXITCODE -ne 0) { throw 'Read-only database validation failed; no reseeding is permitted.' }
        & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'test-phase10-local-seed-contract.ps1') -OutputPath (Join-Path $runDir 'seed-contract.json')
    } | Out-Null
    $summary.steps += @{name='baseline-validation';status='passed'}

    Invoke-LoggedCommand -Name 'customer-directory' -Script {
        npm --prefix (Join-Path $workspaceRoot 'automation') run test:customer-directory:browser
    } | Out-Null
    $summary.steps += [ordered]@{
        name = 'customer-directory'
        status = 'passed'
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
        finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
        log = 'customer-directory.log'
    }

    if ($PaymentSuite -in @('deterministic', 'both')) {
        Invoke-LoggedCommand -Name 'tenantc-routing-regression' -Script {
            & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'run-local-payment-tests.ps1') -Mode deterministic -TenantCode TenantC -ProviderType Razorpay
        } | Out-Null
        $summary.steps += @{name='tenantc-routing-regression';status='passed'}
        Invoke-LoggedCommand -Name 'payments-deterministic' -Script {
            & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $workspaceRoot 'scripts/run-local-payment-tests.ps1') -Mode deterministic -AcceptanceProfile $AcceptanceProfile
        } | Out-Null
        $summary.steps += [ordered]@{ name = 'payments-deterministic'; status = 'passed'; startedUtc = [DateTime]::UtcNow.ToString('o'); finishedUtc = [DateTime]::UtcNow.ToString('o'); log = 'payments-deterministic.log' }
    }
    if ($PaymentSuite -in @('sandbox', 'both')) {
        & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'run-phase10-sandbox-gates.ps1') -ArtifactDirectory $paymentReportRoot -AcceptanceProfile $AcceptanceProfile 2>&1 |
            Protect-Phase10Log | Tee-Object -FilePath (Join-Path $runDir 'payments-sandbox.log')
        $sandboxCode=$LASTEXITCODE
        if (Test-Path (Join-Path $workspaceRoot 'TestResults/local-payment-test-state.lock')) { throw 'A provider fixture needs recovery. Stop all further mutations.' }
        $sandbox=Get-Content (Join-Path $paymentReportRoot 'sandbox-gates.json') -Raw | ConvertFrom-Json
        $summary.steps += @{name='sandbox-payments';status=$sandbox.status;rawExitCode=$sandboxCode;primaryPassed=$sandbox.primaryPassed;report='payments/sandbox-gates.json'}
        if ($sandbox.status -eq 'failed') { $runFailed=$true } elseif ($sandbox.status -ne 'passed') { $runPartial=$true }
    }
    if (Test-Path (Join-Path $workspaceRoot 'TestResults/local-payment-test-state.lock')) { throw 'Fixture lock remains; refuse messaging/restart.' }
    try {
        Invoke-LoggedCommand -Name 'currency-order-entry' -Script { npm --prefix (Join-Path $workspaceRoot 'automation') run test:payment-currency:browser } | Out-Null
        $summary.steps += @{name='currency-order-entry';status='passed'}
    } catch { $runFailed=$true }
    if (Test-Path (Join-Path $workspaceRoot 'TestResults/local-payment-test-state.lock')) { throw 'Currency fixture needs recovery; stop further mutations.' }
    if ($PaymentSuite -in @('sandbox','both')) {
        $sources=@(Get-ChildItem $paymentReportRoot -Directory -Filter 'payment-acceptance-sandbox-*' | ForEach-Object {Join-Path $_.FullName 'summary.json'} | Where-Object {Test-Path $_})
        $hasCases=@($sources | Where-Object { $j=Get-Content $_ -Raw|ConvertFrom-Json; @($j.results.rows|Where-Object journeyOutcome -eq 'completed').Count -gt 0 }).Count -gt 0
        if ($hasCases) {
            $previousContinuation=$env:PHASE10_CONTINUATION_SOURCES
            $previousContinuationArtifact=$env:PHASE10_CONTINUATION_ARTIFACT
            try {
                $env:PHASE10_CONTINUATION_SOURCES=$sources-join';'
                $env:PHASE10_CONTINUATION_ARTIFACT=Join-Path $runDir 'continuation'
                Invoke-LoggedCommand -Name 'order-continuation' -Script { npm --prefix (Join-Path $workspaceRoot 'automation') run test:order-continuation:browser } | Out-Null
                $continuationPath=Join-Path $env:PHASE10_CONTINUATION_ARTIFACT 'summary.json'
                if(-not(Test-Path $continuationPath)){throw 'Order continuation runner exited successfully without a structured summary.'}
                $continuation=Get-Content $continuationPath -Raw|ConvertFrom-Json
                $continuationDecision=Resolve-Phase10ContinuationDecision -Summary $continuation
                $summary.steps += @{name='order-continuation';status=$continuationDecision.Status;structuredStatus=$continuationDecision.StructuredStatus;deferredCount=$continuationDecision.DeferredCount;deferrals=$continuationDecision.Deferrals;report='continuation/summary.json'}
            } catch { $runFailed=$true }
            finally { $env:PHASE10_CONTINUATION_SOURCES=$previousContinuation; $env:PHASE10_CONTINUATION_ARTIFACT=$previousContinuationArtifact }
        } else { $runPartial=$true; $summary.steps += @{name='order-continuation';status='blocked';reason='No completed real-sandbox case exists for order-state evidence.'} }
    }
    try {
        Invoke-LoggedCommand -Name 'messaging-functions' -Script {
            & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'test-local-messaging.ps1') -ArtifactDirectory (Join-Path $runDir 'messaging')
        } | Out-Null
        $summary.steps += @{name='messaging-functions';status='passed'}
    } catch { $runFailed=$true }
    $replayProof=Join-Path $runDir 'messaging/replay-restoration.json'
    if (-not (Test-Path $replayProof) -or (Get-Content $replayProof -Raw | ConvertFrom-Json).status -ne 'passed') { throw 'Replay restoration is not proven; refuse further mutations.' }
    if ($VerifyPersistence) {
        try {
            Invoke-LoggedCommand -Name 'persistence' -Script {
                & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'test-phase10-docker-persistence.ps1') -RestartDesktop -ArtifactDirectory (Join-Path $runDir 'persistence')
            } | Out-Null
            $summary.steps += @{name='persistence';status='passed'}
        } catch { $runFailed=$true }
    } else { $summary.steps += @{name='persistence';status='not-run';reason='Select -VerifyPersistence for the explicit Desktop restart gate.'} }
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'test-phase10-local-seed-contract.ps1') -OutputPath (Join-Path $runDir 'restoration-contract.json')
    if ($LASTEXITCODE -ne 0) { throw 'Final provider restoration contract failed.' }
    $summary.steps += @{name='provider-restoration';status='passed'}

}
catch {
    $runFailed = $true
    $summary.steps += [ordered]@{
        name = 'failure'
        status = 'failed'
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
        finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
        log = 'progress.log'
        error = $_.Exception.Message
    }
    throw
}
finally {
    try {
        if ($dockerAvailable -and $CleanupOnExit) {
            Write-ProgressLine 'Running cleanup for Phase 10 local container stack...'
            $downArguments = @(
                'compose',
                '--env-file', $envExampleFile,
                '--env-file', $envFile,
                '-f', $composeFile,
                '--profile', 'data',
                '--profile', 'identity',
                '--profile', 'storage',
                '--profile', 'messaging',
                '--profile', 'apps',
                '--profile', 'functions',
                'down',
                '--remove-orphans'
            )
            if ($RemoveVolumes) {
                Assert-Phase10VolumeOwnership
                $downArguments += '--volumes'
            }
            & docker @downArguments 2>&1 | Protect-Phase10Log | Tee-Object -FilePath (Join-Path $runDir 'docker-compose-down.log') | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Docker compose down failed with exit code $LASTEXITCODE"
            }

        }
        elseif ($dockerAvailable) {
            Write-ProgressLine 'Preserving the running stack, volumes, and image tags for NFR/rollback proof.'
        }
        else {
            Write-ProgressLine 'Skipping cleanup because Docker was unavailable.'
        }
        $summary.steps += [ordered]@{
            name = 'cleanup'
            status = 'passed'
            startedUtc = (Get-Date).ToUniversalTime().ToString('o')
            finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
            log = 'docker-compose-down.log'
        }
    }
    catch {
        $runFailed = $true
        $summary.steps += [ordered]@{
            name = 'cleanup'
            status = 'failed'
            startedUtc = (Get-Date).ToUniversalTime().ToString('o')
            finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
            log = 'docker-compose-down.log'
            error = $_.Exception.Message
        }
        Write-ProgressLine "Cleanup failed: $($_.Exception.Message)"
    }
    finally {
        if ([string]::IsNullOrWhiteSpace($previousDockerConfig)) {
            Remove-Item Env:DOCKER_CONFIG -ErrorAction SilentlyContinue
        }
        else {
            $env:DOCKER_CONFIG = $previousDockerConfig
        }
    }

    $summary.finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
    $summary.status = if ($runFailed) { 'failed' } elseif ($runPartial) { 'partial' } else { 'passed' }
    $summary.deferrals = @('DW-023','DW-024')
    $env:PHASE10_PAYMENT_REPORT_ROOT = $previousPaymentReportRoot
    Set-Content -Path $summaryPath -Value ($summary | ConvertTo-Json -Depth 6) -Encoding utf8
    $diagnostics = [ordered]@{
        target = $summary.target
        mode = 'endtoend'
        status = $summary.status
        startedUtc = $summary.startedUtc
        finishedUtc = $summary.finishedUtc
        runDir = $runDir
        summaryPath = $summaryPath
        logs = [ordered]@{
            startup = $startupLogPath
            progress = $progressLogPath
            smoke = Join-Path $runDir 'smoke.log'
            integrationPrep = Join-Path $runDir 'integration-prep.log'
            integration = Join-Path $runDir 'integration.log'
            integrationDetails = Join-Path $runDir 'integration'
            matrix = Join-Path $runDir 'matrix.log'
            cleanup = Join-Path $runDir 'docker-compose-down.log'
        }
        latestPointers = [ordered]@{
            run = $rootMarkerPath
            fullValidation = $latestPointerPath
            failure = $latestFailurePointerPath
        }
        failure = if ($runFailed) {
            [ordered]@{
                step = ($summary.steps | Where-Object { $_.name -eq 'failure' } | Select-Object -First 1)
                note = 'See the integration log and the step log path recorded in the step details.'
            }
        } else {
            $null
        }
    }
    Set-Content -Path $diagnosticsPath -Value ($diagnostics | ConvertTo-Json -Depth 8) -Encoding utf8
    Set-Content -Path $latestPointerPath -Value $runDir -Encoding utf8
    Set-Content -Path $rootMarkerPath -Value $runDir -Encoding utf8
    if ($runFailed) {
        Set-Content -Path $latestFailurePointerPath -Value $runDir -Encoding utf8
    }
    Write-Host "Phase 10 Docker end-to-end run directory: $runDir" -ForegroundColor Cyan
    Write-Host "Phase 10 Docker end-to-end diagnostics: $diagnosticsPath" -ForegroundColor Cyan
    if ($runFailed) {
        Write-Host "Phase 10 Docker end-to-end latest failure pointer: $latestFailurePointerPath" -ForegroundColor Yellow
    }
}
if ($runFailed -or $runPartial) { exit 1 }
