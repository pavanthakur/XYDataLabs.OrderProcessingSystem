#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('L1', 'L2', 'L3', 'L4', 'L5', 'L6')]
    [string]$Milestone,

    [switch]$DryRun,

    [ValidateRange(60, 3600)]
    [int]$CommandTimeoutSeconds = 900
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$frontendRoot = Join-Path $workspaceRoot 'frontend'
$artifactRoot = Join-Path $workspaceRoot 'TestResults\Phase10\local-preazure'
$composeFile = Join-Path $workspaceRoot 'compose\docker-compose.phase10.yml'
$envExampleFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local.example'
$envFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local'
$dockerConfigRoot = Join-Path $workspaceRoot '.tmp\docker-config'
$istZone = [TimeZoneInfo]::FindSystemTimeZoneById('India Standard Time')
$startedAt = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $istZone)

$milestones = @{
    L1 = @{
        Slug = 'real-services'
        Title = 'Real Services'
        Purpose = 'Prove independently buildable service hosts, Compose topology, routing ownership, and service readiness contracts.'
    }
    L2 = @{
        Slug = 'messaging'
        Title = 'Messaging'
        Purpose = 'Prove Service Bus topology, durable outbox/consumer behavior, idempotency, and tenant-aware effects.'
    }
    L3 = @{
        Slug = 'dlq-functions'
        Title = 'DLQ and Functions'
        Purpose = 'Prove separate DLQ intake/replay entities, manual settlement, approval controls, replay limits, and Functions startup.'
    }
    L4 = @{
        Slug = 'identity'
        Title = 'Identity'
        Purpose = 'Prove the local Keycloak OIDC path, tenant consistency, operator authorization, and webhook authentication boundary.'
    }
    L5 = @{
        Slug = 'nfr'
        Title = 'Operational Readiness Proof'
        Purpose = 'Produce separate functional, performance, tenant, payments, operational, recovery, and security evidence without hiding category failures.'
    }
    L6 = @{
        Slug = 'full-validation'
        Title = 'Pre-Azure Full Validation'
        Purpose = 'Run the complete local promotion gate and assemble evidence required before CI and Azure validation.'
    }
}

$definition = $milestones[$Milestone]
$runStamp = $startedAt.ToString('yyyyMMdd-HHmmssfff')
$runDir = Join-Path $artifactRoot "${runStamp}_${Milestone}-$($definition.Slug)"
$planPath = Join-Path $runDir 'run-plan.txt'
$progressPath = Join-Path $runDir 'progress.log'
$currentStepPath = Join-Path $runDir 'current-step.txt'
$summaryPath = Join-Path $runDir 'summary.json'
$latestPointerPath = Join-Path $artifactRoot "latest-$($Milestone.ToLowerInvariant())-$($definition.Slug).txt"
$failurePointerPath = Join-Path $artifactRoot "latest-failure-$($Milestone.ToLowerInvariant())-$($definition.Slug).txt"

New-Item -ItemType Directory -Path $runDir -Force | Out-Null
New-Item -ItemType Directory -Path $dockerConfigRoot -Force | Out-Null
Set-Content -LiteralPath $latestPointerPath -Value $runDir -Encoding utf8
Set-Content -LiteralPath $progressPath -Value '' -Encoding utf8
Set-Content -LiteralPath $currentStepPath -Value 'initializing' -Encoding utf8

$steps = [System.Collections.Generic.List[object]]::new()
$summary = [ordered]@{
    milestone = $Milestone
    title = $definition.Title
    status = 'running'
    dryRun = [bool]$DryRun
    startedAtIst = $startedAt.ToString('o')
    completedAtIst = $null
    reportDirectory = $runDir
    commitSha = $null
    steps = $steps
    error = $null
}

function Get-IstNow {
    [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $istZone)
}

function Get-LocalEnvValue {
    param([Parameter(Mandatory = $true)][string]$Name)

    $environmentValue = [Environment]::GetEnvironmentVariable($Name)
    if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
        return $environmentValue.Trim()
    }

    $line = Get-Content -LiteralPath $envFile |
        Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*=" } |
        Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($line)) {
        return $null
    }

    return (($line -split '=', 2)[1]).Trim().Trim('"').Trim("'")
}

function Assert-MessagingEnabled {
    if ($DryRun) {
        return
    }

    if ((Get-LocalEnvValue -Name 'LOCAL_SERVICEBUS_ENABLED') -ne 'true') {
        throw "LOCAL_SERVICEBUS_ENABLED=true is required for $Milestone in $envFile."
    }
}

function Write-Summary {
    $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding utf8
}

function Write-ProgressLog {
    param([Parameter(Mandatory = $true)][string]$Message)

    $line = '[{0}] [{1}] {2}' -f (Get-IstNow).ToString('o'), $Milestone, $Message
    Write-Host $line
    Add-Content -LiteralPath $progressPath -Value $line -Encoding utf8
}

function Invoke-BoundedStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$WorkingDirectory = $workspaceRoot,
        [int]$TimeoutSeconds = $CommandTimeoutSeconds
    )

    $started = Get-IstNow
    $logName = (($Name -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLowerInvariant()) + '.log'
    $logPath = Join-Path $runDir $logName
    Set-Content -LiteralPath $currentStepPath -Value $Name -Encoding utf8
    Write-ProgressLog "START $Name"

    if ($DryRun) {
        $display = @($Command) + $Arguments
        Set-Content -LiteralPath $logPath -Value ("DRY RUN: " + ($display -join ' ')) -Encoding utf8
        $steps.Add([ordered]@{
            name = $Name
            status = 'planned'
            startedAtIst = $started.ToString('o')
            completedAtIst = (Get-IstNow).ToString('o')
            log = $logName
        })
        Write-Summary
        Write-ProgressLog "PLANNED $Name"
        return
    }

    $stdoutPath = Join-Path $runDir "$logName.stdout.tmp"
    $stderrPath = Join-Path $runDir "$logName.stderr.tmp"
    $process = Start-Process `
        -FilePath $Command `
        -ArgumentList $Arguments `
        -WorkingDirectory $WorkingDirectory `
        -NoNewWindow `
        -PassThru `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    while (-not $process.HasExited) {
        if ([DateTimeOffset]::UtcNow -ge $deadline) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            throw "$Name timed out after $TimeoutSeconds seconds."
        }

        Write-ProgressLog "RUNNING $Name pid=$($process.Id)"
        Start-Sleep -Seconds 10
        $process.Refresh()
    }

    $output = @()
    if (Test-Path -LiteralPath $stdoutPath) {
        $output += Get-Content -LiteralPath $stdoutPath
    }
    if (Test-Path -LiteralPath $stderrPath) {
        $output += Get-Content -LiteralPath $stderrPath
    }
    $output | Set-Content -LiteralPath $logPath -Encoding utf8
    Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue

    if ($process.ExitCode -ne 0) {
        $steps.Add([ordered]@{
            name = $Name
            status = 'failed'
            startedAtIst = $started.ToString('o')
            completedAtIst = (Get-IstNow).ToString('o')
            exitCode = $process.ExitCode
            log = $logName
        })
        Write-Summary
        throw "$Name failed with exit code $($process.ExitCode). See $logPath"
    }

    $steps.Add([ordered]@{
        name = $Name
        status = 'passed'
        startedAtIst = $started.ToString('o')
        completedAtIst = (Get-IstNow).ToString('o')
        exitCode = 0
        log = $logName
    })
    Write-Summary
    Write-ProgressLog "PASS $Name"
}

function Add-ComposeConfigStep {
    Invoke-BoundedStep `
        -Name 'Docker Compose full profile config' `
        -Command 'docker' `
        -Arguments @(
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
            'config',
            '--quiet'
        )
}

function Test-LocalTcpPortOpen {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Port
    )

    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $connectTask = $client.ConnectAsync($HostName, $Port)
        return $connectTask.Wait([TimeSpan]::FromSeconds(3)) -and $client.Connected
    }
    catch {
        return $false
    }
    finally {
        $client.Dispose()
    }
}

function Test-Phase10ProtectedTopologyReady {
    return (Test-LocalTcpPortOpen -HostName 'localhost' -Port 8081) `
        -and (Test-LocalTcpPortOpen -HostName 'localhost' -Port 5022) `
        -and (Test-LocalTcpPortOpen -HostName 'localhost' -Port 5080)
}

function Test-Phase10MessagingTopologyReady {
    return (Test-LocalTcpPortOpen -HostName 'localhost' -Port 5672) `
        -and (Test-LocalTcpPortOpen -HostName 'localhost' -Port 5300)
}

function Test-Phase10FullTopologyReady {
    $servicesReady = (Test-LocalTcpPortOpen -HostName 'localhost' -Port 5081) `
        -and (Test-LocalTcpPortOpen -HostName 'localhost' -Port 5082) `
        -and (Test-LocalTcpPortOpen -HostName 'localhost' -Port 5083) `
        -and (Test-LocalTcpPortOpen -HostName 'localhost' -Port 5084)

    if (-not $servicesReady) {
        return $false
    }

    if ((Get-LocalEnvValue -Name 'LOCAL_SERVICEBUS_ENABLED') -eq 'true') {
        return (Test-Phase10ProtectedTopologyReady) -and (Test-Phase10MessagingTopologyReady)
    }

    return Test-Phase10ProtectedTopologyReady
}

function Test-Phase10FunctionsContainerReady {
    if ($DryRun) {
        return $true
    }

    $composeEnvArgs = @('--env-file', $envExampleFile, '--env-file', $envFile)
    $containerIdOutput = & docker compose @composeEnvArgs -f $composeFile --profile data --profile storage --profile messaging --profile functions ps -q functions 2>&1
    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    $containerId = ([string]::Join('', @($containerIdOutput))).Trim()
    return -not [string]::IsNullOrWhiteSpace($containerId)
}

function Test-Phase10DlqFunctionsTopologyReady {
    if (-not (Test-Phase10FullTopologyReady)) {
        return $false
    }

    if ((Get-LocalEnvValue -Name 'LOCAL_SERVICEBUS_ENABLED') -ne 'true') {
        return $false
    }

    return Test-Phase10FunctionsContainerReady
}

function Add-ReusedStackStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$Details
    )

    $started = Get-IstNow
    $logName = (($Name -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLowerInvariant()) + '.log'
    $logPath = Join-Path $runDir $logName
    Set-Content -LiteralPath $currentStepPath -Value $Name -Encoding utf8
    Write-ProgressLog "START $Name"
    Set-Content -LiteralPath $logPath -Value $Details -Encoding utf8
    $steps.Add([ordered]@{
        name = $Name
        status = 'passed'
        startedAtIst = $started.ToString('o')
        completedAtIst = (Get-IstNow).ToString('o')
        exitCode = 0
        log = $logName
        reusedExistingStack = $true
    })
    Write-Summary
    Write-ProgressLog "PASS $Name (reused existing stack)"
}

function Invoke-Phase10IdentityProof {
    Invoke-BoundedStep `
        -Name 'Identity and authorization tests' `
        -Command 'dotnet' `
        -Arguments @(
            'test',
            'tests/XYDataLabs.OrderProcessingSystem.API.Tests/XYDataLabs.OrderProcessingSystem.API.Tests.csproj',
            '--filter', 'FullyQualifiedName~Identity|FullyQualifiedName~Authorization|FullyQualifiedName~Tenant',
            '--logger', "trx;LogFileName=$runDir\identity-tests.trx"
        )

    if (-not $DryRun) {
        $env:KEYCLOAK_TENANT_ADMIN_PASSWORD =
            Get-LocalEnvValue -Name 'KEYCLOAK_TENANT_ADMIN_PASSWORD'
    }
    Invoke-BoundedStep `
        -Name 'Keycloak PKCE and authorization browser proof' `
        -Command 'npm' `
        -WorkingDirectory $frontendRoot `
        -Arguments @(
            'run',
            'proof:phase10:identity',
            '--workspace', '@xydatalabs/orderprocessing-web',
            '--',
            '--url', 'http://localhost:5022',
            '--orders-api-url', 'http://localhost:5081',
            '--payments-api-url', 'http://localhost:5084',
            '--approval-api-url', 'http://localhost:5081',
            '--output', "$runDir\identity-browser-evidence.json"
        ) `
        -TimeoutSeconds 300
}

function Invoke-Phase10ArchitectureConformance {
    Invoke-BoundedStep `
        -Name 'Architecture conformance' `
        -Command 'pwsh' `
        -Arguments @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', 'scripts/run-phase10-architecture-conformance.ps1',
            '-ArtifactRoot', 'TestResults/Phase10/local-preazure'
        ) `
        -TimeoutSeconds 1800
}

$planLines = @(
    "Phase 10 Pre-Azure $Milestone - $($definition.Title)",
    "Started (IST): $($startedAt.ToString('o'))",
    "Purpose: $($definition.Purpose)",
    'Policy: stop at the first failed required step; do not promote a failed milestone.',
    'Artifacts: progress.log, current-step.txt, summary.json, command logs, and latest pointers.',
    "Dry run: $([bool]$DryRun)"
)
Set-Content -LiteralPath $planPath -Value $planLines -Encoding utf8
Write-Summary
Write-ProgressLog "$Milestone initialized. reportDirectory=$runDir"

$previousDockerConfig = $env:DOCKER_CONFIG
$previousPhase10RunRoot = $env:PHASE10_RUN_ROOT
$env:DOCKER_CONFIG = $dockerConfigRoot
$env:PHASE10_RUN_ROOT = $runDir

Push-Location $workspaceRoot
try {
    if (-not (Test-Path -LiteralPath $envFile)) {
        throw "Required local configuration is missing: $envFile"
    }

    $summary.commitSha = (& git rev-parse HEAD).Trim()
    Write-Summary

    switch ($Milestone) {
        'L1' {
            Add-ComposeConfigStep
            foreach ($project in @(
                'XYDataLabs.OrderProcessingSystem.Orders.Host/XYDataLabs.OrderProcessingSystem.Orders.Host.csproj',
                'XYDataLabs.OrderProcessingSystem.Payments.Host/XYDataLabs.OrderProcessingSystem.Payments.Host.csproj',
                'XYDataLabs.OrderProcessingSystem.Inventory.Host/XYDataLabs.OrderProcessingSystem.Inventory.Host.csproj',
                'XYDataLabs.OrderProcessingSystem.Notifications.Host/XYDataLabs.OrderProcessingSystem.Notifications.Host.csproj',
                'XYDataLabs.OrderProcessingSystem.Gateway/XYDataLabs.OrderProcessingSystem.Gateway.csproj'
            )) {
                Invoke-BoundedStep -Name "Build $project" -Command 'dotnet' -Arguments @('build', $project, '--no-restore')
            }
            foreach ($service in @('orders', 'payments', 'inventory', 'notifications')) {
                Invoke-BoundedStep `
                    -Name "Build independent $service image" `
                    -Command 'docker' `
                    -Arguments @(
                        'compose',
                        '--env-file', $envExampleFile,
                        '--env-file', $envFile,
                        '-f', $composeFile,
                        '--profile', 'identity',
                        '--profile', 'apps',
                        'build', $service
                    ) `
                    -TimeoutSeconds 1800
            }
            Invoke-BoundedStep `
                -Name 'Start real service topology' `
                -Command 'pwsh' `
                -Arguments @(
                    '-NoProfile',
                    '-ExecutionPolicy', 'Bypass',
                    '-File', 'scripts/start-phase10-docker-dev.ps1',
                    '-Action', 'up',
                    '-Profile', 'apps'
                ) `
                -TimeoutSeconds 3600
        }
        'L2' {
            Assert-MessagingEnabled
            Add-ComposeConfigStep
            Invoke-BoundedStep `
                -Name 'Start complete local stack' `
                -Command 'pwsh' `
                -Arguments @(
                    '-NoProfile',
                    '-ExecutionPolicy', 'Bypass',
                    '-File', 'scripts/start-phase10-docker-dev.ps1',
                    '-Action', 'up',
                    '-Profile', 'apps'
                ) `
                -TimeoutSeconds 3600
            Invoke-BoundedStep `
                -Name 'Messaging integration tests' `
                -Command 'dotnet' `
                -Arguments @(
                    'test',
                    'tests/XYDataLabs.OrderProcessingSystem.Integration.Tests/XYDataLabs.OrderProcessingSystem.Integration.Tests.csproj',
                    '--filter', 'FullyQualifiedName~Outbox|FullyQualifiedName~Inbox|FullyQualifiedName~Event',
                    '--logger', "trx;LogFileName=$runDir\messaging-tests.trx"
                )
        }
        'L3' {
            Assert-MessagingEnabled
            if (-not $DryRun) {
                $env:LOCAL_SERVICEBUS_REPLAY_ENABLED = 'true'
            }
            Add-ComposeConfigStep
            if (Test-Phase10DlqFunctionsTopologyReady) {
                Add-ReusedStackStep `
                    -Name 'Start apps, broker, and Functions topology' `
                    -Details @(
                        'Existing full Phase 10 messaging + applications + Functions topology detected.',
                        'Reusing already running local Docker services because the required ports and Functions container are already live.',
                        'Ports checked: 8081, 5022, 5080, 5081, 5082, 5083, 5084, 5672, 5300.',
                        'Functions container check: docker compose ps -q functions returned a running container id.'
                    )
            }
            else {
                Invoke-BoundedStep `
                    -Name 'Start apps, broker, and Functions topology' `
                    -Command 'pwsh' `
                    -Arguments @(
                        '-NoProfile',
                        '-ExecutionPolicy', 'Bypass',
                        '-File', 'scripts/start-phase10-docker-dev.ps1',
                        '-Action', 'up',
                        '-Profile', 'apps'
                    ) `
                    -TimeoutSeconds 3600
            }
            Invoke-BoundedStep `
                -Name 'Functions build' `
                -Command 'dotnet' `
                -Arguments @(
                    'build',
                    'XYDataLabs.OrderProcessingSystem.Functions/XYDataLabs.OrderProcessingSystem.Functions.csproj',
                    '--no-restore'
                )
            Invoke-BoundedStep `
                -Name 'DLQ and replay tests' `
                -Command 'dotnet' `
                -Arguments @(
                    'test',
                    'tests/XYDataLabs.OrderProcessingSystem.Integration.Tests/XYDataLabs.OrderProcessingSystem.Integration.Tests.csproj',
                    '--filter', 'FullyQualifiedName~Dlq|FullyQualifiedName~Replay',
                    '--logger', "trx;LogFileName=$runDir\dlq-functions-tests.trx"
                )
            Invoke-BoundedStep `
                -Name 'Functions trigger discovery proof' `
                -Command 'pwsh' `
                -Arguments @(
                    '-NoProfile',
                    '-ExecutionPolicy', 'Bypass',
                    '-File', 'scripts/test-phase10-functions-discovery.ps1',
                    '-OutputPath', "$runDir\functions-discovery.log"
                )
        }
        'L4' {
            Add-ComposeConfigStep
            if (Test-Phase10ProtectedTopologyReady) {
                Add-ReusedStackStep `
                    -Name 'Start Keycloak and protected application topology' `
                    -Details @(
                    'Existing protected application topology detected.',
                    'Reusing already running local Docker services because the required ports are live.',
                    'Ports checked: 8081, 5022, 5080.'
                )
            }
            else {
                Invoke-BoundedStep `
                    -Name 'Start Keycloak and protected application topology' `
                    -Command 'pwsh' `
                    -Arguments @(
                        '-NoProfile',
                        '-ExecutionPolicy', 'Bypass',
                        '-File', 'scripts/start-phase10-docker-dev.ps1',
                        '-Action', 'up',
                    '-Profile', 'apps'
                ) `
                -TimeoutSeconds 3600
            }
            Invoke-Phase10IdentityProof
        }
        'L5' {
            Assert-MessagingEnabled
            if (Test-Phase10FullTopologyReady) {
                Add-ReusedStackStep `
                    -Name 'Start complete local stack' `
                    -Details @(
                    'Existing full Phase 10 topology detected.',
                    'Reusing already running local Docker services because the required ports are live.',
                    'Ports checked: 8081, 5022, 5080, 5081, 5082, 5083, 5084, 5300, 5672.'
                )
            }
            else {
                Invoke-BoundedStep `
                    -Name 'Start complete local stack' `
                    -Command 'pwsh' `
                    -Arguments @(
                        '-NoProfile',
                        '-ExecutionPolicy', 'Bypass',
                        '-File', 'scripts/start-phase10-docker-dev.ps1',
                        '-Action', 'up',
                        '-Profile', 'apps'
                    ) `
                    -TimeoutSeconds 3600
            }
            Invoke-BoundedStep `
                -Name 'Rollback readiness' `
                -Command 'pwsh' `
                -Arguments @(
                    '-NoProfile',
                    '-ExecutionPolicy', 'Bypass',
                    '-File', 'scripts/test-phase10-rollback-readiness.ps1',
                    '-ArtifactRoot', $runDir
                )
            Invoke-BoundedStep `
                -Name 'Phase 10 NFR proof' `
                -Command 'pwsh' `
                -Arguments @(
                    '-NoProfile',
                    '-ExecutionPolicy', 'Bypass',
                    '-File', 'scripts/run-phase10-local-nfr-proof.ps1',
                    '-ArtifactRoot', $runDir
                ) `
                -TimeoutSeconds 1800
        }
        'L6' {
            Assert-MessagingEnabled
            Invoke-BoundedStep `
                -Name 'Environment readiness' `
                -Command 'pwsh' `
                -Arguments @(
                    '-NoProfile',
                    '-ExecutionPolicy', 'Bypass',
                    '-File', 'scripts/test-phase10-tool-readiness.ps1'
                )
            Invoke-BoundedStep `
                -Name 'Repository validation' `
                -Command 'pwsh' `
                -Arguments @(
                    '-NoProfile',
                    '-ExecutionPolicy', 'Bypass',
                    '-File', 'scripts/run-phase10-repository-validation.ps1'
                ) `
                -TimeoutSeconds 1800
            Add-ComposeConfigStep
            Invoke-Phase10ArchitectureConformance
            if (Test-Phase10FullTopologyReady) {
                Add-ReusedStackStep `
                    -Name 'Start complete local stack' `
                    -Details @(
                    'Existing full Phase 10 topology detected.',
                    'Reusing already running local Docker services because the required ports are live.',
                    'Ports checked: 8081, 5022, 5080, 5081, 5082, 5083, 5084, 5300, 5672.'
                )
            }
            else {
                Invoke-BoundedStep `
                    -Name 'Start complete local stack' `
                    -Command 'pwsh' `
                    -Arguments @(
                        '-NoProfile',
                        '-ExecutionPolicy', 'Bypass',
                        '-File', 'scripts/start-phase10-docker-dev.ps1',
                        '-Action', 'up',
                        '-Profile', 'apps'
                    ) `
                    -TimeoutSeconds 3600
            }
            Invoke-Phase10IdentityProof
            Invoke-BoundedStep `
                -Name 'Rollback readiness' `
                -Command 'pwsh' `
                -Arguments @(
                    '-NoProfile',
                    '-ExecutionPolicy', 'Bypass',
                    '-File', 'scripts/test-phase10-rollback-readiness.ps1',
                    '-ArtifactRoot', $runDir
                )
            Invoke-BoundedStep `
                -Name 'Docker Compose end-to-end' `
                -Command 'pwsh' `
                -Arguments @(
                    '-NoProfile',
                    '-ExecutionPolicy', 'Bypass',
                    '-File', 'scripts/run-phase10-local-container-stack-end-to-end.ps1'
                ) `
                -TimeoutSeconds 3600
            Invoke-BoundedStep `
                -Name 'Phase 10 NFR proof' `
                -Command 'pwsh' `
                -Arguments @(
                    '-NoProfile',
                    '-ExecutionPolicy', 'Bypass',
                    '-File', 'scripts/run-phase10-local-nfr-proof.ps1',
                    '-ArtifactRoot', $runDir
                ) `
                -TimeoutSeconds 1800
            Invoke-BoundedStep `
                -Name 'Stop local stack (preserve volumes)' `
                -Command 'pwsh' `
                -Arguments @(
                    '-NoProfile',
                    '-ExecutionPolicy', 'Bypass',
                    '-File', 'scripts/cleanup-phase10-preazure-local.ps1'
                )
        }
    }

    $summary.status = if ($DryRun) { 'planned' } else { 'passed' }
    $summary.completedAtIst = (Get-IstNow).ToString('o')
    Set-Content -LiteralPath $currentStepPath -Value 'completed' -Encoding utf8
    Write-Summary
    Remove-Item -LiteralPath $failurePointerPath -Force -ErrorAction SilentlyContinue
    Write-ProgressLog "$Milestone $($summary.status)."
}
catch {
    $summary.status = 'failed'
    $summary.completedAtIst = (Get-IstNow).ToString('o')
    $summary.error = $_.Exception.Message
    Set-Content -LiteralPath $currentStepPath -Value 'failed' -Encoding utf8
    Set-Content -LiteralPath $failurePointerPath -Value $runDir -Encoding utf8
    Write-Summary
    Write-ProgressLog "$Milestone FAILED: $($_.Exception.Message)"
    throw
}
finally {
    if ([string]::IsNullOrWhiteSpace($previousPhase10RunRoot)) {
        Remove-Item Env:PHASE10_RUN_ROOT -ErrorAction SilentlyContinue
    }
    else {
        $env:PHASE10_RUN_ROOT = $previousPhase10RunRoot
    }

    if ([string]::IsNullOrWhiteSpace($previousDockerConfig)) {
        Remove-Item Env:DOCKER_CONFIG -ErrorAction SilentlyContinue
    }
    else {
        $env:DOCKER_CONFIG = $previousDockerConfig
    }

    Pop-Location
}
