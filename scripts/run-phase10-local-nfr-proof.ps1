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

    [switch]$SkipOperationalChecks,

    [switch]$OperationalOnly,

    [switch]$SkipDynamicPaymentMatrix,

    [string[]]$SelectedCategories = @()
)

$ErrorActionPreference = 'Stop'
if ($OperationalOnly -and $UseCleanReset) {
    throw '-OperationalOnly cannot be combined with -UseCleanReset; this lane never resets the Service Bus emulator.'
}
if ($OperationalOnly -and $SkipOperationalChecks) {
    throw '-OperationalOnly cannot be combined with -SkipOperationalChecks.'
}
$script:Phase10NfrRestorationFailed = $false
. (Join-Path $PSScriptRoot 'phase10-docker-safety.ps1')
. (Join-Path $PSScriptRoot 'phase10-nfr-aggregate.ps1')
. (Join-Path $PSScriptRoot 'phase10-nfr-drill-contract.ps1')
. (Join-Path $PSScriptRoot 'phase10-nfr-selection.ps1')
$categorySelection = Resolve-Phase10NfrSelection -Categories $SelectedCategories -OperationalOnly:$OperationalOnly -SkipDynamicPaymentMatrix:$SkipDynamicPaymentMatrix
$targetedNoChargeRun = $categorySelection.mode -eq 'targeted-no-charge'
$skipOperationalExecution = $SkipOperationalChecks -or $targetedNoChargeRun
$fullNoChargeRun = $categorySelection.mode -eq 'full' -and $SkipDynamicPaymentMatrix
if ($fullNoChargeRun -and ($UseCleanReset -or $SkipOperationalChecks)) {
    throw 'Full no-charge NFR preserves storage and requires operational and recovery checks.'
}
function Test-Phase10NfrCategorySelected {
    param([Parameter(Mandatory = $true)][string]$Name)
    return $categorySelection.selectedCategories -contains $Name
}
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
if (Test-Path -LiteralPath $summaryPath -PathType Leaf) {
    throw "Refusing to overwrite existing NFR evidence: $summaryPath"
}
Set-Content -LiteralPath $progressPath -Value '' -Encoding utf8
Set-Content -LiteralPath $currentStepPath -Value 'initializing' -Encoding utf8
Set-Content -LiteralPath (Join-Path $nfrRoot 'run-plan.txt') -Encoding utf8 -Value @(
    $ProofName,
    "Started (IST): $($startedAt.ToString('o'))",
    'Functional: focused durability, DLQ, and replay integration tests.',
    "Performance: 1-message canary, then $BurstMessageCount OrderCreatedV1 messages; consumer P95 <= $MaximumP95Seconds seconds.",
    "Clean reset: $(if ($OperationalOnly) { 'prohibited in the operational-only lane' } elseif ($UseCleanReset) { 'enabled' } else { 'available via -UseCleanReset' }).",
    "Operational checks: $(if ($targetedNoChargeRun) { 'not selected in targeted no-charge mode' } elseif ($SkipOperationalChecks) { 'skipped via -SkipOperationalChecks' } else { 'enabled' }).",
    'Tenant: dedicated/shared routing and tenant registry behavior are reported independently.',
    "Payments: provider seed/reconciliation checks; dynamic provider matrix $(if ($SkipDynamicPaymentMatrix) { 'explicitly skipped' } else { 'enabled' }).",
    'Security: local Keycloak-backed API auth tests, browser PKCE/operator authorization proof, and artifact secret scan.',
    'Operational: Compose controls and restart diagnostics are reported independently from recovery.',
    'Recovery: retained image evidence and executed previous-image rollback/restore are reported independently.',
    "Selection: $($categorySelection.mode); selected=$($categorySelection.selectedCategories -join ','); dynamic payment matrix=$($categorySelection.dynamicPaymentMatrix).",
    'Policy: categories are reported independently; the aggregate is passed only when every category passed. Failed/not-run/blocked => incomplete (nonzero exit).'
)

$categories = [ordered]@{
    functional = [ordered]@{ status = 'not-run'; execution = 'not-selected'; checks = @(); error = 'Not selected.' }
    performance = [ordered]@{ status = 'not-run'; execution = 'not-selected'; checks = @(); error = 'Not selected.' }
    tenant = [ordered]@{ status = 'not-run'; execution = 'not-selected'; checks = @(); error = 'Not selected.' }
    payments = [ordered]@{ status = 'not-run'; execution = 'not-selected'; integrationStatus = 'not-run'; dynamicMatrixStatus = 'not-run'; checks = @(); error = 'Not selected.' }
    operational = [ordered]@{ status = 'not-run'; execution = 'not-selected'; checks = @(); error = 'Not selected.' }
    recovery = [ordered]@{ status = 'not-run'; execution = 'not-selected'; checks = @(); error = 'Not selected.' }
    security = [ordered]@{ status = 'not-run'; execution = 'not-selected'; checks = @(); error = 'Not selected.' }
}
foreach ($categoryName in $categorySelection.selectedCategories) {
    $categories[$categoryName]['status'] = 'running'
    $categories[$categoryName]['execution'] = 'selected'
    $categories[$categoryName]['error'] = $null
}
$summary = [ordered]@{
    status = 'running'
    startedAtIst = $startedAt.ToString('o')
    completedAtIst = $null
    artifactRoot = $nfrRoot
    commitSha = (& git -C $workspaceRoot rev-parse HEAD).Trim()
    worktreeAtStart = $(if ([string]::IsNullOrWhiteSpace((& git -C $workspaceRoot status --porcelain) -join '')) { 'clean' } else { 'dirty' })
    selection = [ordered]@{
        mode = $categorySelection.mode
        requestedCategories = @($categorySelection.requestedCategories)
        selectedCategories = @($categorySelection.selectedCategories)
        notSelectedCategories = @($categorySelection.notSelectedCategories)
        dynamicPaymentMatrix = $categorySelection.dynamicPaymentMatrix
        carriedForwardEvidence = @()
    }
    paymentSettingsIntegrity = 'not-selected'
    paymentSettingsEvidence = @()
    commitShaAtFinish = $null
    worktreeAtFinish = $null
    categories = $categories
}

function Get-IstNow {
    [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $istZone)
}

function Write-NfrSummary {
    $summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath -Encoding utf8
}

function Write-CategorySummaryFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category
    )

    Set-Content -LiteralPath (Join-Path $nfrRoot "$Category-summary.json") `
        -Value ($categories[$Category] | ConvertTo-Json -Depth 8) -Encoding utf8
}

if ($targetedNoChargeRun) {
    foreach ($categoryName in @('operational', 'recovery')) {
        $categories[$categoryName]['status'] = 'not-run'
        $categories[$categoryName]['execution'] = 'not-selected'
        $categories[$categoryName]['error'] = 'Not run because targeted no-charge category selection excludes Docker operational mutations and rollback.'
        Write-CategorySummaryFile -Category $categoryName
    }
    Write-NfrSummary
}
elseif ($SkipOperationalChecks) {
    foreach ($categoryName in @('operational', 'recovery')) {
        $categories[$categoryName]['status'] = 'skipped'
        $categories[$categoryName]['execution'] = 'skipped-by-option'
        $categories[$categoryName]['error'] = 'Skipped by -SkipOperationalChecks.'
    }
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

function Get-Phase10NfrPaymentSettingsSnapshot {
    param([Parameter(Mandatory = $true)][hashtable]$Settings)

    $sharedDatabase = 'OrderProcessingSystem_Dev'
    $sharedConnectionString = New-Phase10HostSqlConnectionString -Database $sharedDatabase -Password $Settings.LOCAL_SQL_PASSWORD -Settings $Settings
    Assert-Phase10HostSqlIdentity -ConnectionString $sharedConnectionString
    $sharedConnection = [System.Data.SqlClient.SqlConnection]::new($sharedConnectionString)
    try {
        $sharedConnection.Open()
        $identityCommand = $sharedConnection.CreateCommand()
        $identityCommand.CommandText = "SELECT CONVERT(nvarchar(128),SERVERPROPERTY('MachineName')) AS Machine"
        $sqlMachine = [string]$identityCommand.ExecuteScalar()
        $registryCommand = $sharedConnection.CreateCommand()
        $registryCommand.CommandText = "SELECT Id,Code,TenantTier,Status,PaymentProviderCode FROM dbo.Tenants WHERE Status='Active' ORDER BY Code"
        $registryReader = $registryCommand.ExecuteReader()
        $tenants = @()
        while ($registryReader.Read()) {
            $tenants += [ordered]@{
                id = $registryReader.GetInt32(0)
                code = $registryReader.GetString(1)
                tier = $registryReader.GetString(2)
                status = $registryReader.GetString(3)
                registryRoute = $registryReader.GetString(4)
            }
        }
        $registryReader.Dispose()
    }
    finally { $sharedConnection.Dispose() }

    if ($tenants.Count -eq 0) { throw 'Payment configuration snapshot found no active tenants.' }
    $databaseMap = Get-Phase10ComposeDedicatedTenantDatabaseMap
    foreach ($tenant in $tenants) {
        $businessDatabase = Resolve-Phase10LocalTenantDatabaseFromRegistry -TenantCode $tenant.code -TenantTier $tenant.tier -Status $tenant.status -DedicatedDatabaseMap $databaseMap
        $connectionString = New-Phase10HostSqlConnectionString -Database $businessDatabase -Password $Settings.LOCAL_SQL_PASSWORD -Settings $Settings
        Assert-Phase10HostSqlIdentity -ConnectionString $connectionString
        $connection = [System.Data.SqlClient.SqlConnection]::new($connectionString)
        try {
            $connection.Open()
            $mirrorCommand = $connection.CreateCommand()
            $mirrorCommand.CommandText = 'SELECT Id,PaymentProviderCode FROM dbo.Tenants WHERE Code=@code'
            [void]$mirrorCommand.Parameters.AddWithValue('@code', $tenant.code)
            $mirrorReader = $mirrorCommand.ExecuteReader()
            if (-not $mirrorReader.Read() -or $mirrorReader.GetInt32(0) -ne $tenant.id) { throw "Business tenant identity mismatch for '$($tenant.code)'." }
            $tenant.businessRoute = $mirrorReader.GetString(1)
            $mirrorReader.Dispose()

            $providersCommand = $connection.CreateCommand()
            $providersCommand.CommandText = 'SELECT Id,ProviderType,Use3DSecure,IsProduction FROM payments.PaymentProviders WHERE TenantId=@tenant ORDER BY ProviderType,Id'
            [void]$providersCommand.Parameters.AddWithValue('@tenant', $tenant.id)
            $providersReader = $providersCommand.ExecuteReader()
            $providers = @()
            while ($providersReader.Read()) {
                $providers += [ordered]@{
                    id = $providersReader.GetInt32(0)
                    provider = $providersReader.GetString(1)
                    threeDs = $providersReader.GetBoolean(2)
                    production = $providersReader.GetBoolean(3)
                }
            }
            $providersReader.Dispose()
            $tenant.businessDatabase = $businessDatabase
            $tenant.providers = $providers
        }
        finally { $connection.Dispose() }
    }

    return [ordered]@{ schema = 'phase10-payment-settings-snapshot-v1'; sqlMachine = $sqlMachine; tenants = $tenants }
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

function Invoke-IsolatedNfrIntegrationFilterSet {
    param(
        [Parameter(Mandatory = $true)][string]$FilterExpression,
        [Parameter(Mandatory = $true)][string]$ResultsDirectory
    )

    $filters = @($FilterExpression -split '\|' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($filters.Count -eq 0) { throw 'NFR integration filter set is empty.' }

    $runner = Join-Path $workspaceRoot 'scripts/invoke-integration-tests-isolated.ps1'
    for ($index = 0; $index -lt $filters.Count; $index++) {
        $filterResults = Join-Path $ResultsDirectory ('filter-{0:D2}' -f ($index + 1))
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $runner `
            -Runtime docker-phase10 -TestFilter ([string]$filters[$index]) -ResultsDirectory $filterResults
        if ($LASTEXITCODE -ne 0) {
            throw "Isolated NFR integration filter $($index + 1) failed with exit code $LASTEXITCODE."
        }
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

function Get-Phase10RollbackPreflight {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentImage,
        [Parameter(Mandatory = $true)][string]$PreviousImage,
        [Parameter(Mandatory = $true)][string]$EvidencePath
    )

    $manifestPath = Join-Path $workspaceRoot 'TestResults/Phase10/rollback-baseline/290d0fba/provenance.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'Rollback provenance manifest is missing; previous-image rollback is blocked.'
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.schema -ne 'phase10-rollback-baseline-v1' -or
        $manifest.previousImage -cne $PreviousImage -or
        [string]$manifest.sourceCommit -notmatch '^[0-9a-f]{40}$' -or
        [string]$manifest.previousImageId -notmatch '^sha256:[0-9a-f]{64}$') {
        throw 'Rollback provenance does not identify the selected image with a valid source revision and immutable ID.'
    }
    & git -C $workspaceRoot cat-file -e "$($manifest.sourceCommit)^{commit}"
    if ($LASTEXITCODE -ne 0) { throw 'Rollback source commit is not available in this checkout.' }

    $changedFiles = @(& git -C $workspaceRoot diff --name-only "$($manifest.sourceCommit)..HEAD")
    if ($LASTEXITCODE -ne 0) { throw 'Cannot compare the rollback source revision with the reviewed candidate.' }
    $changedFiles += @(& git -C $workspaceRoot diff --name-only HEAD)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect uncommitted changes before rollback.' }
    $changedFiles += @(& git -C $workspaceRoot ls-files --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect untracked files before rollback.' }
    $relevantPattern = '(?i)(^|/)(XYDataLabs\.OrderProcessingSystem\.(Inventory\.|SharedKernel/|ServiceDefaults/|Eventing\.Abstractions/)|Resources/Database/|.*Migrations?/|.*\.sql$|Directory\.(Build|Packages)\.props)'
    $incompatibleChanges = @($changedFiles | Sort-Object -Unique | Where-Object { $_ -match $relevantPattern })
    if ($incompatibleChanges.Count -gt 0) {
        throw 'Application persistence/Inventory contracts changed after the rollback baseline; schema compatibility needs review before rollback.'
    }

    $previousId = ([string](& docker image inspect $PreviousImage --format '{{.Id}}')).Trim()
    if ($LASTEXITCODE -ne 0 -or $previousId -cne [string]$manifest.previousImageId) {
        throw 'Retained rollback image ID does not match its provenance manifest.'
    }
    $currentId = ([string](& docker image inspect $CurrentImage --format '{{.Id}}')).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $currentId.StartsWith('sha256:', [StringComparison]::Ordinal)) {
        throw 'Current Inventory image identity could not be established.'
    }
    $containerName = Resolve-ComposeServiceContainerName -ServiceName 'inventory'
    $runningId = ([string](& docker inspect --format '{{.Image}}' $containerName)).Trim()
    if ($LASTEXITCODE -ne 0 -or $runningId -cne $currentId) {
        throw 'Running Inventory image differs from the selected current image tag; rollback/restore is blocked.'
    }

    $evidence = [ordered]@{
        status = 'preflight-passed'
        sourceCommit = [string]$manifest.sourceCommit
        previousImage = $PreviousImage
        previousImageId = $previousId
        currentImage = $CurrentImage
        currentImageId = $currentId
        runningImageIdBefore = $runningId
        relevantSourceChangesSinceBaseline = $incompatibleChanges
        comparedCandidateCommit = (& git -C $workspaceRoot rev-parse HEAD).Trim()
        databaseRollback = $false
        rollbackObserved = $false
        currentImageRestored = $false
    }
    $evidence | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $EvidencePath -Encoding utf8
    return [pscustomobject]$evidence
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

function Invoke-ConsumerOutageBacklogDrill {
    param(
        [Parameter(Mandatory = $true)][string]$TopicName,
        [Parameter(Mandatory = $true)][string]$SqlConnectionString,
        [Parameter(Mandatory = $true)][string]$ServiceBusConnectionString,
        [ValidateRange(5, 100)][int]$MessageCount = 25,
        [int]$RecoveryLimitSeconds = 1800,
        [ValidateRange(1, 120)][double]$MaximumP95Seconds = 30
    )

    $composeArgs = Get-Phase10ComposeArguments
    $consumers = @('inventory', 'notifications')
    $runId = "phase10-drill-$([guid]::NewGuid().ToString('N'))"
    $probeResultPath = Join-Path $nfrRoot 'consumer-outage-drill-probe.json'
    $probeOutPath = Join-Path $nfrRoot 'consumer-outage-drill-probe.out.log'
    $probeErrPath = Join-Path $nfrRoot 'consumer-outage-drill-probe.err.log'
    $drillPath = Join-Path $nfrRoot 'consumer-outage-drill.json'
    $drill = [ordered]@{
        drill = 'consumer-outage-backlog-recovery'
        runId = $runId
        messageCount = $MessageCount
        recoveryLimitSeconds = $RecoveryLimitSeconds
        status = 'failed'
        note = 'Consumers are stopped, the burst is published into the broker backlog, consumers are started, and the backlog must drain to exactly one effect per message.'
    }
    $previousSql = $env:PHASE10_NFR_SQL_CONNECTION_STRING
    $previousBus = $env:PHASE10_NFR_SERVICEBUS_CONNECTION_STRING
    $probe = $null
    $executionPassed = $false
    $primaryFailure = $null
    $probeStopped = $true
    $consumerStartExitCode = -1
    $consumersReady = $false
    $environmentRestored = $false
    $restorationFailures = [System.Collections.Generic.List[string]]::new()
    try {
        & docker @composeArgs stop @consumers
        if ($LASTEXITCODE -ne 0) { throw "Stopping consumers failed with exit code $LASTEXITCODE." }
        $drill.outageStartedUtc = [DateTimeOffset]::UtcNow.ToString('o')

        $env:PHASE10_NFR_SQL_CONNECTION_STRING = $SqlConnectionString
        $env:PHASE10_NFR_SERVICEBUS_CONNECTION_STRING = $ServiceBusConnectionString
        $probe = Start-Process -FilePath 'dotnet' -PassThru -WorkingDirectory $workspaceRoot `
            -RedirectStandardOutput $probeOutPath -RedirectStandardError $probeErrPath -ArgumentList @(
                'run', '--project', 'tools/Phase10.NfrProbe/Phase10.NfrProbe.csproj', '--no-build', '--',
                '--sql-read-mode', 'docker-compose', '--topic', $TopicName, '--tenant-code', 'TenantA',
                '--message-count', "$MessageCount", '--timeout-seconds', "$RecoveryLimitSeconds",
                '--settle-seconds', '20', '--maximum-p95-seconds', "$MaximumP95Seconds",
                '--run-id', $runId, '--result-path', $probeResultPath)
        $null = $probe.Handle

        $publishDeadline = [DateTimeOffset]::UtcNow.AddSeconds(180)
        while ($true) {
            $published = (Test-Path -LiteralPath $probeOutPath) -and
                (Select-String -LiteralPath $probeOutPath -Pattern 'Published \d+ OrderCreatedV1' -Quiet)
            if ($published) { break }
            if ($probe.HasExited) { throw "Probe exited before publishing the backlog (exit $($probe.ExitCode))." }
            if ([DateTimeOffset]::UtcNow -gt $publishDeadline) { throw 'Timed out waiting for the backlog to be published.' }
            Start-Sleep -Seconds 2
        }

        $restartAt = [DateTimeOffset]::UtcNow
        $drill.consumersStartedUtc = $restartAt.ToString('o')
        & docker @composeArgs start @consumers
        if ($LASTEXITCODE -ne 0) { throw "Starting consumers failed with exit code $LASTEXITCODE." }
        Wait-ForUrl -Url 'http://localhost:5082/health/ready' -TimeoutSeconds 600
        Wait-ForUrl -Url 'http://localhost:5083/health/ready' -TimeoutSeconds 600
        $drill.consumersReadySeconds = [math]::Round(([DateTimeOffset]::UtcNow - $restartAt).TotalSeconds, 3)

        if (-not $probe.WaitForExit($RecoveryLimitSeconds * 1000)) {
            throw "Backlog did not drain within $RecoveryLimitSeconds seconds."
        }
        $probe.WaitForExit()
        $drill.backlogRecoverySeconds = [math]::Round(([DateTimeOffset]::UtcNow - $restartAt).TotalSeconds, 3)
        if ($probe.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $probeResultPath)) {
            throw "Probe reported failure (exit $($probe.ExitCode)); see $probeResultPath."
        }

        $probeResult = Get-Content -LiteralPath $probeResultPath -Raw | ConvertFrom-Json
        $drill.inventoryEffects = $probeResult.InventoryEffectCount
        $drill.notificationEffects = $probeResult.NotificationEffectCount
        $drill.inventoryInbox = $probeResult.InventoryInboxCount
        $drill.notificationsInbox = $probeResult.NotificationsInboxCount
        $drill.p95Seconds = $probeResult.P95Seconds
        $drill.lostMessages = [math]::Max(0, $MessageCount - [math]::Min($probeResult.InventoryEffectCount, $probeResult.NotificationEffectCount))
        $drill.duplicateEffects = [math]::Max(0, $probeResult.InventoryEffectCount - $MessageCount) +
            [math]::Max(0, $probeResult.NotificationEffectCount - $MessageCount)
        if ($drill.lostMessages -ne 0 -or $drill.duplicateEffects -ne 0) {
            throw "Loss or duplicate effects detected: lost=$($drill.lostMessages) duplicates=$($drill.duplicateEffects)."
        }
        if ($probeResult.InventoryInboxCount -ne $MessageCount -or $probeResult.NotificationsInboxCount -ne $MessageCount) {
            throw 'Consumer inbox counts do not reconcile to the outage drill message count.'
        }
        if ($probeResult.P95Seconds -ge $MaximumP95Seconds) {
            throw "Outage-drill consumer P95 $($probeResult.P95Seconds)s is not below $MaximumP95Seconds seconds."
        }
        if ($drill.backlogRecoverySeconds -gt $RecoveryLimitSeconds) {
            throw "Recovery took $($drill.backlogRecoverySeconds)s, above the $RecoveryLimitSeconds s limit."
        }
        $executionPassed = $true
    }
    catch {
        $primaryFailure = $_.Exception
        $drill.errorType = $_.Exception.GetType().FullName
    }
    finally {
        if ($null -ne $probe) {
            try {
                $probe.Refresh()
                if (-not $probe.HasExited) { $probe.Kill($true) }
                if (-not $probe.WaitForExit(10000)) { throw 'Probe process tree did not exit within 10 seconds.' }
                $probeStopped = $true
            }
            catch {
                $probeStopped = $false
                $restorationFailures.Add('probe-stop')
            }
        }

        try {
            & docker @composeArgs start @consumers
            $consumerStartExitCode = $LASTEXITCODE
            if ($consumerStartExitCode -ne 0) {
                $restorationFailures.Add('consumer-start')
            }
            else {
                try {
                    Wait-ForUrl -Url 'http://localhost:5082/health/ready' -TimeoutSeconds 600
                    Wait-ForUrl -Url 'http://localhost:5083/health/ready' -TimeoutSeconds 600
                    $consumersReady = $true
                }
                catch {
                    $restorationFailures.Add('consumer-readiness')
                }
            }
        }
        catch {
            $consumerStartExitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { -1 }
            $restorationFailures.Add('consumer-start')
        }

        $sqlRestored = $false
        $busRestored = $false
        try {
            if ($null -eq $previousSql) { Remove-Item Env:PHASE10_NFR_SQL_CONNECTION_STRING -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable('PHASE10_NFR_SQL_CONNECTION_STRING', $previousSql, 'Process') }
            $currentSql = [Environment]::GetEnvironmentVariable('PHASE10_NFR_SQL_CONNECTION_STRING', 'Process')
            $sqlRestored = if ($null -eq $previousSql) { [string]::IsNullOrEmpty($currentSql) } else { $currentSql -ceq $previousSql }
        }
        catch { $restorationFailures.Add('sql-environment-restore') }
        try {
            if ($null -eq $previousBus) { Remove-Item Env:PHASE10_NFR_SERVICEBUS_CONNECTION_STRING -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable('PHASE10_NFR_SERVICEBUS_CONNECTION_STRING', $previousBus, 'Process') }
            $currentBus = [Environment]::GetEnvironmentVariable('PHASE10_NFR_SERVICEBUS_CONNECTION_STRING', 'Process')
            $busRestored = if ($null -eq $previousBus) { [string]::IsNullOrEmpty($currentBus) } else { $currentBus -ceq $previousBus }
        }
        catch { $restorationFailures.Add('servicebus-environment-restore') }
        $environmentRestored = $sqlRestored -and $busRestored
        if (-not $environmentRestored -and $restorationFailures.Count -eq 0) { $restorationFailures.Add('environment-restoration') }

        $finalStatus = Complete-Phase10NfrDrillResult -Drill $drill `
            -ExecutionPassed ($executionPassed -and $null -eq $primaryFailure) `
            -ProbeStopped $probeStopped `
            -ConsumersStartExitCode $consumerStartExitCode `
            -ConsumersReady $consumersReady `
            -EnvironmentRestored $environmentRestored `
            -ExecutionFailureType $(if ($null -ne $primaryFailure) { $primaryFailure.GetType().FullName } elseif (-not $executionPassed) { 'UnknownExecutionFailure' } else { $null }) `
            -RestorationFailures $restorationFailures.ToArray()
        if (-not (Test-Phase10NfrMutationsAllowed -Drill $drill)) { $script:Phase10NfrRestorationFailed = $true }
        try {
            $drill | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $drillPath -Encoding utf8
        }
        catch {
            $global:LASTEXITCODE = 1
            throw "Failed to persist the consumer outage drill evidence at $drillPath."
        }
    }

    Get-Content -LiteralPath $drillPath -Raw | Write-Host
    if ($finalStatus -ne 'passed') {
        $global:LASTEXITCODE = 1
        $failureTags = @($drill.restorationFailures) -join ', '
        throw "Consumer outage/backlog drill failed. Execution=$(-not $executionPassed); restoration findings=[$failureTags]. See $drillPath and the probe logs."
    }
    $global:LASTEXITCODE = 0
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
$sqlConnectionString = New-Phase10HostSqlConnectionString -Database 'OrderProcessingSystem_Dev' -Password $sqlPassword
Assert-Phase10HostSqlIdentity -ConnectionString $sqlConnectionString
$paymentSettingsBefore = $null
if ($OperationalOnly -or $fullNoChargeRun) {
    Assert-Phase10ComposeProject
    Assert-Phase10LocalDockerEndpoint
    $activeLocks = @(
        (Join-Path $workspaceRoot 'TestResults/phase10-docker-acceptance.lock'),
        (Join-Path $workspaceRoot 'TestResults/local-payment-test-state.lock'),
        (Get-ChildItem -LiteralPath (Join-Path $workspaceRoot 'TestResults') -Filter 'integration-active-*.lock' -File -ErrorAction SilentlyContinue | ForEach-Object FullName)
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }
    if ($activeLocks.Count -gt 0) { throw 'Active Docker acceptance, payment-fixture or integration lock exists; operational mutations are blocked.' }
    $runningContainerIds = @(& docker ps -q)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect running Docker workloads; operational mutations are blocked.' }
    foreach ($containerId in $runningContainerIds) {
        $project = ([string](& docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' $containerId)).Trim()
        if ($LASTEXITCODE -ne 0 -or $project -cne 'xy-phase10') {
            throw 'A running container is not owned by xy-phase10; operational mutations are blocked.'
        }
    }
}
if ($SkipDynamicPaymentMatrix -and (Test-Phase10NfrCategorySelected -Name 'payments')) {
    $paymentSettingsBefore = Get-Phase10NfrPaymentSettingsSnapshot -Settings $envValues
    $beforePath = Join-Path $nfrRoot 'payment-settings-before.json'
    if (Test-Path -LiteralPath $beforePath) { throw 'Payment settings evidence already exists; use a fresh NFR run directory.' }
    $paymentSettingsBefore | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $beforePath -Encoding utf8
    $summary.paymentSettingsIntegrity = 'awaiting-post-run-verification'
    $summary.paymentSettingsEvidence += [ordered]@{ file = 'payment-settings-before.json'; sha256 = (Get-FileHash -LiteralPath $beforePath -Algorithm SHA256).Hash.ToLowerInvariant() }
}
$testProject = 'tests/XYDataLabs.OrderProcessingSystem.Integration.Tests/XYDataLabs.OrderProcessingSystem.Integration.Tests.csproj'
$functionalFilter = 'FullyQualifiedName~Outbox|FullyQualifiedName~Inbox|FullyQualifiedName~Dlq|FullyQualifiedName~Replay'
$tenantFilter = 'FullyQualifiedName~DedicatedTenant|FullyQualifiedName~TenantMiddleware|FullyQualifiedName~TenantRegistryService|FullyQualifiedName~TenantIsolation'
$paymentFilter = 'FullyQualifiedName~PaymentProviderSeed|FullyQualifiedName~PaymentReconciliation'

if ((Test-Phase10NfrCategorySelected -Name 'recovery') -and -not $SkipOperationalChecks) {
    $previousImageTag = Resolve-PreviousInventoryImageTag -ImageOwner $imageOwner
    if ([string]::IsNullOrWhiteSpace($previousImageTag)) {
        Write-Progress 'Rollback prerequisite missing (set PHASE10_PREVIOUS_IMAGE_TAG or retain a phase10-prev-* inventory image). Recovery will be BLOCKED; operational checks continue.'
    }
    else {
        $currentInventoryImage = "ghcr.io/$imageOwner/orderprocessing-inventory:$currentImageTag"
        $previousInventoryImage = "ghcr.io/$imageOwner/orderprocessing-inventory:$previousImageTag"
        Assert-DockerImageExists -ImageName $currentInventoryImage
        Assert-DockerImageExists -ImageName $previousInventoryImage
        Write-Progress "Rollback prerequisite resolved. currentImage=$currentInventoryImage previousImage=$previousInventoryImage"
    }
}

if (-not $OperationalOnly) {
$selectedFunctional = Test-Phase10NfrCategorySelected -Name 'functional'
if ($selectedFunctional) {
$previousTestConnection = $env:ORDERPROCESSING_TEST_CONNECTION_STRING
$previousNfrSqlConnection = $env:PHASE10_NFR_SQL_CONNECTION_STRING
$previousNfrServiceBusConnection = $env:PHASE10_NFR_SERVICEBUS_CONNECTION_STRING
$previousProvisioningConnection = $env:PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING
$env:PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING = $sqlConnectionString
$env:PHASE10_NFR_SQL_CONNECTION_STRING = $sqlConnectionString
$env:PHASE10_NFR_SERVICEBUS_CONNECTION_STRING = $serviceBusConnectionString
try {
    $functionalPassed = Invoke-CategoryCommand -Category 'functional' -Name 'Durability and tenant integration tests' -Command {
        Invoke-IsolatedNfrIntegrationFilterSet -FilterExpression $functionalFilter -ResultsDirectory (Join-Path $nfrRoot 'functional')
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
    if ($null -eq $previousProvisioningConnection) { Remove-Item Env:PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING -ErrorAction SilentlyContinue }
    else { $env:PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING = $previousProvisioningConnection }
}
$categories.functional.status = if ($functionalPassed) { 'passed' } else { 'failed' }
Write-CategorySummaryFile -Category 'functional'
Write-NfrSummary
}

if (Test-Phase10NfrCategorySelected -Name 'performance') {
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
}

if (Test-Phase10NfrCategorySelected -Name 'tenant') {
$previousTestConnection = $env:ORDERPROCESSING_TEST_CONNECTION_STRING
try {
    $previousProvisioningConnection = $env:PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING
    $env:PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING = $sqlConnectionString
    $tenantPassed = Invoke-CategoryCommand -Category 'tenant' -Name 'Tenant routing and isolation integration tests' -Command {
        Invoke-IsolatedNfrIntegrationFilterSet -FilterExpression $tenantFilter -ResultsDirectory (Join-Path $nfrRoot 'tenant')
    }
}
finally {
    if ([string]::IsNullOrWhiteSpace($previousTestConnection)) {
        Remove-Item Env:ORDERPROCESSING_TEST_CONNECTION_STRING -ErrorAction SilentlyContinue
    }
    else {
        $env:ORDERPROCESSING_TEST_CONNECTION_STRING = $previousTestConnection
    }
    if ($null -eq $previousProvisioningConnection) { Remove-Item Env:PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING -ErrorAction SilentlyContinue }
    else { $env:PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING = $previousProvisioningConnection }
}
$categories.tenant.status = if ($tenantPassed) { 'passed' } else { 'failed' }
Write-CategorySummaryFile -Category 'tenant'
Write-NfrSummary
}

if (Test-Phase10NfrCategorySelected -Name 'payments') {
$paymentsPassed = $false
$previousTestConnection = $env:ORDERPROCESSING_TEST_CONNECTION_STRING
try {
    $previousProvisioningConnection = $env:PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING
    $env:PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING = $sqlConnectionString
    $paymentsPassed = Invoke-CategoryCommand -Category 'payments' -Name 'Payment provider integration tests' -Command {
        Invoke-IsolatedNfrIntegrationFilterSet -FilterExpression $paymentFilter -ResultsDirectory (Join-Path $nfrRoot 'payments')
    }
}
finally {
    if ([string]::IsNullOrWhiteSpace($previousTestConnection)) {
        Remove-Item Env:ORDERPROCESSING_TEST_CONNECTION_STRING -ErrorAction SilentlyContinue
    }
    else {
        $env:ORDERPROCESSING_TEST_CONNECTION_STRING = $previousTestConnection
    }
    if ($null -eq $previousProvisioningConnection) { Remove-Item Env:PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING -ErrorAction SilentlyContinue }
    else { $env:PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING = $previousProvisioningConnection }
}

if ($paymentsPassed) {
    $categories.payments.integrationStatus = 'passed'
    if ($SkipDynamicPaymentMatrix) {
        $categories.payments.status = 'partial'
        $categories.payments.error = 'Dynamic provider matrix explicitly skipped; only non-transactional integration tests ran.'
        $categories.payments.checks += [ordered]@{ name = 'Dynamic provider payment matrix'; status = 'not-run'; reason = 'explicit opt-out' }
        $categories.payments.dynamicMatrixStatus = 'not-run'
    } else {
        $paymentsPassed = Invoke-CategoryCommand -Category 'payments' -Name 'Dynamic provider payment matrix' -Command {
            npm --prefix (Join-Path $workspaceRoot 'automation') run run:docker:dev:http:playwright-matrix
        }
        $categories.payments.status = if ($paymentsPassed) { 'passed' } else { 'failed' }
        $categories.payments.dynamicMatrixStatus = if ($paymentsPassed) { 'passed' } else { 'failed' }
    }
} else {
    $categories.payments.status = 'failed'
    $categories.payments.integrationStatus = 'failed'
    $categories.payments.dynamicMatrixStatus = if ($SkipDynamicPaymentMatrix) { 'not-run' } else { 'not-started' }
}
Write-CategorySummaryFile -Category 'payments'
Write-NfrSummary
}
}

if ($skipOperationalExecution) {
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
    $recoveryBlocked = $false
    $composeArgs = Get-Phase10ComposeArguments
    $operationalPassed = Invoke-CategoryCommand -Category 'operational' -Name 'Compose controls and running services' -Command {
        docker @composeArgs config --quiet
        if ($LASTEXITCODE -ne 0) { throw "docker compose config failed with exit code $LASTEXITCODE." }
        docker @composeArgs ps
    }

    if ($operationalPassed -and -not $OperationalOnly) {
        $operationalPassed = Invoke-CategoryCommand -Category 'operational' -Name 'Consumer restart diagnostics' -Command {
            docker @composeArgs restart inventory notifications
            if ($LASTEXITCODE -ne 0) { throw "Consumer restart failed with exit code $LASTEXITCODE." }
            Wait-ForUrl -Url 'http://localhost:5082/health/ready'
            Wait-ForUrl -Url 'http://localhost:5083/health/ready'
            docker @composeArgs logs --tail 200 inventory notifications
        }
    }

    if ($operationalPassed -and -not $OperationalOnly) {
        $operationalPassed = Invoke-CategoryCommand -Category 'operational' -Name 'Approved replay visibility (60s limit)' -Command {
            $restorePath = Join-Path $nfrRoot 'replay-proof/replay-restoration.json'
            $restoreStart = [DateTime]::UtcNow
            $restored = $false
            try {
                if (Test-Path -LiteralPath $restorePath) { throw 'Replay restoration evidence already exists; use a fresh run directory.' }
                & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-local-messaging.ps1') `
                    -ArtifactDirectory (Join-Path $nfrRoot 'replay-proof')
                $replayExit = $LASTEXITCODE
                # Windows filesystems may round LastWriteTimeUtc to whole seconds. The path is
                # required to be absent before the child starts, so this narrow tolerance cannot
                # admit prior-run evidence and avoids rejecting a freshly written record.
                $restored = Test-Phase10ReplayRestorationEvidence -Path $restorePath -NotBeforeUtc $restoreStart.AddSeconds(-2)
                if (-not $restored) { throw 'Replay restoration is not proven; later mutations are blocked.' }
                if ($replayExit -ne 0) { throw 'Replay failed despite verified restoration; no replay acceptance is claimed.' }
            } finally {
                if (-not $restored) { $script:Phase10NfrRestorationFailed = $true }
            }
        }
    }

    if ($operationalPassed -and $OperationalOnly) {
        $burstResultPath = Join-Path $nfrRoot 'operational-100-message-burst.json'
        $operationalPassed = Invoke-CategoryCommand -Category 'operational' -Name 'Build NFR probe for operational-only lane' -Command {
            dotnet build tools/Phase10.NfrProbe/Phase10.NfrProbe.csproj --no-restore
        }
        if ($operationalPassed) {
            $operationalPassed = Invoke-CategoryCommand -Category 'operational' -Name '100 message durable consumer burst' -Command {
                dotnet run `
                    --project tools/Phase10.NfrProbe/Phase10.NfrProbe.csproj `
                    --no-build `
                    -- `
                    --servicebus-connection-string $serviceBusConnectionString `
                    --sql-connection-string $sqlConnectionString `
                    --sql-read-mode docker-compose `
                    --topic $topicName `
                    --tenant-code TenantA `
                    --message-count 100 `
                    --timeout-seconds $PerformanceTimeoutSeconds `
                    --maximum-p95-seconds $MaximumP95Seconds `
                    --result-path $burstResultPath
            }
            if ($operationalPassed) {
                $burst = Get-Content -LiteralPath $burstResultPath -Raw | ConvertFrom-Json
                if ($burst.ExpectedMessages -ne 100 -or
                    $burst.InventoryInboxCount -ne 100 -or
                    $burst.NotificationsInboxCount -ne 100 -or
                    $burst.InventoryEffectCount -ne 100 -or
                    $burst.NotificationEffectCount -ne 100 -or
                    $burst.P95Seconds -ge $MaximumP95Seconds) {
                    throw 'Operational-only burst did not prove exactly 100 inbox rows and durable effects per consumer within the P95 target.'
                }
            }
        }
    }

    if ($operationalPassed) {
        $operationalPassed = Invoke-CategoryCommand -Category 'operational' -Name 'Consumer outage backlog recovery drill' -Command {
            Invoke-ConsumerOutageBacklogDrill -TopicName $topicName -SqlConnectionString $sqlConnectionString `
                -ServiceBusConnectionString $serviceBusConnectionString `
                -MessageCount $(if ($OperationalOnly) { 100 } else { 25 }) `
                -MaximumP95Seconds $MaximumP95Seconds
        }
    }
    $categories.operational.status = if ($operationalPassed) { 'passed' } else { 'failed' }
    Write-CategorySummaryFile -Category 'operational'

    if ($script:Phase10NfrRestorationFailed) {
        $recoveryPassed = $false
        $recoveryBlocked = $true
        $categories.recovery.error = 'BLOCKED: earlier operational restoration failed or is unproven; no rollback mutation was attempted.'
    }
    elseif ([string]::IsNullOrWhiteSpace($previousImageTag)) {
        $recoveryPassed = $false
        $recoveryBlocked = $true
        $categories.recovery.error =
            'BLOCKED: a retained previous inventory image (PHASE10_PREVIOUS_IMAGE_TAG or phase10-prev-*) is required so rollback is executed rather than documented only.'
    }
    else {
        $rollbackEvidencePath = Join-Path $nfrRoot 'rollback-evidence.json'
        $recoveryPassed = Invoke-CategoryCommand -Category 'recovery' -Name 'Retained image digest evidence' -Command {
            $script:phase10RollbackEvidence = Get-Phase10RollbackPreflight `
                -CurrentImage $currentInventoryImage `
                -PreviousImage $previousInventoryImage `
                -EvidencePath $rollbackEvidencePath
            Write-Host "Rollback baseline verified: source=$($script:phase10RollbackEvidence.sourceCommit) previousId=$($script:phase10RollbackEvidence.previousImageId) currentId=$($script:phase10RollbackEvidence.currentImageId)"
        }

        if ($recoveryPassed) {
            $originalTag = $env:PHASE10_IMAGE_TAG
            $rollbackPassed = $false
            $restorePassed = $false
            try {
                $env:PHASE10_IMAGE_TAG = $previousImageTag
                $rollbackPassed = Invoke-CategoryCommand -Category 'recovery' -Name 'Rollback inventory to previous image' -Command {
                    docker @composeArgs up -d --no-build inventory
                    if ($LASTEXITCODE -ne 0) { throw "Previous image startup failed with exit code $LASTEXITCODE." }
                    Wait-ForUrl -Url 'http://localhost:5082/health/ready'
                    $activeContainer = Resolve-ComposeServiceContainerName -ServiceName 'inventory'
                    $activeImageId = ([string](& docker inspect --format '{{.Image}}' $activeContainer)).Trim()
                    if ($LASTEXITCODE -ne 0 -or $activeImageId -cne $script:phase10RollbackEvidence.previousImageId) {
                        throw 'Running Inventory image does not match the immutable verified rollback image.'
                    }
                    Write-Host "Rollback image active and ready: $activeImageId"
                }
            }
            finally {
                $env:PHASE10_IMAGE_TAG = $currentImageTag
                $restorePassed = Invoke-CategoryCommand -Category 'recovery' -Name 'Restore inventory current image' -Command {
                    docker @composeArgs up -d --no-build inventory
                    if ($LASTEXITCODE -ne 0) { throw "Current image restore failed with exit code $LASTEXITCODE." }
                    Wait-ForUrl -Url 'http://localhost:5082/health/ready'
                    $activeContainer = Resolve-ComposeServiceContainerName -ServiceName 'inventory'
                    $restoredImageId = ([string](& docker inspect --format '{{.Image}}' $activeContainer)).Trim()
                    if ($LASTEXITCODE -ne 0 -or $restoredImageId -cne $script:phase10RollbackEvidence.currentImageId) {
                        throw 'Running Inventory image was not restored to the exact pre-drill image ID.'
                    }
                    Write-Host "Original Inventory image restored and ready: $restoredImageId"
                }
                if ([string]::IsNullOrWhiteSpace($originalTag)) {
                    Remove-Item Env:PHASE10_IMAGE_TAG -ErrorAction SilentlyContinue
                }
                else {
                    $env:PHASE10_IMAGE_TAG = $originalTag
                }
                if (-not $restorePassed) { $script:Phase10NfrRestorationFailed = $true }
            }
            $recoveryPassed = $rollbackPassed -and $restorePassed -and $recoveryPassed
            $script:phase10RollbackEvidence.status = if ($recoveryPassed) { 'passed' } else { 'failed' }
            $script:phase10RollbackEvidence.rollbackObserved = $rollbackPassed
            $script:phase10RollbackEvidence.currentImageRestored = $restorePassed
            $script:phase10RollbackEvidence | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $rollbackEvidencePath -Encoding utf8
        }
        else {
            $recoveryBlocked = $true
            $categories.recovery.error = 'BLOCKED: retained image provenance or compatibility preflight did not pass; no rollback mutation was attempted.'
        }
    }
    $categories.recovery.status = if ($recoveryPassed) { 'passed' } elseif ($recoveryBlocked) { 'blocked' } else { 'failed' }
    Write-CategorySummaryFile -Category 'recovery'
}

$securityPrerequisites = Test-Path -LiteralPath (Join-Path $workspaceRoot 'frontend\apps\web\scripts\phase10-identity-proof.mjs')
if (Test-Phase10NfrCategorySelected -Name 'security') {
if ($script:Phase10NfrRestorationFailed) {
    $categories.security.status = 'blocked'
    $categories.security.error = 'BLOCKED: an earlier outage-drill restoration failed; later identity actions were not attempted.'
}
elseif (-not $securityPrerequisites) {
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
}

if ($null -ne $paymentSettingsBefore) {
    $afterPath = Join-Path $nfrRoot 'payment-settings-after.json'
    try {
        $paymentSettingsAfter = Get-Phase10NfrPaymentSettingsSnapshot -Settings $envValues
        $paymentSettingsAfter | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $afterPath -Encoding utf8
        $beforeCanonical = ConvertTo-Json -InputObject $paymentSettingsBefore -Depth 10 -Compress
        $afterCanonical = ConvertTo-Json -InputObject $paymentSettingsAfter -Depth 10 -Compress
        if ($beforeCanonical -cne $afterCanonical) {
            $summary.paymentSettingsIntegrity = 'failed'
            $categories.payments.status = 'failed'
            $categories.payments.error = 'Active tenant provider routes/settings changed during the targeted no-charge NFR run; no automatic restoration was attempted.'
        }
        else { $summary.paymentSettingsIntegrity = 'passed' }
        $summary.paymentSettingsEvidence += [ordered]@{ file = 'payment-settings-after.json'; sha256 = (Get-FileHash -LiteralPath $afterPath -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    catch {
        $summary.paymentSettingsIntegrity = 'failed'
        $categories.payments.status = 'failed'
        $categories.payments.error = 'Could not prove active tenant provider settings remained unchanged after the targeted NFR run.'
    }
    Write-CategorySummaryFile -Category 'payments'
}

$aggregate = Get-Phase10NfrAggregate -Categories $categories
$notPassed = $aggregate.NonPassing
$summary.status = $aggregate.Status
$summary.nonPassingCategories = $notPassed
$summary.commitShaAtFinish = (& git -C $workspaceRoot rev-parse HEAD).Trim()
$summary.worktreeAtFinish = $(if ([string]::IsNullOrWhiteSpace((& git -C $workspaceRoot status --porcelain) -join '')) { 'clean' } else { 'dirty' })
$summary.completedAtIst = (Get-IstNow).ToString('o')
Set-Content -LiteralPath $currentStepPath -Value 'completed' -Encoding utf8
Write-NfrSummary
    Write-Progress "$ProofName $($summary.status)."

if ($summary.status -ne 'passed') {
    throw "$ProofName $($summary.status). Non-passing categories: $($notPassed -join ', '). Review $summaryPath and the category summaries."
}
