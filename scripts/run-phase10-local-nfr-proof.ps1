#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ArtifactRoot,

    [string]$ProofName = 'Phase 10 local NFR proof',

    [ValidateRange(1, 1000)]
    [int]$BurstMessageCount = 100,

    [ValidateRange(30, 3600)]
    [int]$PerformanceTimeoutSeconds = 2400,

    [ValidateRange(1, 120)]
    [double]$MaximumP95Seconds = 30,

    [switch]$UseCleanReset,

    [switch]$SkipOperationalChecks
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
    $ProofName,
    "Started (IST): $($startedAt.ToString('o'))",
    'Functional: focused durability, DLQ, and replay integration tests.',
    "Performance: 1-message canary, then $BurstMessageCount OrderCreatedV1 messages; consumer P95 <= $MaximumP95Seconds seconds.",
    "Clean reset: $(if ($UseCleanReset) { 'enabled' } else { 'available via -UseCleanReset' }).",
    "Operational checks: $(if ($SkipOperationalChecks) { 'skipped via -SkipOperationalChecks' } else { 'enabled' }).",
    'Tenant: dedicated/shared routing and tenant registry behavior are reported independently.',
    'Payments: provider seed/reconciliation checks plus dynamic provider reassignment matrix are reported independently.',
    'Security: local Keycloak-backed API auth tests, browser PKCE/operator authorization proof, and artifact secret scan.',
    'Operational: Compose controls and restart diagnostics are reported independently from recovery.',
    'Recovery: retained image evidence and executed previous-image rollback/restore are reported independently.',
    'Policy: categories are reported independently; the aggregate fails when any category fails.'
)

$categories = [ordered]@{
    functional = [ordered]@{ status = 'running'; checks = @(); error = $null }
    performance = [ordered]@{ status = 'running'; checks = @(); error = $null }
    tenant = [ordered]@{ status = 'running'; checks = @(); error = $null }
    payments = [ordered]@{ status = 'running'; checks = @(); error = $null }
    operational = [ordered]@{ status = 'running'; checks = @(); error = $null }
    recovery = [ordered]@{ status = 'running'; checks = @(); error = $null }
    security = [ordered]@{ status = 'running'; checks = @(); error = $null }
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
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
                return
            }
        }
        catch {
        }
        Start-Sleep -Seconds 2
    }

    throw "Timed out waiting for $Url."
}

function Wait-ForDockerLogPatterns {
    param(
        [Parameter(Mandatory = $true)][string[]]$ContainerNames,
        [Parameter(Mandatory = $true)][string[]]$Patterns,
        [int]$TimeoutSeconds = 180,
        [int]$SinceMinutes = 20
    )

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        $logOutput = foreach ($containerName in $ContainerNames) {
            & docker logs --no-color --since ("{0}m" -f $SinceMinutes) $containerName 2>&1
        }
        $text = ($logOutput -join "`n")
        $missing = $Patterns | Where-Object { $text -notmatch [regex]::Escape($_) }
        if (-not $missing) {
            return
        }

        Start-Sleep -Seconds 5
    }

    throw "Timed out waiting for docker log patterns: $($Patterns -join ', ')."
}

function Get-Phase10ComposeArguments {
    return @(
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
}

function Resolve-ComposeServiceContainerName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName
    )

    $composeArgs = Get-Phase10ComposeArguments
    $containerId = (& docker @composeArgs ps -q $ServiceName | Select-Object -First 1).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($containerId)) {
        throw "Could not resolve the running container id for compose service '$ServiceName'."
    }

    $containerName = (& docker inspect -f '{{.Name}}' $containerId | Select-Object -First 1).Trim().TrimStart('/')
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($containerName)) {
        throw "Could not resolve the running container name for compose service '$ServiceName'."
    }

    return $containerName
}

function Resolve-PreviousInventoryImageTag {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImageOwner
    )

    if (-not [string]::IsNullOrWhiteSpace($env:PHASE10_PREVIOUS_IMAGE_TAG)) {
        return $env:PHASE10_PREVIOUS_IMAGE_TAG
    }

    $discoveredPreviousTag = & docker image ls --format '{{.Repository}}:{{.Tag}}' |
        Where-Object { $_ -match "^ghcr\.io/$([regex]::Escape($ImageOwner))/orderprocessing-inventory:phase10-prev-" } |
        Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($discoveredPreviousTag)) {
        return $null
    }

    return ($discoveredPreviousTag -split ':', 2)[1]
}

function Assert-DockerImageExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImageName
    )

    & docker image inspect $ImageName 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Required rollback image is not available locally: $ImageName"
    }
}

function Invoke-Phase10IdentityChecks {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category
    )

    $apiIdentityPassed = Invoke-CategoryCommand -Category $Category -Name 'Identity and authorization tests' -Command {
        dotnet test 'tests/XYDataLabs.OrderProcessingSystem.API.Tests/XYDataLabs.OrderProcessingSystem.API.Tests.csproj' `
            --filter 'FullyQualifiedName~Identity|FullyQualifiedName~Authorization|FullyQualifiedName~Tenant' `
            --logger "trx;LogFileName=$nfrRoot\security-identity-tests.trx"
    }
    if (-not $apiIdentityPassed) {
        return $false
    }

    $previousKeycloakPassword = $env:KEYCLOAK_TENANT_ADMIN_PASSWORD
    try {
        $keycloakPassword = $envValues['KEYCLOAK_TENANT_ADMIN_PASSWORD']
        if (-not [string]::IsNullOrWhiteSpace($keycloakPassword)) {
            $env:KEYCLOAK_TENANT_ADMIN_PASSWORD = $keycloakPassword
        }

        return Invoke-CategoryCommand -Category $Category -Name 'Keycloak PKCE and authorization browser proof' -Command {
            npm --prefix (Join-Path $workspaceRoot 'frontend') run proof:phase10:identity `
                --workspace @xydatalabs/orderprocessing-web `
                -- `
                --url 'http://localhost:5022' `
                --gateway-api-url 'http://localhost:5080' `
                --orders-api-url 'http://localhost:5081' `
                --payments-api-url 'http://localhost:5084' `
                --approval-api-url 'http://localhost:5081' `
                --output "$nfrRoot\security-identity-browser-evidence.json"
        }
    }
    finally {
        if ([string]::IsNullOrWhiteSpace($previousKeycloakPassword)) {
            Remove-Item Env:KEYCLOAK_TENANT_ADMIN_PASSWORD -ErrorAction SilentlyContinue
        }
        else {
            $env:KEYCLOAK_TENANT_ADMIN_PASSWORD = $previousKeycloakPassword
        }
    }
}

function Write-CategorySummaryFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category
    )

    Set-Content -LiteralPath (Join-Path $nfrRoot "$Category-summary.json") `
        -Value ($categories[$Category] | ConvertTo-Json -Depth 8) -Encoding utf8
}

function Invoke-ArtifactSecretScan {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category
    )

    return Invoke-CategoryCommand -Category $Category -Name 'Artifact secret scan' -Command {
        $sensitiveValues = @(
            $envValues['KEYCLOAK_TENANT_ADMIN_PASSWORD'],
            $envValues['LOCAL_OPENPAY_PRIVATE_KEY'],
            $envValues['LOCAL_RAZORPAY_PRIVATE_KEY'],
            $envValues['LOCAL_SQL_PASSWORD'],
            $envValues['LOCAL_SERVICEBUS_HOST_CONNECTION_STRING']
        ) | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and $_ -notmatch '^<'
        } | Select-Object -Unique

        $files = Get-ChildItem -LiteralPath $nfrRoot -Recurse -File |
            Where-Object { $_.Extension -in @('.json', '.log', '.trx', '.txt') }

        foreach ($sensitiveValue in $sensitiveValues) {
            $match = $files | Select-String -SimpleMatch -Pattern $sensitiveValue -List | Select-Object -First 1
            if ($null -ne $match) {
                throw "Sensitive value leaked into artifact file $($match.Path)."
            }
        }

        $tokenMatch = $files | Select-String -Pattern 'Bearer\s+[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+' -List | Select-Object -First 1
        if ($null -ne $tokenMatch) {
            throw "Bearer token-like content found in artifact file $($tokenMatch.Path)."
        }

        Write-Host 'No known secrets or bearer-token patterns were found in the NFR artifacts.'
    }
}

Write-NfrSummary
Write-Progress "$ProofName initialized. artifactRoot=$nfrRoot"
$envValues = Get-EnvValues
$sqlPassword = $envValues['LOCAL_SQL_PASSWORD']
$serviceBusConnectionString = $envValues['LOCAL_SERVICEBUS_HOST_CONNECTION_STRING']
$topicName = $envValues['LOCAL_SERVICEBUS_TOPIC_NAME']
$imageOwner = if ([string]::IsNullOrWhiteSpace($env:PHASE10_IMAGE_OWNER)) { 'pavanthakur' } else { $env:PHASE10_IMAGE_OWNER }
$currentImageTag = if ([string]::IsNullOrWhiteSpace($env:PHASE10_IMAGE_TAG)) { 'dev' } else { $env:PHASE10_IMAGE_TAG }
$previousImageTag = $null
$currentInventoryImage = $null
$previousInventoryImage = $null
if ([string]::IsNullOrWhiteSpace($topicName)) {
    $topicName = 'order-events'
}
$sqlConnectionString = "Server=localhost,1433;Database=OrderProcessingSystem_Dev;User Id=sa;Password=$sqlPassword;Encrypt=False;TrustServerCertificate=True;MultipleActiveResultSets=true"
$testProject = 'tests/XYDataLabs.OrderProcessingSystem.Integration.Tests/XYDataLabs.OrderProcessingSystem.Integration.Tests.csproj'
$functionalFilter = 'FullyQualifiedName~Outbox|FullyQualifiedName~Inbox|FullyQualifiedName~Dlq|FullyQualifiedName~Replay'
$tenantFilter = 'FullyQualifiedName~DedicatedTenant|FullyQualifiedName~TenantMiddleware|FullyQualifiedName~TenantRegistryService|FullyQualifiedName~TenantIsolation'
$paymentFilter = 'FullyQualifiedName~PaymentProviderSeed|FullyQualifiedName~PaymentReconciliation'

if (-not $SkipOperationalChecks) {
    $previousImageTag = Resolve-PreviousInventoryImageTag -ImageOwner $imageOwner
    if ([string]::IsNullOrWhiteSpace($previousImageTag)) {
        throw 'Rollback prerequisite missing: set PHASE10_PREVIOUS_IMAGE_TAG to a retained inventory image tag, or keep a local image tagged like phase10-prev-*. L5 requires an executed rollback, not a documented-only plan.'
    }

    $currentInventoryImage = "ghcr.io/$imageOwner/orderprocessing-inventory:$currentImageTag"
    $previousInventoryImage = "ghcr.io/$imageOwner/orderprocessing-inventory:$previousImageTag"
    Assert-DockerImageExists -ImageName $currentInventoryImage
    Assert-DockerImageExists -ImageName $previousInventoryImage
    Write-Progress "Rollback prerequisite resolved. currentImage=$currentInventoryImage previousImage=$previousInventoryImage"
}

$previousTestConnection = $env:ORDERPROCESSING_TEST_CONNECTION_STRING
$previousNfrSqlConnection = $env:PHASE10_NFR_SQL_CONNECTION_STRING
$previousNfrServiceBusConnection = $env:PHASE10_NFR_SERVICEBUS_CONNECTION_STRING
$env:ORDERPROCESSING_TEST_CONNECTION_STRING = $sqlConnectionString
$env:PHASE10_NFR_SQL_CONNECTION_STRING = $sqlConnectionString
$env:PHASE10_NFR_SERVICEBUS_CONNECTION_STRING = $serviceBusConnectionString
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
    if ([string]::IsNullOrWhiteSpace($previousNfrSqlConnection)) {
        Remove-Item Env:PHASE10_NFR_SQL_CONNECTION_STRING -ErrorAction SilentlyContinue
    }
    else {
        $env:PHASE10_NFR_SQL_CONNECTION_STRING = $previousNfrSqlConnection
    }
    if ([string]::IsNullOrWhiteSpace($previousNfrServiceBusConnection)) {
        Remove-Item Env:PHASE10_NFR_SERVICEBUS_CONNECTION_STRING -ErrorAction SilentlyContinue
    }
    else {
        $env:PHASE10_NFR_SERVICEBUS_CONNECTION_STRING = $previousNfrServiceBusConnection
    }
}
$categories.functional.status = if ($functionalPassed) { 'passed' } else { 'failed' }
Write-CategorySummaryFile -Category 'functional'
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
        $consumerContainers = @(
            Resolve-ComposeServiceContainerName -ServiceName 'inventory'
            Resolve-ComposeServiceContainerName -ServiceName 'notifications'
        )
        if ($UseCleanReset) {
            Write-Progress 'Clean reset requested. Resetting Service Bus emulator before performance burst.'
            $serviceBusContainer = Resolve-ComposeServiceContainerName -ServiceName 'servicebus-emulator'

            & docker restart $serviceBusContainer
            if ($LASTEXITCODE -ne 0) { throw "Service Bus emulator reset failed with exit code $LASTEXITCODE." }
            Write-Progress 'Waiting for Service Bus emulator readiness after reset.'
            Wait-ForUrl -Url 'http://localhost:5300/health' -TimeoutSeconds 600
            Write-Progress 'Restarting inventory and notifications consumers after Service Bus reset.'
            foreach ($consumerContainer in $consumerContainers) {
                $running = (& docker inspect -f '{{.State.Running}}' $consumerContainer).Trim()
                if ($running -ne 'true') {
                    & docker start $consumerContainer
                    if ($LASTEXITCODE -ne 0) { throw "Consumer warm-up start failed for $consumerContainer with exit code $LASTEXITCODE." }
                }
            }
            Write-Progress 'Waiting for consumer readiness after Service Bus reset.'
            Wait-ForUrl -Url 'http://localhost:5082/health/ready' -TimeoutSeconds 600
            Wait-ForUrl -Url 'http://localhost:5083/health/ready' -TimeoutSeconds 600
        }
        else {
            Write-Progress 'Skipping clean reset; using the warm local stack path.'
            Write-Progress 'Waiting for consumer readiness on the running stack.'
            Wait-ForUrl -Url 'http://localhost:5082/health/ready' -TimeoutSeconds 600
            Wait-ForUrl -Url 'http://localhost:5083/health/ready' -TimeoutSeconds 600
        }
        Start-Sleep -Seconds 10
        $warmupProbeResultPath = Join-Path $nfrRoot 'performance-probe-warmup.json'
        $performancePassed = Invoke-CategoryCommand -Category 'performance' -Name '1 message durable consumer warm-up canary' -Command {
            dotnet run `
                --project tools/Phase10.NfrProbe/Phase10.NfrProbe.csproj `
                --no-build `
                -- `
                --servicebus-connection-string $serviceBusConnectionString `
                --sql-connection-string $sqlConnectionString `
                --sql-read-mode docker-compose `
                --topic $topicName `
                --tenant-id 1 `
                --tenant-code TenantA `
                --message-count 1 `
                --timeout-seconds 900 `
                --maximum-p95-seconds $MaximumP95Seconds `
                --result-path $warmupProbeResultPath
        }
        if ($performancePassed) {
            Write-Progress 'Warm-up canary passed. Starting the 100 message performance burst.'
            $performancePassed = Invoke-CategoryCommand -Category 'performance' -Name '100 message durable consumer burst' -Command {
                dotnet run `
                    --project tools/Phase10.NfrProbe/Phase10.NfrProbe.csproj `
                    --no-build `
                    -- `
                    --servicebus-connection-string $serviceBusConnectionString `
                    --sql-connection-string $sqlConnectionString `
                    --sql-read-mode docker-compose `
                    --topic $topicName `
                    --tenant-id 1 `
                    --tenant-code TenantA `
                    --message-count $BurstMessageCount `
                    --timeout-seconds $PerformanceTimeoutSeconds `
                    --maximum-p95-seconds $MaximumP95Seconds `
                    --result-path $probeResultPath
            }
        }
    }
    $categories.performance.status = if ($performancePassed) { 'passed' } else { 'failed' }
}
Write-CategorySummaryFile -Category 'performance'
Write-NfrSummary

$previousTestConnection = $env:ORDERPROCESSING_TEST_CONNECTION_STRING
try {
    $env:ORDERPROCESSING_TEST_CONNECTION_STRING = $sqlConnectionString
    $tenantPassed = Invoke-CategoryCommand -Category 'tenant' -Name 'Tenant routing and isolation integration tests' -Command {
        dotnet test $testProject `
            --filter $tenantFilter `
            --logger "trx;LogFileName=$nfrRoot\tenant-tests.trx"
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
$categories.tenant.status = if ($tenantPassed) { 'passed' } else { 'failed' }
Write-CategorySummaryFile -Category 'tenant'
Write-NfrSummary

$paymentsPassed = $false
$previousTestConnection = $env:ORDERPROCESSING_TEST_CONNECTION_STRING
try {
    $env:ORDERPROCESSING_TEST_CONNECTION_STRING = $sqlConnectionString
    $paymentsPassed = Invoke-CategoryCommand -Category 'payments' -Name 'Payment provider integration tests' -Command {
        dotnet test $testProject `
            --filter $paymentFilter `
            --logger "trx;LogFileName=$nfrRoot\payments-tests.trx"
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

if ($paymentsPassed) {
    $paymentsPassed = Invoke-CategoryCommand -Category 'payments' -Name 'Dynamic provider payment matrix' -Command {
        npm --prefix (Join-Path $workspaceRoot 'automation') run run:docker:dev:http:playwright-matrix
    }
}
$categories.payments.status = if ($paymentsPassed) { 'passed' } else { 'failed' }
Write-CategorySummaryFile -Category 'payments'
Write-NfrSummary

if ($SkipOperationalChecks) {
    Write-Progress 'Skipping operational checks by request.'
    $categories.operational.status = 'skipped'
    $categories.operational.checks += [ordered]@{
        name = 'Operational checks'
        status = 'skipped'
        startedAtIst = (Get-IstNow).ToString('o')
            completedAtIst = (Get-IstNow).ToString('o')
            log = $null
        }
    $categories.recovery.status = 'skipped'
    $categories.recovery.checks += [ordered]@{
        name = 'Recovery checks'
        status = 'skipped'
        startedAtIst = (Get-IstNow).ToString('o')
        completedAtIst = (Get-IstNow).ToString('o')
        log = $null
    }
    Write-CategorySummaryFile -Category 'operational'
    Write-CategorySummaryFile -Category 'recovery'
}
else {
    $composeArgs = Get-Phase10ComposeArguments
    $operationalPassed = Invoke-CategoryCommand -Category 'operational' -Name 'Compose controls and running services' -Command {
        docker @composeArgs config --quiet
        if ($LASTEXITCODE -ne 0) { throw "docker compose config failed with exit code $LASTEXITCODE." }
        docker @composeArgs ps
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
    Write-CategorySummaryFile -Category 'operational'

    if ([string]::IsNullOrWhiteSpace($previousImageTag)) {
        $recoveryPassed = $false
        $categories.recovery.error =
            'PHASE10_PREVIOUS_IMAGE_TAG is required so rollback is executed rather than documented only.'
    }
    else {
        $recoveryPassed = Invoke-CategoryCommand -Category 'recovery' -Name 'Retained image digest evidence' -Command {
            docker image inspect $currentInventoryImage $previousInventoryImage `
                --format '{{.RepoTags}} {{.Id}} {{json .RepoDigests}}'
        }

        if ($recoveryPassed) {
            $originalTag = $env:PHASE10_IMAGE_TAG
            try {
                $env:PHASE10_IMAGE_TAG = $previousImageTag
                $rollbackPassed = Invoke-CategoryCommand -Category 'recovery' -Name 'Rollback inventory to previous image' -Command {
                    docker @composeArgs up -d --no-build inventory
                    if ($LASTEXITCODE -ne 0) { throw "Previous image startup failed with exit code $LASTEXITCODE." }
                    Wait-ForUrl -Url 'http://localhost:5082/health/ready'
                }
            }
            finally {
                $env:PHASE10_IMAGE_TAG = $currentImageTag
                $restorePassed = Invoke-CategoryCommand -Category 'recovery' -Name 'Restore inventory current image' -Command {
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
            $recoveryPassed = $rollbackPassed -and $restorePassed -and $recoveryPassed
        }
    }
    $categories.recovery.status = if ($recoveryPassed) { 'passed' } else { 'failed' }
    Write-CategorySummaryFile -Category 'recovery'
}

$securityPrerequisites = Test-Path -LiteralPath (Join-Path $workspaceRoot 'frontend\apps\web\scripts\phase10-identity-proof.mjs')
if (-not $securityPrerequisites) {
    $categories.security.status = 'failed'
    $categories.security.error = 'The local identity proof script is missing.'
}
else {
    $securityPassed = Invoke-Phase10IdentityChecks -Category 'security'
    if ($securityPassed) {
        $securityPassed = Invoke-ArtifactSecretScan -Category 'security'
    }
    $categories.security.status = if ($securityPassed) { 'passed' } else { 'failed' }
}
Write-CategorySummaryFile -Category 'security'

$allPassed = @($categories.Values | Where-Object { $_.status -eq 'failed' }).Count -eq 0
$summary.status = if ($allPassed) { 'passed' } else { 'failed' }
$summary.completedAtIst = (Get-IstNow).ToString('o')
Set-Content -LiteralPath $currentStepPath -Value 'completed' -Encoding utf8
Write-NfrSummary
    Write-Progress "$ProofName $($summary.status)."

if (-not $allPassed) {
    throw "$ProofName failed. Review $summaryPath and the category summaries."
}
