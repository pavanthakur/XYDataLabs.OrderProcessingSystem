#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('dev', 'stg', 'prod', 'all')]
    [string[]] $Environment = @('dev'),

    [Parameter(Mandatory = $false)]
    [ValidateSet('http', 'https', 'all')]
    [string[]] $Profile = @('http'),

    [Parameter(Mandatory = $false)]
    [string[]] $Tenant,

    [Parameter(Mandatory = $false)]
    [string] $OutputRoot,

    [switch] $SkipTests,
    [switch] $SkipAutomation,
    [switch] $SkipCleanup,
    [switch] $AllowPartialExecution
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$automationRoot = Join-Path $repoRoot 'automation'
$dockerRoot = Join-Path $repoRoot 'Resources\Docker'
$timestamp = Get-Date
$bundleId = 'docker-validation-{0}' -f $timestamp.ToString('yyyyMMdd-HHmmss')
$bundleRoot = if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    Join-Path $automationRoot (Join-Path 'reports\docker-validation' $bundleId)
}
else {
    Join-Path $OutputRoot $bundleId
}

$apiTestProject = Join-Path $repoRoot 'tests\XYDataLabs.OrderProcessingSystem.API.Tests\XYDataLabs.OrderProcessingSystem.API.Tests.csproj'
$integrationTestProject = Join-Path $repoRoot 'tests\XYDataLabs.OrderProcessingSystem.Integration.Tests\XYDataLabs.OrderProcessingSystem.Integration.Tests.csproj'

New-Item -ItemType Directory -Force -Path $bundleRoot | Out-Null

function Expand-Selection {
    param(
        [string[]] $Requested,
        [string[]] $Allowed
    )

    if ($Requested -contains 'all') {
        return @($Allowed)
    }

    return @($Requested | Where-Object { $_ -in $Allowed } | Select-Object -Unique)
}

function To-Array {
    param([object] $Value)

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [System.Array]) {
        return @($Value)
    }

    return @($Value)
}

function Get-EnvOrDockerSecretValue {
    param(
        [string] $Name,
        [string] $SecretsFilePath
    )

    if (-not (Test-Path $SecretsFilePath)) {
        $environmentItem = Get-Item -Path "Env:$Name" -ErrorAction SilentlyContinue
        $environmentValue = if ($null -ne $environmentItem) { $environmentItem.Value } else { '' }
        return $environmentValue
    }

    foreach ($line in Get-Content $SecretsFilePath) {
        if ($line -match "^$Name=(.*)$") {
            return $Matches[1].Trim()
        }
    }

    $environmentItem = Get-Item -Path "Env:$Name" -ErrorAction SilentlyContinue
    $environmentValue = if ($null -ne $environmentItem) { $environmentItem.Value } else { '' }
    return $environmentValue
}

function Get-RelativePathSafe {
    param(
        [string] $BasePath,
        [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }

    return [System.IO.Path]::GetRelativePath($BasePath, $Path)
}

function Test-IsPlaceholderValue {
    param(
        [string] $Value,
        [string[]] $PlaceholderValues
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $true
    }

    $normalizedValue = $Value.Trim().ToLowerInvariant()
    return $normalizedValue -in @($PlaceholderValues | ForEach-Object { $_.ToLowerInvariant() })
}

function Write-JsonFile {
    param(
        [string] $Path,
        [object] $Value
    )

    $directory = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    $Value | ConvertTo-Json -Depth 12 | Set-Content -Path $Path -Encoding UTF8
}

function Invoke-LoggedCommand {
    param(
        [string] $Command,
        [string[]] $Arguments,
        [string] $LogPath,
        [string] $WorkingDirectory
    )

    $directory = Split-Path -Path $LogPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    Push-Location $WorkingDirectory
    try {
        $output = & $Command @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    $outputText = [string]::Join([Environment]::NewLine, @($output | ForEach-Object { $_.ToString() }))
    Set-Content -Path $LogPath -Value $outputText -Encoding UTF8

    return [PSCustomObject] @{
        Command = $Command
        Arguments = @($Arguments)
        ExitCode = $exitCode
        OutputText = $outputText
        LogPath = $LogPath
    }
}

function Get-TestSummary {
    param([string] $OutputText)

    $summary = [ordered] @{
        Total = $null
        Passed = $null
        Failed = $null
        Skipped = $null
        Outcome = 'unknown'
    }

    $match = [regex]::Match($OutputText, 'Total tests:\s*(?<total>\d+)\s+Passed:\s*(?<passed>\d+)\s+Failed:\s*(?<failed>\d+)\s+Skipped:\s*(?<skipped>\d+)')
    if (-not $match.Success) {
        $match = [regex]::Match($OutputText, 'Passed!\s+- Failed:\s*(?<failed>\d+),\s*Passed:\s*(?<passed>\d+),\s*Skipped:\s*(?<skipped>\d+),\s*Total:\s*(?<total>\d+)')
    }

    if ($match.Success) {
        $summary.Total = [int] $match.Groups['total'].Value
        $summary.Passed = [int] $match.Groups['passed'].Value
        $summary.Failed = [int] $match.Groups['failed'].Value
        $summary.Skipped = [int] $match.Groups['skipped'].Value
        $summary.Outcome = if ($summary.Failed -gt 0) { 'failed' } else { 'passed' }
    }
    else {
        $failedMatches = [regex]::Matches($OutputText, '\[FAIL\]')
        if ($failedMatches.Count -gt 0) {
            $summary.Failed = $failedMatches.Count
            $summary.Outcome = 'failed'
        }
    }

    return [PSCustomObject] $summary
}

function ConvertFrom-TrailingJson {
    param([string] $Text)

    $lines = $Text -split "`r?`n"
    for ($index = $lines.Length - 1; $index -ge 0; $index--) {
        if ($lines[$index].TrimStart().StartsWith('{')) {
            $candidate = ($lines[$index..($lines.Length - 1)] -join [Environment]::NewLine).Trim()
            try {
                return $candidate | ConvertFrom-Json -Depth 20
            }
            catch {
            }
        }
    }

    throw 'Unable to parse trailing JSON payload from command output.'
}

function Get-ComposeArguments {
    param(
        [string] $TargetEnvironment,
        [string] $TargetProfile
    )

    $arguments = @()
    if (Test-Path (Join-Path $dockerRoot '.env.local')) {
        $arguments += @('--env-file', '.env.local')
    }

    $arguments += @('-f', 'docker-compose.database.yml', '-f', "docker-compose.$TargetEnvironment.yml", '--profile', $TargetProfile)
    return $arguments
}

function Get-ContainerSnapshot {
    param(
        [string] $TargetEnvironment,
        [string] $TargetProfile,
        [string] $TargetDirectory
    )

    $composeArguments = Get-ComposeArguments -TargetEnvironment $TargetEnvironment -TargetProfile $TargetProfile
    $psArguments = @('compose') + $composeArguments + @('ps', '--format', 'json')
    $psResult = Invoke-LoggedCommand -Command 'docker' -Arguments $psArguments -LogPath (Join-Path $TargetDirectory 'docker-compose-ps.log') -WorkingDirectory $dockerRoot
    $psJsonPath = Join-Path $TargetDirectory 'docker-compose-ps.json'
    Set-Content -Path $psJsonPath -Value $psResult.OutputText -Encoding UTF8

    $idsArguments = @('compose') + $composeArguments + @('ps', '-q')
    $idsResult = Invoke-LoggedCommand -Command 'docker' -Arguments $idsArguments -LogPath (Join-Path $TargetDirectory 'docker-compose-ids.log') -WorkingDirectory $dockerRoot
    if ($psResult.ExitCode -ne 0 -or $idsResult.ExitCode -ne 0) {
        return [PSCustomObject] @{
            Outcome = 'failed'
            ContainerCount = 0
            FailedContainers = @()
            ComposePsPath = $psJsonPath
            InspectPath = ''
        }
    }

    $containerIds = @($idsResult.OutputText -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    $inspectObjects = @()
    $inspectPath = Join-Path $TargetDirectory 'docker-inspect.json'
    if ($containerIds.Count -gt 0) {
        $inspectArguments = @('inspect') + $containerIds
        $inspectResult = Invoke-LoggedCommand -Command 'docker' -Arguments $inspectArguments -LogPath (Join-Path $TargetDirectory 'docker-inspect.log') -WorkingDirectory $repoRoot
        Set-Content -Path $inspectPath -Value $inspectResult.OutputText -Encoding UTF8
        if ($inspectResult.ExitCode -eq 0) {
            try {
                $inspectObjects = To-Array -Value ($inspectResult.OutputText | ConvertFrom-Json -Depth 20)
            }
            catch {
                $inspectObjects = @()
            }
        }
    }
    else {
        Write-JsonFile -Path $inspectPath -Value @()
    }

    $failedContainers = @()
    foreach ($container in $inspectObjects) {
        $state = $container.State
        $status = if ($state.PSObject.Properties.Name -contains 'Health' -and $state.Health) {
            $state.Health.Status
        }
        else {
            $state.Status
        }

        if ($status -notin @('healthy', 'running')) {
            $failedContainers += [PSCustomObject] @{
                Name = $container.Name
                Status = $status
            }
        }
    }

    return [PSCustomObject] @{
        Outcome = if ($containerIds.Count -eq 0) { 'failed' } elseif ($failedContainers.Count -gt 0) { 'failed' } else { 'passed' }
        ContainerCount = $containerIds.Count
        FailedContainers = @($failedContainers)
        ComposePsPath = $psJsonPath
        InspectPath = $inspectPath
    }
}

function Wait-ForContainerSnapshotPassed {
    param(
        [string] $TargetEnvironment,
        [string] $TargetProfile,
        [string] $TargetDirectory,
        [int] $TimeoutSec = 120,
        [int] $IntervalSec = 5
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    do {
        $snapshot = Get-ContainerSnapshot -TargetEnvironment $TargetEnvironment -TargetProfile $TargetProfile -TargetDirectory $TargetDirectory
        if ($snapshot.Outcome -eq 'passed') {
            return $snapshot
        }

        Start-Sleep -Seconds $IntervalSec
    }
    while ((Get-Date) -lt $deadline)

    return $snapshot
}

function Get-DockerComposeFilePath {
    param([string] $TargetEnvironment)

    return Join-Path $dockerRoot ("docker-compose.{0}.yml" -f $TargetEnvironment)
}

function Get-ExpectedDatabaseNames {
    param([string] $TargetEnvironment)

    $composePath = Get-DockerComposeFilePath -TargetEnvironment $TargetEnvironment
    if (-not (Test-Path -LiteralPath $composePath)) {
        throw "Unsupported Docker validation environment '$TargetEnvironment'. Compose file not found: $composePath"
    }

    $content = Get-Content -LiteralPath $composePath -Raw
    $databaseNames = New-Object 'System.Collections.Generic.List[string]'

    $sharedMatches = [regex]::Matches($content, 'ConnectionStrings__OrderProcessingSystemDbConnection=.+?Database=(?<database>[^;]+);')
    foreach ($match in $sharedMatches) {
        $databaseName = $match.Groups['database'].Value.Trim()
        if (-not [string]::IsNullOrWhiteSpace($databaseName) -and -not $databaseNames.Contains($databaseName)) {
            $databaseNames.Add($databaseName)
        }
    }

    $dedicatedMatches = [regex]::Matches($content, 'DedicatedTenantConnectionStrings__[^=]+=.+?Database=(?<database>[^;]+);')
    foreach ($match in $dedicatedMatches) {
        $databaseName = $match.Groups['database'].Value.Trim()
        if (-not [string]::IsNullOrWhiteSpace($databaseName) -and -not $databaseNames.Contains($databaseName)) {
            $databaseNames.Add($databaseName)
        }
    }

    if ($databaseNames.Count -eq 0) {
        throw "Could not resolve expected database names from $composePath."
    }

    return @($databaseNames)
}

function Get-LatestMigrationId {
    $migrationsPath = Join-Path $repoRoot 'XYDataLabs.OrderProcessingSystem.Infrastructure\Migrations'
    $migrationFiles = @(
        Get-ChildItem -Path $migrationsPath -Filter '*.cs' -File |
        Where-Object {
            $_.Name -notlike '*.Designer.cs' -and
            $_.Name -ne 'OrderProcessingSystemDbContextModelSnapshot.cs' -and
            $_.BaseName -match '^\d+_'
        } |
        Sort-Object Name
    )

    if ($migrationFiles.Count -eq 0) {
        return ''
    }

    return $migrationFiles[-1].BaseName
}

function Get-SqlcmdOutputLines {
    param([string] $OutputText)

    return @(
        $OutputText -split "`r?`n" |
            ForEach-Object { $_.Trim() } |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and
                $_ -notmatch '^\(\d+ rows? affected\)$'
            }
    )
}

function Invoke-SqlcmdInContainer {
    param(
        [string] $Database,
        [string] $Query,
        [string] $LogPath
    )

    $escapedQuery = $Query.Replace('"', '\"')
    $shellCommand = [string]::Format(
        'if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then SQLCMD=/opt/mssql-tools18/bin/sqlcmd; else SQLCMD=/opt/mssql-tools/bin/sqlcmd; fi; "$SQLCMD" -C -S localhost -U sa -P "$SA_PASSWORD" -d "{0}" -h -1 -W -Q "{1}"',
        $Database,
        $escapedQuery)

    return Invoke-LoggedCommand -Command 'docker' -Arguments @('exec', 'orderprocessing-sqlserver', '/bin/sh', '-lc', $shellCommand) -LogPath $LogPath -WorkingDirectory $repoRoot
}

function Invoke-DatabaseReadinessCheck {
    param(
        [string] $TargetEnvironment,
        [string] $TargetDirectory
    )

    $expectedDatabases = @(Get-ExpectedDatabaseNames -TargetEnvironment $TargetEnvironment)
    $latestMigrationId = Get-LatestMigrationId
    $summaryPath = Join-Path $TargetDirectory 'database-readiness.json'
    $masterLogPath = Join-Path $TargetDirectory 'database-readiness-master.log'

    $masterQuery = "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE name IN ('{0}') ORDER BY name;" -f ($expectedDatabases -join "','")
    $masterResult = Invoke-SqlcmdInContainer -Database 'master' -Query $masterQuery -LogPath $masterLogPath
    $foundDatabases = if ($masterResult.ExitCode -eq 0) { @(Get-SqlcmdOutputLines -OutputText $masterResult.OutputText) } else { @() }

    $databaseSummaries = [System.Collections.Generic.List[object]]::new()
    foreach ($databaseName in $expectedDatabases) {
        $migrationLogPath = Join-Path $TargetDirectory ("database-readiness-{0}-migration.log" -f $databaseName)
        $tablesLogPath = Join-Path $TargetDirectory ("database-readiness-{0}-tables.log" -f $databaseName)

        $migrationResult = Invoke-SqlcmdInContainer -Database $databaseName -Query 'SET NOCOUNT ON; SELECT TOP 1 [MigrationId] FROM [__EFMigrationsHistory] ORDER BY [MigrationId] DESC;' -LogPath $migrationLogPath
        $tableResult = Invoke-SqlcmdInContainer -Database $databaseName -Query "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.tables WHERE name IN ('Customers', 'Products', 'Orders', 'OutboxMessages');" -LogPath $tablesLogPath

        $migrationLines = if ($migrationResult.ExitCode -eq 0) { @(Get-SqlcmdOutputLines -OutputText $migrationResult.OutputText) } else { @() }
        $tableLines = if ($tableResult.ExitCode -eq 0) { @(Get-SqlcmdOutputLines -OutputText $tableResult.OutputText) } else { @() }

        $latestAppliedMigration = if (@($migrationLines).Count -gt 0) { @($migrationLines)[-1] } else { '' }
        $requiredTableCount = 0
        if (@($tableLines).Count -gt 0) {
            [void][int]::TryParse(@($tableLines)[-1], [ref] $requiredTableCount)
        }

        $databaseOutcome = if (
            $databaseName -in $foundDatabases -and
            $migrationResult.ExitCode -eq 0 -and
            $tableResult.ExitCode -eq 0 -and
            $latestAppliedMigration -eq $latestMigrationId -and
            $requiredTableCount -eq 4) {
            'passed'
        }
        else {
            'failed'
        }

        $databaseSummaries.Add([PSCustomObject] @{
            Database = $databaseName
            Outcome = $databaseOutcome
            Exists = $databaseName -in $foundDatabases
            LatestMigrationExpected = $latestMigrationId
            LatestMigrationApplied = $latestAppliedMigration
            RequiredTableCount = $requiredTableCount
            MigrationLog = Get-RelativePathSafe -BasePath $bundleRoot -Path $migrationLogPath
            TableLog = Get-RelativePathSafe -BasePath $bundleRoot -Path $tablesLogPath
        })
    }

    $summary = [PSCustomObject] @{
        Outcome = if ($masterResult.ExitCode -eq 0 -and @($databaseSummaries | Where-Object { $_.Outcome -eq 'failed' }).Count -eq 0) { 'passed' } else { 'failed' }
        ExpectedDatabases = $expectedDatabases
        FoundDatabases = $foundDatabases
        LatestMigrationExpected = $latestMigrationId
        MasterLog = Get-RelativePathSafe -BasePath $bundleRoot -Path $masterLogPath
        Databases = @($databaseSummaries)
    }

    Write-JsonFile -Path $summaryPath -Value $summary

    return [PSCustomObject] @{
        Outcome = $summary.Outcome
        SummaryPath = $summaryPath
        Summary = $summary
    }
}

function Test-OpenPayCredentialReadiness {
    param([string] $TargetDirectory)

    $summaryPath = Join-Path $TargetDirectory 'openpay-credential-readiness.json'
    $merchantId = Get-EnvOrDockerSecretValue -Name 'LOCAL_OPENPAY_MERCHANT_ID' -SecretsFilePath (Join-Path $dockerRoot '.env.local')
    $privateKey = Get-EnvOrDockerSecretValue -Name 'LOCAL_OPENPAY_PRIVATE_KEY' -SecretsFilePath (Join-Path $dockerRoot '.env.local')
    $deviceSessionId = Get-EnvOrDockerSecretValue -Name 'LOCAL_OPENPAY_DEVICE_SESSION_ID' -SecretsFilePath (Join-Path $dockerRoot '.env.local')

    $merchantPlaceholders = @(
        '',
        'merchant-id',
        'local-sandbox-only',
        '<set-a-local-openpay-merchant-id>',
        '__openpay_merchant_id__'
    )
    $privateKeyPlaceholders = @(
        '',
        'private-key',
        'local-sandbox-only',
        '<set-a-local-openpay-private-key>',
        '__openpay_private_key__'
    )

    $issues = [System.Collections.Generic.List[string]]::new()
    if (Test-IsPlaceholderValue -Value $merchantId -PlaceholderValues $merchantPlaceholders) {
        $issues.Add('LOCAL_OPENPAY_MERCHANT_ID is missing or still set to a placeholder value.')
    }

    if (Test-IsPlaceholderValue -Value $privateKey -PlaceholderValues $privateKeyPlaceholders) {
        $issues.Add('LOCAL_OPENPAY_PRIVATE_KEY is missing or still set to a placeholder value.')
    }

    $summary = [PSCustomObject] @{
        Outcome = if ($issues.Count -eq 0) { 'passed' } else { 'blocked' }
        Summary = if ($issues.Count -eq 0) {
            'OpenPay runtime credentials look non-placeholder. Automation can proceed.'
        }
        else {
            'Automation blocked because Docker runtime OpenPay credentials are missing or still use placeholder values. Run scripts/setup-local.ps1 or update Resources/Docker/.env.local with real sandbox credentials before rerunning payment automation.'
        }
        MerchantIdConfigured = -not [string]::IsNullOrWhiteSpace($merchantId)
        PrivateKeyConfigured = -not [string]::IsNullOrWhiteSpace($privateKey)
        DeviceSessionIdConfigured = -not [string]::IsNullOrWhiteSpace($deviceSessionId)
        Issues = @($issues)
    }

    Write-JsonFile -Path $summaryPath -Value $summary

    return [PSCustomObject] @{
        Outcome = $summary.Outcome
        Summary = $summary.Summary
        SummaryPath = $summaryPath
        Details = $summary
    }
}

function Invoke-BundleTests {
    param([string] $TestsDirectory)

    $results = [ordered] @{}

    $apiResult = Invoke-LoggedCommand -Command 'dotnet' -Arguments @('test', $apiTestProject, '--nologo') -LogPath (Join-Path $TestsDirectory 'api-tests.log') -WorkingDirectory $repoRoot
    $results.Api = [PSCustomObject] @{
        Outcome = if ($apiResult.ExitCode -eq 0) { 'passed' } else { 'failed' }
        ExitCode = $apiResult.ExitCode
        Summary = Get-TestSummary -OutputText $apiResult.OutputText
        LogPath = $apiResult.LogPath
    }

    $integrationResult = Invoke-LoggedCommand -Command 'dotnet' -Arguments @('test', $integrationTestProject, '--nologo') -LogPath (Join-Path $TestsDirectory 'integration-tests.log') -WorkingDirectory $repoRoot
    $results.Integration = [PSCustomObject] @{
        Outcome = if ($integrationResult.ExitCode -eq 0) { 'passed' } else { 'failed' }
        ExitCode = $integrationResult.ExitCode
        Summary = Get-TestSummary -OutputText $integrationResult.OutputText
        LogPath = $integrationResult.LogPath
    }

    return [PSCustomObject] $results
}

function Invoke-AutomationRun {
    param(
        [string] $TargetKey,
        [string] $TargetDirectory
    )

    $arguments = @('--prefix', 'automation', 'run', 'run', '--', '--target', $TargetKey)
    foreach ($tenantCode in @($Tenant)) {
        if (-not [string]::IsNullOrWhiteSpace($tenantCode)) {
            foreach ($code in ($tenantCode -split ',')) {
                $code = $code.Trim()
                if (-not [string]::IsNullOrWhiteSpace($code)) {
                    $arguments += @('--tenant', $code)
                }
            }
        }
    }
    if ($AllowPartialExecution) {
        $arguments += '--allow-partial'
    }

    $automationResult = Invoke-LoggedCommand -Command 'npm' -Arguments $arguments -LogPath (Join-Path $TargetDirectory 'automation.log') -WorkingDirectory $repoRoot
    if ($automationResult.ExitCode -ne 0) {
        return [PSCustomObject] @{
            Outcome = 'failed'
            ExitCode = $automationResult.ExitCode
            ReportDirectory = ''
            VerificationReportPath = ''
            SummaryPath = ''
            RawOutputPath = $automationResult.LogPath
            TenantPassCount = 0
            TenantFailCount = 0
            TenantSkippedCount = 0
            VerificationOutcome = 'failed'
            VerificationSummary = 'Automation command failed before a report could be parsed.'
        }
    }

    $payload = ConvertFrom-TrailingJson -Text $automationResult.OutputText
    $rows = To-Array -Value $payload.rows
    $tenantPassCount = @($rows | Where-Object { $_.verificationOutcome -eq 'passed' }).Count
    $tenantFailCount = @($rows | Where-Object { $_.verificationOutcome -eq 'failed' -or $_.journeyOutcome -like 'failed*' }).Count
    $tenantSkippedCount = @($rows | Where-Object { $_.verificationOutcome -eq 'skipped' }).Count

    $reportDirectory = [string] $payload.reportDirectory
    $summaryPath = Join-Path $reportDirectory 'summary.json'
    $verificationReportPath = Join-Path $reportDirectory 'verification-report.json'

    if (Test-Path $verificationReportPath) {
        Copy-Item -Path $verificationReportPath -Destination (Join-Path $TargetDirectory 'verification-report.json') -Force
    }

    Write-JsonFile -Path (Join-Path $TargetDirectory 'automation-artifacts.json') -Value ([ordered] @{
        ReportDirectory = $reportDirectory
        SummaryJson = if (Test-Path $summaryPath) { $summaryPath } else { '' }
        SummaryMarkdown = Join-Path $reportDirectory 'summary.md'
        VerificationReportJson = if (Test-Path $verificationReportPath) { $verificationReportPath } else { '' }
    })

    return [PSCustomObject] @{
        Outcome = if ($tenantFailCount -gt 0) { 'failed' } else { 'passed' }
        ExitCode = $automationResult.ExitCode
        ReportDirectory = $reportDirectory
        VerificationReportPath = if (Test-Path $verificationReportPath) { $verificationReportPath } else { '' }
        SummaryPath = if (Test-Path $summaryPath) { $summaryPath } else { '' }
        RawOutputPath = $automationResult.LogPath
        TenantPassCount = $tenantPassCount
        TenantFailCount = $tenantFailCount
        TenantSkippedCount = $tenantSkippedCount
        VerificationOutcome = if ($tenantFailCount -gt 0) { 'failed' } else { 'passed' }
        VerificationSummary = [string] $payload.verificationSummary
    }
}

function Write-BundleSummary {
    param(
        [string] $SummaryMarkdownPath,
        [string] $SummaryJsonPath,
        [pscustomobject] $BundleSummary
    )

    $apiPassed = if ($null -ne $BundleSummary.ApiTests.Summary.Passed) { $BundleSummary.ApiTests.Summary.Passed } else { 'n/a' }
    $apiTotal = if ($null -ne $BundleSummary.ApiTests.Summary.Total) { $BundleSummary.ApiTests.Summary.Total } else { 'n/a' }
    $integrationPassed = if ($null -ne $BundleSummary.IntegrationTests.Summary.Passed) { $BundleSummary.IntegrationTests.Summary.Passed } else { 'n/a' }
    $integrationTotal = if ($null -ne $BundleSummary.IntegrationTests.Summary.Total) { $BundleSummary.IntegrationTests.Summary.Total } else { 'n/a' }

    $targetLines = @(
        foreach ($target in $BundleSummary.Targets) {
            "- $($target.Target): startup=$($target.DockerStartupOutcome), health=$($target.ContainerHealthOutcome), db=$($target.DatabaseReadinessOutcome), openpay=$($target.OpenPayCredentialOutcome), automation=$($target.AutomationOutcome), verification=$($target.VerificationOutcome)"
            "  artifacts: $($target.TargetDirectory)"
            "  startup log: $($target.StartupLog)"
            "  database summary: $($target.DatabaseReadinessSummary)"
            "  OpenPay credential summary: $($target.OpenPayCredentialSummaryPath)"
            "  automation log: $($target.AutomationLog)"
            "  automation report: $($target.AutomationReportDirectory)"
        }
    )

    $testLines = @(
        "- API tests: $($BundleSummary.ApiTests.Outcome) (passed $apiPassed / total $apiTotal)",
        "- Integration tests: $($BundleSummary.IntegrationTests.Outcome) (passed $integrationPassed / total $integrationTotal)"
    )

    $artifactRootLine = [System.IO.Path]::GetRelativePath((Split-Path -Path $SummaryMarkdownPath -Parent), $bundleRoot)
    if ([string]::IsNullOrWhiteSpace($artifactRootLine) -or $artifactRootLine -eq '.') {
        $artifactRootLine = '.'
    }
    $markdown = @(
        '# Docker Validation Bundle',
        '',
        "Bundle ID: $($BundleSummary.BundleId)",
        "Started: $($BundleSummary.StartedUtc)",
        "Finished: $($BundleSummary.FinishedUtc)",
        "Overall outcome: $($BundleSummary.Outcome)",
        "Resolved SQL image: $($BundleSummary.SqlServerImage)",
        '',
        '## Bundle Test Evidence',
        '',
        "Test evidence target: $($BundleSummary.TestEvidenceTarget)"
    ) + $testLines + @(
        '',
        '## Docker Targets',
        ''
    ) + $targetLines + @(
        '',
        '## Artifact Root',
        '',
        "./$artifactRootLine"
    )

    Set-Content -Path $SummaryMarkdownPath -Value ($markdown -join [Environment]::NewLine) -Encoding UTF8
    Write-JsonFile -Path $SummaryJsonPath -Value $BundleSummary
}

$selectedEnvironments = Expand-Selection -Requested $Environment -Allowed @('dev', 'stg', 'prod')
$selectedProfiles = Expand-Selection -Requested $Profile -Allowed @('http', 'https')
$resolvedSqlServerImage = Get-EnvOrDockerSecretValue -Name 'ORDERPROCESSING_SQLSERVER_IMAGE' -SecretsFilePath (Join-Path $dockerRoot '.env.local')
if (-not [string]::IsNullOrWhiteSpace($resolvedSqlServerImage)) {
    Set-Item -Path 'Env:ORDERPROCESSING_SQLSERVER_IMAGE' -Value $resolvedSqlServerImage
}
else {
    $resolvedSqlServerImage = 'mcr.microsoft.com/mssql/server:2022-CU14-ubuntu-22.04'
}

$targets = @(
    foreach ($selectedEnvironment in $selectedEnvironments) {
        foreach ($selectedProfile in $selectedProfiles) {
            [PSCustomObject] @{
                Environment = $selectedEnvironment
                Profile = $selectedProfile
                Key = "docker-$selectedEnvironment-$selectedProfile"
            }
        }
    }
)

if ($targets.Count -eq 0) {
    throw 'No Docker validation targets were selected.'
}

$testsDirectory = Join-Path $bundleRoot 'tests'
$targetResults = [System.Collections.Generic.List[object]]::new()
$testEvidenceTarget = ''
$apiTests = [PSCustomObject] @{ Outcome = 'skipped'; Summary = [PSCustomObject] @{ Passed = $null; Total = $null } ; LogPath = '' }
$integrationTests = [PSCustomObject] @{ Outcome = 'skipped'; Summary = [PSCustomObject] @{ Passed = $null; Total = $null } ; LogPath = '' }
$overallOutcome = 'passed'

foreach ($target in $targets) {
    $targetDirectory = Join-Path $bundleRoot $target.Key
    New-Item -ItemType Directory -Force -Path $targetDirectory | Out-Null

    $startupResult = Invoke-LoggedCommand -Command 'pwsh' -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $dockerRoot 'start-docker.ps1'), '-Environment', $target.Environment, '-Profile', $target.Profile, '-NoPrePull') -LogPath (Join-Path $targetDirectory 'docker-start.log') -WorkingDirectory $repoRoot

    $dockerStartupOutcome = if ($startupResult.ExitCode -eq 0) { 'passed' } else { 'failed' }
    $containerSnapshot = if ($startupResult.ExitCode -eq 0) {
        Wait-ForContainerSnapshotPassed -TargetEnvironment $target.Environment -TargetProfile $target.Profile -TargetDirectory $targetDirectory
    }
    else {
        [PSCustomObject] @{
            Outcome = 'failed'
            ContainerCount = 0
            FailedContainers = @()
            ComposePsPath = ''
            InspectPath = ''
        }
    }

    $databaseReadinessResult = if ($startupResult.ExitCode -eq 0 -and $containerSnapshot.Outcome -eq 'passed') {
        Invoke-DatabaseReadinessCheck -TargetEnvironment $target.Environment -TargetDirectory $targetDirectory
    }
    else {
        [PSCustomObject] @{
            Outcome = if ($startupResult.ExitCode -eq 0) { 'blocked' } else { 'blocked' }
            SummaryPath = ''
            Summary = [PSCustomObject] @{
                Outcome = 'blocked'
                ExpectedDatabases = @()
                FoundDatabases = @()
                LatestMigrationExpected = ''
                MasterLog = ''
                Databases = @()
            }
        }
    }

    $openPayCredentialResult = if ($startupResult.ExitCode -eq 0 -and $containerSnapshot.Outcome -eq 'passed' -and $databaseReadinessResult.Outcome -eq 'passed') {
        Test-OpenPayCredentialReadiness -TargetDirectory $targetDirectory
    }
    else {
        [PSCustomObject] @{
            Outcome = 'blocked'
            Summary = 'OpenPay credential validation was blocked because Docker startup, container health, or database readiness failed first.'
            SummaryPath = ''
            Details = [PSCustomObject] @{
                Outcome = 'blocked'
                Summary = 'OpenPay credential validation was blocked because Docker startup, container health, or database readiness failed first.'
                MerchantIdConfigured = $false
                PrivateKeyConfigured = $false
                DeviceSessionIdConfigured = $false
                Issues = @()
            }
        }
    }

    if (-not $SkipTests -and [string]::IsNullOrWhiteSpace($testEvidenceTarget) -and $startupResult.ExitCode -eq 0) {
        $testEvidenceTarget = $target.Key
        $bundleTests = Invoke-BundleTests -TestsDirectory $testsDirectory
        $apiTests = $bundleTests.Api
        $integrationTests = $bundleTests.Integration
        if ($apiTests.Outcome -eq 'failed' -or $integrationTests.Outcome -eq 'failed') {
            $overallOutcome = 'failed'
        }
    }

    $automationResult = if (-not $SkipAutomation -and $startupResult.ExitCode -eq 0 -and $containerSnapshot.Outcome -eq 'passed' -and $databaseReadinessResult.Outcome -eq 'passed' -and $openPayCredentialResult.Outcome -eq 'passed') {
        Invoke-AutomationRun -TargetKey $target.Key -TargetDirectory $targetDirectory
    }
    else {
        [PSCustomObject] @{
            Outcome = if ($SkipAutomation) { 'skipped' } else { 'blocked' }
            ExitCode = if ($SkipAutomation) { 0 } elseif ($startupResult.ExitCode -eq 0) { 0 } else { $startupResult.ExitCode }
            ReportDirectory = ''
            VerificationReportPath = ''
            SummaryPath = ''
            RawOutputPath = ''
            TenantPassCount = 0
            TenantFailCount = 0
            TenantSkippedCount = 0
            VerificationOutcome = if ($SkipAutomation) { 'skipped' } else { 'blocked' }
            VerificationSummary = if ($SkipAutomation) {
                'Automation skipped.'
            }
            elseif ($startupResult.ExitCode -ne 0) {
                'Automation blocked because Docker startup failed.'
            }
            elseif ($containerSnapshot.Outcome -ne 'passed') {
                'Automation blocked because container health validation failed.'
            }
            elseif ($databaseReadinessResult.Outcome -ne 'passed') {
                'Automation blocked because database readiness validation failed.'
            }
            else {
                $openPayCredentialResult.Summary
            }
        }
    }

    if ($dockerStartupOutcome -eq 'failed' -or $containerSnapshot.Outcome -eq 'failed' -or $databaseReadinessResult.Outcome -ne 'passed' -or $openPayCredentialResult.Outcome -eq 'blocked' -or $automationResult.Outcome -in @('failed', 'blocked')) {
        $overallOutcome = 'failed'
    }

    $targetSummary = [PSCustomObject] @{
        Target = $target.Key
        Environment = $target.Environment
        Profile = $target.Profile
        TargetDirectory = Get-RelativePathSafe -BasePath $bundleRoot -Path $targetDirectory
        DockerStartupOutcome = $dockerStartupOutcome
        StartupExitCode = $startupResult.ExitCode
        StartupLog = Get-RelativePathSafe -BasePath $bundleRoot -Path $startupResult.LogPath
        ContainerHealthOutcome = $containerSnapshot.Outcome
        ContainerCount = $containerSnapshot.ContainerCount
        ContainerSnapshot = Get-RelativePathSafe -BasePath $bundleRoot -Path $containerSnapshot.ComposePsPath
        ContainerInspect = Get-RelativePathSafe -BasePath $bundleRoot -Path $containerSnapshot.InspectPath
        FailedContainers = @($containerSnapshot.FailedContainers)
        DatabaseReadinessOutcome = $databaseReadinessResult.Outcome
        DatabaseReadinessSummary = Get-RelativePathSafe -BasePath $bundleRoot -Path $databaseReadinessResult.SummaryPath
        DatabaseReadiness = $databaseReadinessResult.Summary
        OpenPayCredentialOutcome = $openPayCredentialResult.Outcome
        OpenPayCredentialSummary = $openPayCredentialResult.Summary
        OpenPayCredentialSummaryPath = Get-RelativePathSafe -BasePath $bundleRoot -Path $openPayCredentialResult.SummaryPath
        OpenPayCredentials = $openPayCredentialResult.Details
        AutomationOutcome = $automationResult.Outcome
        AutomationLog = Get-RelativePathSafe -BasePath $bundleRoot -Path $automationResult.RawOutputPath
        AutomationReportDirectory = Get-RelativePathSafe -BasePath $bundleRoot -Path $automationResult.ReportDirectory
        AutomationSummary = Get-RelativePathSafe -BasePath $bundleRoot -Path $automationResult.SummaryPath
        VerificationOutcome = $automationResult.VerificationOutcome
        VerificationSummary = $automationResult.VerificationSummary
        VerificationReport = Get-RelativePathSafe -BasePath $bundleRoot -Path $automationResult.VerificationReportPath
        TenantPassCount = $automationResult.TenantPassCount
        TenantFailCount = $automationResult.TenantFailCount
        TenantSkippedCount = $automationResult.TenantSkippedCount
    }
    $targetResults.Add($targetSummary)

    Write-JsonFile -Path (Join-Path $targetDirectory 'target-summary.json') -Value $targetSummary

    if (-not $SkipCleanup) {
        Invoke-LoggedCommand -Command 'pwsh' -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $dockerRoot 'start-docker.ps1'), '-Environment', $target.Environment, '-Profile', $target.Profile, '-Down') -LogPath (Join-Path $targetDirectory 'docker-cleanup.log') -WorkingDirectory $repoRoot | Out-Null
    }
}

if ($SkipTests) {
    $testEvidenceTarget = 'skipped'
}
elseif ([string]::IsNullOrWhiteSpace($testEvidenceTarget)) {
    $testEvidenceTarget = 'not-run'
    $overallOutcome = 'failed'
}

$bundleSummary = [PSCustomObject] @{
    BundleId = $bundleId
    StartedUtc = $timestamp.ToUniversalTime().ToString('o')
    FinishedUtc = (Get-Date).ToUniversalTime().ToString('o')
    Outcome = $overallOutcome
    SqlServerImage = $resolvedSqlServerImage
    ArtifactRoot = $bundleRoot
    TestEvidenceTarget = $testEvidenceTarget
    ApiTests = [PSCustomObject] @{
        Outcome = $apiTests.Outcome
        Summary = $apiTests.Summary
        LogPath = Get-RelativePathSafe -BasePath $bundleRoot -Path $apiTests.LogPath
    }
    IntegrationTests = [PSCustomObject] @{
        Outcome = $integrationTests.Outcome
        Summary = $integrationTests.Summary
        LogPath = Get-RelativePathSafe -BasePath $bundleRoot -Path $integrationTests.LogPath
    }
    Targets = @($targetResults)
}

Write-BundleSummary -SummaryMarkdownPath (Join-Path $bundleRoot 'summary.md') -SummaryJsonPath (Join-Path $bundleRoot 'summary.json') -BundleSummary $bundleSummary

if ($overallOutcome -ne 'passed') {
    Write-Error "Docker validation bundle completed with failures. See $bundleRoot"
}

Write-Host "Docker validation bundle written to $bundleRoot"
