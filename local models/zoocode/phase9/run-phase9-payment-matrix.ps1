param(
    [ValidateRange(120, 300000)]
    [int]$TimeoutMs = 120000,

    [ValidateRange(120, 1800)]
    [int]$PaymentWaitSeconds = 300,

    [ValidateSet('dev', 'stg', 'prod')]
    [string]$Environment = 'dev',

    [ValidateSet('http', 'https')]
    [string]$Profile = 'http',

    [ValidateSet('dev', 'stg', 'prod', 'all')]
    [string]$Stage = 'all',

    [switch]$VerifyPayments
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$tenantSmoke = Join-Path $repoRoot 'scripts\test-frontend-tenant-bootstrap.ps1'
$paymentVerify = Join-Path $repoRoot 'scripts\verify-payment-run-physical.ps1'
$dockerProfileRunner = Join-Path $PSScriptRoot 'run-phase9-docker-profile.ps1'

if (-not (Test-Path $tenantSmoke)) {
    throw "Tenant bootstrap smoke script not found: $tenantSmoke"
}

if ($VerifyPayments -and -not (Test-Path $paymentVerify)) {
    throw "Payment verification script not found: $paymentVerify"
}

if (-not (Test-Path $dockerProfileRunner)) {
    throw "Docker profile runner not found: $dockerProfileRunner"
}

function Start-DockerProfile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Environment,

        [Parameter(Mandatory = $true)]
        [string]$Profile
    )

    Write-Host "Starting Docker profile $Environment/$Profile..." -ForegroundColor Cyan
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $dockerProfileRunner -Environment $Environment -Profile $Profile -Reset -Strict
    if ($LASTEXITCODE -ne 0) {
        throw "Docker profile $Environment/$Profile failed with exit code $LASTEXITCODE."
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
        default { throw "Unsupported matrix target: $Environment/$Profile" }
    }

    Push-Location (Join-Path $repoRoot 'Resources\Docker')
    try {
        Write-Host "Starting UI service $uiService..." -ForegroundColor Cyan
        & docker compose --env-file .env.local -f docker-compose.database.yml -f "docker-compose.$Environment.yml" --profile $Profile up -d $uiService
        if ($LASTEXITCODE -ne 0) {
            throw "UI service $uiService failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

$matrixTargets = @(
    @{ Environment = 'dev'; Profile = 'http'; Target = 'docker-dev-http' },
    @{ Environment = 'dev'; Profile = 'https'; Target = 'docker-dev-https' },
    @{ Environment = 'stg'; Profile = 'http'; Target = 'docker-stg-http' },
    @{ Environment = 'stg'; Profile = 'https'; Target = 'docker-stg-https' },
    @{ Environment = 'prod'; Profile = 'http'; Target = 'docker-prod-http' },
    @{ Environment = 'prod'; Profile = 'https'; Target = 'docker-prod-https' }
)

if ($Stage -ne 'all') {
    $matrixTargets = @($matrixTargets | Where-Object { $_.Environment -eq $Stage })
}

foreach ($matrixTarget in $matrixTargets) {
    Start-DockerProfile -Environment $matrixTarget.Environment -Profile $matrixTarget.Profile
    Start-DockerUiService -Environment $matrixTarget.Environment -Profile $matrixTarget.Profile

    Write-Host ""
    Write-Host "Running tenant bootstrap smoke for $($matrixTarget.Target)..." -ForegroundColor Cyan
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $tenantSmoke -Target $matrixTarget.Target -TimeoutMs $TimeoutMs
    if ($LASTEXITCODE -ne 0) {
        throw "Tenant matrix smoke failed for $($matrixTarget.Target) with exit code $LASTEXITCODE."
    }
}

if ($VerifyPayments) {
    Write-Host ""
    Write-Host "Waiting $PaymentWaitSeconds seconds before payment verification..." -ForegroundColor Yellow
    Start-Sleep -Seconds $PaymentWaitSeconds

    Write-Host "Running Docker payment verification for $Environment/$Profile..." -ForegroundColor Cyan
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $paymentVerify -Runtime docker -Environment $Environment -Profile $Profile
    if ($LASTEXITCODE -ne 0) {
        throw "Payment verification failed with exit code $LASTEXITCODE."
    }
}

Write-Host ""
Write-Host "Phase 9 tenant matrix smoke completed." -ForegroundColor Green
