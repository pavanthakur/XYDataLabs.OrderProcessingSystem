param(
    [ValidateSet('dev', 'stg', 'prod')]
    [string]$Environment = 'dev',

    [ValidateSet('http', 'https')]
    [string]$Profile = 'http',

    [ValidateSet('dev', 'stg', 'prod', 'all')]
    [string]$Stage = 'dev',

    [ValidateRange(120, 300000)]
    [int]$TenantSmokeTimeoutMs = 120000,

    [ValidateRange(15, 600)]
    [int]$WebhookWorkerWaitSeconds = 15,

    [ValidateRange(60, 900)]
    [int]$VerificationWaitSeconds = 180,

    [switch]$Reset,

    [switch]$NoPrePull,

    [switch]$Build,

    [switch]$InstallBrowser,

    [switch]$VerifyPayments,

    [switch]$ReuseExistingStack,

    [switch]$VerifyPhysicalLog,

    [string]$RunPrefix
)

$ErrorActionPreference = 'Stop'
$env:DOCKER_CONFIG = if ([string]::IsNullOrWhiteSpace($env:DOCKER_CONFIG)) {
    Join-Path $env:TEMP 'orderprocessing-docker-config'
} else {
    $env:DOCKER_CONFIG
}
if (-not (Test-Path $env:DOCKER_CONFIG)) {
    New-Item -ItemType Directory -Path $env:DOCKER_CONFIG | Out-Null
}
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$tenantSmoke = Join-Path $repoRoot 'scripts\test-frontend-tenant-bootstrap.ps1'
$webhookE2E = Join-Path $repoRoot 'scripts\test-webhook-e2e.ps1'
$physicalVerifier = Join-Path $repoRoot 'scripts\verify-payment-run-physical.ps1'
$dockerProfileRunner = Join-Path $PSScriptRoot 'run-phase9-docker-profile.ps1'
$phase9LogDir = Join-Path $repoRoot '.tmp'
$phase9LogFile = Join-Path $phase9LogDir ("phase9-payment-e2e-{0}-{1}.log" -f $Environment, $Profile)

if (-not (Test-Path $phase9LogDir)) {
    New-Item -ItemType Directory -Path $phase9LogDir | Out-Null
}

Start-Transcript -Path $phase9LogFile -Append | Out-Null

function Invoke-Checked {
    param(
        [scriptblock]$ScriptBlock,
        [string]$FailureMessage
    )

    $output = & $ScriptBlock 2>&1
    foreach ($line in @($output)) {
        if ($null -ne $line) {
            Write-Host $line
        }
    }
    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMessage (exit code $LASTEXITCODE)"
    }
}

function Start-DockerProfile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Environment,

        [Parameter(Mandatory = $true)]
        [string]$Profile
    )

    Write-Host "Starting Docker profile $Environment/$Profile..." -ForegroundColor Cyan
    $dockerArgs = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        $dockerProfileRunner
        '-Environment'
        $Environment
        '-Profile'
        $Profile
        '-Strict'
        '-BootstrapDatabases'
    )

    if ($Reset) {
        $dockerArgs += '-Reset'
    }

    if ($NoPrePull) {
        $dockerArgs += '-NoPrePull'
    }

    if ($Build) {
        $dockerArgs += '-LegacyBuild'
    }

    $output = & pwsh @dockerArgs 2>&1
    foreach ($line in @($output)) {
        if ($null -ne $line) {
            Write-Host $line
        }
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Docker profile $Environment/$Profile failed with exit code $LASTEXITCODE"
    }
}

function Start-DockerUiService {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Environment,

        [Parameter(Mandatory = $true)]
        [string]$Profile
    )

    $uiService = switch ("$Environment/$Profile") {
        'dev/http' { 'ui-dev-http' }
        'dev/https' { 'ui-dev-https' }
        'stg/http' { 'ui-stg-http' }
        'stg/https' { 'ui-stg-https' }
        'prod/http' { 'ui-prod-http' }
        'prod/https' { 'ui-prod-https' }
        default { throw "Unsupported payment E2E target: $Environment/$Profile" }
    }

    Push-Location (Join-Path $repoRoot 'Resources\Docker')
    try {
        Write-Host "Starting UI service $uiService..." -ForegroundColor Cyan
        $composeArgs = @(
            'compose'
            '--env-file'
            '.env.local'
            '-f'
            'docker-compose.database.yml'
            '-f'
            "docker-compose.$Environment.yml"
            '--profile'
            $Profile
            'up'
            '-d'
            '--build'
            $uiService
        )
        & docker @composeArgs
        if ($LASTEXITCODE -ne 0) {
            throw "UI service $uiService failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

function Get-WebhookApiBaseUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Environment,

        [Parameter(Mandatory = $true)]
        [string]$Profile
    )

    switch ("$Environment/$Profile") {
        'dev/http' { return 'http://localhost:5020' }
        'dev/https' { return 'https://localhost:5021' }
        'stg/http' { return 'http://localhost:5030' }
        'stg/https' { return 'https://localhost:5031' }
        'prod/http' { return 'http://localhost:5040' }
        'prod/https' { return 'https://localhost:5041' }
        default { throw "Unsupported webhook E2E target: $Environment/$Profile" }
    }
}

function Wait-ForHttpOk {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [ValidateRange(30, 1800)]
        [int]$TimeoutSeconds = 300
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3
            if ($response.StatusCode -eq 200) {
                return
            }
        }
        catch {
        }

        Start-Sleep -Seconds 2
    }

    throw "Timed out waiting for $Url"
}

function Assert-DockerStagingDatabasesPresent {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('dev', 'stg', 'prod')]
        [string]$Environment
    )

    if ($Environment -eq 'dev') {
        return
    }

    $expectedDatabases = switch ($Environment) {
        'stg' { @('OrderProcessingSystem_Stg', 'OrderProcessingSystem_TenantC_Stg') }
        'prod' { @('OrderProcessingSystem_Prod', 'OrderProcessingSystem_TenantC_Prod') }
    }

    $present = docker exec orderprocessing-sqlserver /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P (Get-Content (Join-Path $repoRoot 'Resources\Docker\.env.local') | Where-Object { $_ -match '^LOCAL_SQL_PASSWORD=' } | Select-Object -First 1).Split('=',2)[1] -C -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE name IN ('$(($expectedDatabases -join "','"))') ORDER BY name;" -h -1 -W 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect Docker SQL databases for ${Environment}: $([string]::Join([Environment]::NewLine, @($present | ForEach-Object { $_.ToString() })))"
    }

    $presentNames = @($present | Where-Object { $_ -and $_.ToString().Trim() -ne '' } | ForEach-Object { $_.ToString().Trim() })
    $missing = @($expectedDatabases | Where-Object { $presentNames -notcontains $_ })
    if ($missing.Count -gt 0) {
        throw "Docker SQL is missing required ${Environment} database(s): $($missing -join ', '). Provision them first before running Phase 9 payment E2E."
    }
}

if (-not (Test-Path $tenantSmoke)) {
    throw "Tenant bootstrap smoke script not found: $tenantSmoke"
}

if (-not (Test-Path $webhookE2E)) {
    throw "Webhook E2E script not found: $webhookE2E"
}

if ($VerifyPayments -and -not (Test-Path $physicalVerifier)) {
    throw "Physical payment verifier script not found: $physicalVerifier"
}

try {
    Write-Host "Phase 9 payment E2E started for $Environment/$Profile." -ForegroundColor Cyan

    $apiBaseUrl = Get-WebhookApiBaseUrl -Environment $Environment -Profile $Profile
    $target = switch ("$Environment/$Profile") {
        'dev/http' { 'docker-dev-http' }
        'dev/https' { 'docker-dev-https' }
        'stg/http' { 'docker-stg-http' }
        'stg/https' { 'docker-stg-https' }
        'prod/http' { 'docker-prod-http' }
        'prod/https' { 'docker-prod-https' }
        default { throw "Unsupported tenant smoke target for $Environment/$Profile" }
    }

    if (-not $ReuseExistingStack) {
        Start-DockerProfile -Environment $Environment -Profile $Profile
        Start-DockerUiService -Environment $Environment -Profile $Profile
    } else {
        Assert-DockerStagingDatabasesPresent -Environment $Environment
        Write-Host "ReuseExistingStack enabled. Waiting for existing API/UI endpoints to be healthy..." -ForegroundColor Yellow
        Wait-ForHttpOk -Url "$apiBaseUrl/health/ready" -TimeoutSeconds 300
        $uiReadyUrl = switch ("$Environment/$Profile") {
            'dev/http' { 'http://localhost:5022/' }
            'dev/https' { 'https://localhost:5023/' }
            'stg/http' { 'http://localhost:5032/' }
            'stg/https' { 'https://localhost:5033/' }
            'prod/http' { 'http://localhost:5042/' }
            'prod/https' { 'https://localhost:5043/' }
        }
        Wait-ForHttpOk -Url $uiReadyUrl -TimeoutSeconds 300
    }

    Assert-DockerStagingDatabasesPresent -Environment $Environment

    Write-Host ""
    Write-Host "Step 1/3: tenant bootstrap smoke for $target" -ForegroundColor Cyan
    Invoke-Checked {
        pwsh -NoProfile -ExecutionPolicy Bypass -File $tenantSmoke -Target $target -TimeoutMs $TenantSmokeTimeoutMs
    } "Tenant bootstrap smoke failed for $target"

    Write-Host ""
    Write-Host "Step 2/3: payment webhook matrix for $Environment/$Profile" -ForegroundColor Cyan
    Invoke-Checked {
        pwsh -NoProfile -ExecutionPolicy Bypass -File $webhookE2E -ApiBaseUrl $apiBaseUrl -WorkerWaitSeconds $WebhookWorkerWaitSeconds
    } "Webhook E2E matrix failed for $Environment/$Profile"

    if ($VerifyPayments -and $VerifyPhysicalLog) {
        Write-Host ""
        Write-Host "Step 3/3: physical payment verification for $Environment/$Profile" -ForegroundColor Cyan
        if ([string]::IsNullOrWhiteSpace($RunPrefix)) {
            Write-Host "No RunPrefix supplied. Waiting $VerificationWaitSeconds seconds before automatic verification resolution..." -ForegroundColor Yellow
            Start-Sleep -Seconds $VerificationWaitSeconds
            Invoke-Checked {
                pwsh -NoProfile -ExecutionPolicy Bypass -File $physicalVerifier -Runtime docker -Environment $Environment -Profile $Profile
            } "Physical payment verification failed for $Environment/$Profile"
        }
        else {
            Invoke-Checked {
                pwsh -NoProfile -ExecutionPolicy Bypass -File $physicalVerifier -Runtime docker -Environment $Environment -Profile $Profile -RunPrefix $RunPrefix
            } "Physical payment verification failed for $Environment/$Profile with run prefix $RunPrefix"
        }
    }
    elseif ($VerifyPayments) {
        Write-Host ""
        Write-Host "Physical payment verification skipped because -VerifyPhysicalLog was not supplied." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Phase 9 payment E2E completed successfully for $Environment/$Profile." -ForegroundColor Green
}
finally {
    Stop-Transcript | Out-Null
}
