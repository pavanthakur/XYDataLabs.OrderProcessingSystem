#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ArtifactRoot,

    [ValidateRange(1, 1000)]
    [int]$BurstMessageCount = 100,

    [ValidateRange(30, 600)]
    [int]$PerformanceTimeoutSeconds = 180,

    [ValidateRange(1, 120)]
    [double]$MaximumP95Seconds = 30
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $workspaceRoot 'compose\docker-compose.phase10.yml'
$envExampleFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local.example'
$envFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local'
$nfrRoot = Join-Path $ArtifactRoot 'nfr'
$progressPath = Join-Path $nfrRoot 'progress.log'
$currentStepPath = Join-Path $nfrRoot 'current-step.txt'
$summaryPath = Join-Path $nfrRoot 'summary.json'
$istZone = [TimeZoneInfo]::FindSystemTimeZoneById('India Standard Time')
$startedAt = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $istZone)

New-Item -ItemType Directory -Path $nfrRoot -Force | Out-Null
Set-Content -LiteralPath $progressPath -Value '' -Encoding utf8
Set-Content -LiteralPath $currentStepPath -Value 'initializing' -Encoding utf8
Set-Content -LiteralPath (Join-Path $nfrRoot 'run-plan.txt') -Encoding utf8 -Value @(
    'Phase 10 local NFR proof',
    "Started (IST): $($startedAt.ToString('o'))",
    'Functional: focused durability, tenant, payment, DLQ, and replay integration tests.',
    "Performance: $BurstMessageCount OrderCreatedV1 messages; exact effects; consumer P95 <= $MaximumP95Seconds seconds.",
    'Operational: Compose controls, image evidence, restart diagnostics, and an executed previous-image rollback/restore.',
    'Policy: categories are reported independently; the aggregate fails when any category fails.'
)

$categories = [ordered]@{
    functional = [ordered]@{ status = 'running'; checks = @(); error = $null }
    performance = [ordered]@{ status = 'running'; checks = @(); error = $null }
    operational = [ordered]@{ status = 'running'; checks = @(); error = $null }
}
$summary = [ordered]@{
    status = 'running'
    startedAtIst = $startedAt.ToString('o')
    completedAtIst = $null
    artifactRoot = $nfrRoot
    commitSha = (& git -C $workspaceRoot rev-parse HEAD).Trim()
    categories = $categories
}

function Get-IstNow {
    [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $istZone)
}

function Write-NfrSummary {
    $summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath -Encoding utf8
}

function Write-Progress {
    param([Parameter(Mandatory = $true)][string]$Message)

    $line = '[{0}] {1}' -f (Get-IstNow).ToString('o'), $Message
    Write-Host $line
    Add-Content -LiteralPath $progressPath -Value $line -Encoding utf8
}

function Get-EnvValues {
    $values = @{}
    foreach ($path in @($envExampleFile, $envFile)) {
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }

        foreach ($line in Get-Content -LiteralPath $path) {
            if ($line -notmatch '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$') {
                continue
            }

            $value = $Matches[2].Trim()
            if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $values[$Matches[1]] = $value
        }
    }
    return $values
}

function Invoke-CategoryCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Command
    )

    $slug = (($Name -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLowerInvariant())
    $logPath = Join-Path $nfrRoot "$Category-$slug.log"
    Set-Content -LiteralPath $currentStepPath -Value "$Category/$Name" -Encoding utf8
    Write-Progress "START $Category/$Name"
    $started = Get-IstNow
    try {
        & $Command 2>&1 |
            Tee-Object -FilePath $logPath |
            ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) {
            throw "$Name failed with exit code $LASTEXITCODE."
        }

        $categories[$Category].checks += [ordered]@{
            name = $Name
            status = 'passed'
            startedAtIst = $started.ToString('o')
            completedAtIst = (Get-IstNow).ToString('o')
            log = [IO.Path]::GetFileName($logPath)
        }
        Write-Progress "PASS $Category/$Name"
        Write-NfrSummary
        return $true
    }
    catch {
        $categories[$Category].checks += [ordered]@{
            name = $Name
            status = 'failed'
            startedAtIst = $started.ToString('o')
            completedAtIst = (Get-IstNow).ToString('o')
            log = [IO.Path]::GetFileName($logPath)
            error = $_.Exception.Message
        }
        $categories[$Category].error = $_.Exception.Message
        Write-Progress "FAIL $Category/$Name - $($_.Exception.Message)"
        Write-NfrSummary
        return $false
    }
}

function Wait-ForUrl {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [int]$TimeoutSeconds = 120
    )

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -SkipHttpErrorCheck -Uri $Url -TimeoutSec 5
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
                return
            }
        }
        catch {
        }
        Start-Sleep -Seconds 2
    }

    throw "Timed out waiting for $Url."
}

Write-NfrSummary
Write-Progress "NFR proof initialized. artifactRoot=$nfrRoot"
$envValues = Get-EnvValues
$sqlPassword = $envValues['LOCAL_SQL_PASSWORD']
$serviceBusConnectionString = $envValues['LOCAL_SERVICEBUS_HOST_CONNECTION_STRING']
$topicName = $envValues['LOCAL_SERVICEBUS_TOPIC_NAME']
if ([string]::IsNullOrWhiteSpace($topicName)) {
    $topicName = 'order-events'
}
$sqlConnectionString = "Server=localhost,1433;Database=OrderProcessingSystem_Dev;User Id=sa;Password=$sqlPassword;Encrypt=False;TrustServerCertificate=True;MultipleActiveResultSets=true"
$testProject = 'tests/XYDataLabs.OrderProcessingSystem.Integration.Tests/XYDataLabs.OrderProcessingSystem.Integration.Tests.csproj'
$functionalFilter = 'FullyQualifiedName~Outbox|FullyQualifiedName~Inbox|FullyQualifiedName~Tenant|FullyQualifiedName~Payment|FullyQualifiedName~Dlq|FullyQualifiedName~Replay'

$previousTestConnection = $env:ORDERPROCESSING_TEST_CONNECTION_STRING
$env:ORDERPROCESSING_TEST_CONNECTION_STRING = $sqlConnectionString
try {
    $functionalPassed = Invoke-CategoryCommand -Category 'functional' -Name 'Durability and tenant integration tests' -Command {
        dotnet test $testProject `
            --filter $functionalFilter `
            --logger "trx;LogFileName=$nfrRoot\functional-tests.trx"
    }
}
finally {
    if ([string]::IsNullOrWhiteSpace($previousTestConnection)) {
        Remove-Item Env:ORDERPROCESSING_TEST_CONNECTION_STRING -ErrorAction SilentlyContinue
    }
    else {
        $env:ORDERPROCESSING_TEST_CONNECTION_STRING = $previousTestConnection
    }
}
$categories.functional.status = if ($functionalPassed) { 'passed' } else { 'failed' }
Set-Content -LiteralPath (Join-Path $nfrRoot 'functional-summary.json') `
    -Value ($categories.functional | ConvertTo-Json -Depth 8) -Encoding utf8
Write-NfrSummary

$performancePrerequisites = -not [string]::IsNullOrWhiteSpace($sqlPassword) `
    -and $sqlPassword -notmatch '^<' `
    -and -not [string]::IsNullOrWhiteSpace($serviceBusConnectionString) `
    -and $envValues['LOCAL_SERVICEBUS_ENABLED'] -eq 'true'

if (-not $performancePrerequisites) {
    $categories.performance.status = 'failed'
    $categories.performance.error =
        'LOCAL_SERVICEBUS_ENABLED=true and valid LOCAL_SERVICEBUS_HOST_CONNECTION_STRING/LOCAL_SQL_PASSWORD values are required.'
}
else {
    $probeResultPath = Join-Path $nfrRoot 'performance-probe.json'
    $performancePassed = Invoke-CategoryCommand -Category 'performance' -Name 'Build NFR probe' -Command {
        dotnet build tools/Phase10.NfrProbe/Phase10.NfrProbe.csproj --no-restore
    }
    if ($performancePassed) {
        $performancePassed = Invoke-CategoryCommand -Category 'performance' -Name '100 message durable consumer burst' -Command {
            dotnet run `
                --project tools/Phase10.NfrProbe/Phase10.NfrProbe.csproj `
                --no-build `
                -- `
                --servicebus-connection-string $serviceBusConnectionString `
                --sql-connection-string $sqlConnectionString `
                --topic $topicName `
                --tenant-id 1 `
                --tenant-code TenantA `
                --message-count $BurstMessageCount `
                --timeout-seconds $PerformanceTimeoutSeconds `
                --maximum-p95-seconds $MaximumP95Seconds `
                --result-path $probeResultPath
        }
    }
    $categories.performance.status = if ($performancePassed) { 'passed' } else { 'failed' }
}
Set-Content -LiteralPath (Join-Path $nfrRoot 'performance-summary.json') `
    -Value ($categories.performance | ConvertTo-Json -Depth 8) -Encoding utf8
Write-NfrSummary

$composeArgs = @(
    'compose',
    '--env-file', $envExampleFile,
    '--env-file', $envFile,
    '-f', $composeFile,
    '--profile', 'data',
    '--profile', 'identity',
    '--profile', 'storage',
    '--profile', 'messaging',
    '--profile', 'apps',
    '--profile', 'functions'
)
$operationalPassed = Invoke-CategoryCommand -Category 'operational' -Name 'Compose controls and running services' -Command {
    docker @composeArgs config --quiet
    if ($LASTEXITCODE -ne 0) { throw "docker compose config failed with exit code $LASTEXITCODE." }
    docker @composeArgs ps
}

$imageOwner = if ([string]::IsNullOrWhiteSpace($env:PHASE10_IMAGE_OWNER)) { 'pavanthakur' } else { $env:PHASE10_IMAGE_OWNER }
$currentImageTag = if ([string]::IsNullOrWhiteSpace($env:PHASE10_IMAGE_TAG)) { 'dev' } else { $env:PHASE10_IMAGE_TAG }
$previousImageTag = $env:PHASE10_PREVIOUS_IMAGE_TAG
if ([string]::IsNullOrWhiteSpace($previousImageTag)) {
    $operationalPassed = $false
    $categories.operational.error =
        'PHASE10_PREVIOUS_IMAGE_TAG is required so rollback is executed rather than documented only.'
}
else {
    $currentInventoryImage = "ghcr.io/$imageOwner/orderprocessing-inventory:$currentImageTag"
    $previousInventoryImage = "ghcr.io/$imageOwner/orderprocessing-inventory:$previousImageTag"
    $operationalPassed = (Invoke-CategoryCommand -Category 'operational' -Name 'Retained image digest evidence' -Command {
        docker image inspect $currentInventoryImage $previousInventoryImage `
            --format '{{.RepoTags}} {{.Id}} {{json .RepoDigests}}'
    }) -and $operationalPassed

    if ($operationalPassed) {
        $originalTag = $env:PHASE10_IMAGE_TAG
        try {
            $env:PHASE10_IMAGE_TAG = $previousImageTag
            $rollbackPassed = Invoke-CategoryCommand -Category 'operational' -Name 'Rollback inventory to previous image' -Command {
                docker @composeArgs up -d --no-build inventory
                if ($LASTEXITCODE -ne 0) { throw "Previous image startup failed with exit code $LASTEXITCODE." }
                Wait-ForUrl -Url 'http://localhost:5082/health/ready'
            }
        }
        finally {
            $env:PHASE10_IMAGE_TAG = $currentImageTag
            $restorePassed = Invoke-CategoryCommand -Category 'operational' -Name 'Restore inventory current image' -Command {
                docker @composeArgs up -d --no-build inventory
                if ($LASTEXITCODE -ne 0) { throw "Current image restore failed with exit code $LASTEXITCODE." }
                Wait-ForUrl -Url 'http://localhost:5082/health/ready'
            }
            if ([string]::IsNullOrWhiteSpace($originalTag)) {
                Remove-Item Env:PHASE10_IMAGE_TAG -ErrorAction SilentlyContinue
            }
            else {
                $env:PHASE10_IMAGE_TAG = $originalTag
            }
        }
        $operationalPassed = $rollbackPassed -and $restorePassed -and $operationalPassed
    }
}

if ($operationalPassed) {
    $operationalPassed = Invoke-CategoryCommand -Category 'operational' -Name 'Consumer restart diagnostics' -Command {
        docker @composeArgs restart inventory notifications
        if ($LASTEXITCODE -ne 0) { throw "Consumer restart failed with exit code $LASTEXITCODE." }
        Wait-ForUrl -Url 'http://localhost:5082/health/ready'
        Wait-ForUrl -Url 'http://localhost:5083/health/ready'
        docker @composeArgs logs --tail 200 inventory notifications
    }
}
$categories.operational.status = if ($operationalPassed) { 'passed' } else { 'failed' }
Set-Content -LiteralPath (Join-Path $nfrRoot 'operational-summary.json') `
    -Value ($categories.operational | ConvertTo-Json -Depth 8) -Encoding utf8

$allPassed = @($categories.Values | Where-Object { $_.status -ne 'passed' }).Count -eq 0
$summary.status = if ($allPassed) { 'passed' } else { 'failed' }
$summary.completedAtIst = (Get-IstNow).ToString('o')
Set-Content -LiteralPath $currentStepPath -Value 'completed' -Encoding utf8
Write-NfrSummary
Write-Progress "NFR proof $($summary.status)."

if (-not $allPassed) {
    throw "Phase 10 NFR proof failed. Review $summaryPath and the three category summaries."
}
