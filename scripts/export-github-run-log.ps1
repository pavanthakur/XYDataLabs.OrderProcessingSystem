param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+$')]
    [string]$RunId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+$')]
    [string]$JobId,

    [string]$OutputRoot = (Join-Path $PWD 'TestResults/GitHubActions')
)

$ErrorActionPreference = 'Stop'

function Write-Info {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Green
}

function Resolve-CommandOrThrow {
    param([string]$CommandName)

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "Required command '$CommandName' was not found. Install GitHub CLI and run 'gh auth login -h github.com'."
    }

    return $command.Source
}

$ghPath = Resolve-CommandOrThrow -CommandName 'gh'

Write-Info "Checking GitHub CLI authentication..."
$authOutput = & $ghPath auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    $authText = ($authOutput | Out-String).Trim()
    throw "GitHub CLI is not authenticated. Run 'gh auth login -h github.com' in this terminal. Details: $authText"
}

$runDirectory = Join-Path $OutputRoot $RunId
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $runDirectory "job-$JobId-$timestamp.log"
$summaryPath = Join-Path $runDirectory "job-$JobId-$timestamp.summary.txt"

Write-Info "Exporting GitHub Actions job log..."
$logOutput = & $ghPath run view $RunId --job $JobId --log 2>&1
if ($LASTEXITCODE -ne 0) {
    $failureText = ($logOutput | Out-String).Trim()
    throw "Failed to export GitHub Actions job log for run '$RunId', job '$JobId'. Details: $failureText"
}

$logOutput | Set-Content -LiteralPath $logPath -Encoding utf8

$summary = @(
    "GitHub Actions Job Log Export"
    "RunId: $RunId"
    "JobId: $JobId"
    "ExportedAtLocal: $(Get-Date -Format o)"
    "LogPath: $logPath"
    ""
    "Next step:"
    "Share this path with Codex for diagnosis: $logPath"
)

$summary | Set-Content -LiteralPath $summaryPath -Encoding utf8

Write-Success "GitHub job log exported."
Write-Host "LogPath: $logPath"
Write-Host "SummaryPath: $summaryPath"
