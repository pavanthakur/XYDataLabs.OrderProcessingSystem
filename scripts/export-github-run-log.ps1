param(
    [Parameter(Mandatory = $false)]
    [string]$Url,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^\d+$')]
    [string]$RunId,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^\d+$')]
    [string]$JobId,

    [string]$OutputRoot = (Join-Path $PWD 'TestResults/GitHubActions'),

    [switch]$ResolveOnly
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

function Resolve-GitHubActionsIds {
    param(
        [string]$InputUrl,
        [string]$InputRunId,
        [string]$InputJobId
    )

    $resolvedRunId = $InputRunId
    $resolvedJobId = $InputJobId

    if (-not [string]::IsNullOrWhiteSpace($InputUrl)) {
        if ($InputUrl -match '/actions/runs/(?<runId>\d+)/job/(?<jobId>\d+)') {
            $resolvedRunId = $Matches.runId
            $resolvedJobId = $Matches.jobId
        }
        elseif ($InputUrl -match '/actions/runs/(?<runId>\d+)') {
            $resolvedRunId = $Matches.runId
        }
        else {
            throw "Could not extract a GitHub Actions run id from Url '$InputUrl'. Expected a URL containing '/actions/runs/<run-id>' and preferably '/job/<job-id>'."
        }
    }

    if ([string]::IsNullOrWhiteSpace($resolvedRunId)) {
        throw "RunId is required. Pass -Url '<GitHub Actions job URL>' or -RunId <run-id> -JobId <job-id>."
    }

    if ([string]::IsNullOrWhiteSpace($resolvedJobId)) {
        throw "JobId is required. Pass a job URL containing '/job/<job-id>' or add -JobId <job-id>."
    }

    return [pscustomobject]@{
        RunId = $resolvedRunId
        JobId = $resolvedJobId
    }
}

$ids = Resolve-GitHubActionsIds -InputUrl $Url -InputRunId $RunId -InputJobId $JobId
$RunId = $ids.RunId
$JobId = $ids.JobId

$runDirectory = Join-Path $OutputRoot $RunId
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

$logPath = Join-Path $runDirectory "job-$JobId.log"
$summaryPath = Join-Path $runDirectory "job-$JobId.summary.txt"
$latestLogPath = Join-Path $OutputRoot 'latest-job.log'
$latestSummaryPath = Join-Path $OutputRoot 'latest-job.summary.txt'
$latestPathFile = Join-Path $OutputRoot 'latest-job-log-path.txt'

if ($ResolveOnly) {
    Write-Host "RunId: $RunId"
    Write-Host "JobId: $JobId"
    Write-Host "LogPath: $logPath"
    Write-Host "LatestLogPath: $latestLogPath"
    return
}

$ghPath = Resolve-CommandOrThrow -CommandName 'gh'

Write-Info "Checking GitHub CLI authentication..."
$authOutput = & $ghPath auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    $authText = ($authOutput | Out-String).Trim()
    throw "GitHub CLI is not authenticated. Run 'gh auth login -h github.com' in this terminal. Details: $authText"
}

Write-Info "Exporting GitHub Actions job log..."
$logOutput = & $ghPath run view $RunId --job $JobId --log 2>&1
if ($LASTEXITCODE -ne 0) {
    $failureText = ($logOutput | Out-String).Trim()
    throw "Failed to export GitHub Actions job log for run '$RunId', job '$JobId'. Details: $failureText"
}

$logOutput | Set-Content -LiteralPath $logPath -Encoding utf8
Copy-Item -LiteralPath $logPath -Destination $latestLogPath -Force

$summary = @(
    "GitHub Actions Job Log Export"
    "RunId: $RunId"
    "JobId: $JobId"
    "ExportedAtLocal: $(Get-Date -Format o)"
    "LogPath: $logPath"
    "LatestLogPath: $latestLogPath"
    ""
    "Next step:"
    "Tell Codex the export is complete. Codex can read: $latestLogPath"
)

$summary | Set-Content -LiteralPath $summaryPath -Encoding utf8
Copy-Item -LiteralPath $summaryPath -Destination $latestSummaryPath -Force
$logPath | Set-Content -LiteralPath $latestPathFile -Encoding utf8

Write-Success "GitHub job log exported."
Write-Host "LogPath: $logPath"
Write-Host "LatestLogPath: $latestLogPath"
Write-Host "SummaryPath: $summaryPath"
