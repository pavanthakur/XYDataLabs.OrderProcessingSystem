#Requires -Version 7.0
# Dependency-free regression tests: mocks only; never contacts or modifies Docker.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'phase10-docker-safety.ps1')
. (Join-Path $PSScriptRoot 'integration-test-database.ps1')
$failures = 0
$passed = 0
$previousProject = $env:COMPOSE_PROJECT_NAME
$previousDockerHost = $env:DOCKER_HOST
$previousDockerContext = $env:DOCKER_CONTEXT
$previousSqlPort = $env:LOCAL_SQL_HOST_PORT
$env:COMPOSE_PROJECT_NAME = ''
$env:DOCKER_HOST = ''
$env:DOCKER_CONTEXT = ''
$env:LOCAL_SQL_HOST_PORT = '14330'

function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    try { & $Body; $script:passed++; Write-Host "PASS $Name" }
    catch { $script:failures++; Write-Host "FAIL $Name : $($_.Exception.Message)" }
}
function Assert-True { param($Value, [string]$Message = 'Assertion failed'); if (-not $Value) { throw $Message } }
function Assert-Throws {
    param([scriptblock]$Body, [string]$Pattern)
    $caught = $null
    try { & $Body } catch { $caught = $_.Exception.Message }
    Assert-True ($caught -and $caught -match $Pattern) "Expected failure matching $Pattern"
}
function docker {
    $script:dockerCalls += ,@($args)
    $global:LASTEXITCODE = 0
    if ($script:dockerUnavailable) { $global:LASTEXITCODE = 1; return }
    if ($args[0] -eq 'context') { return 'npipe:////./pipe/dockerDesktopLinuxEngine' }
    if ($args[0] -eq 'ps') { return $script:containerIds }
    if ($args[0] -eq 'inspect') {
        if ($args[2] -eq '{{.Config.Hostname}}') { return $script:sqlContainerHostname }
        return $script:containerOwner
    }
    if ($args[0] -eq 'port') { return $script:sqlBinding }
    if ($args[0] -eq 'volume' -and $args[1] -eq 'ls') { return $script:volumeNames }
    if ($args[0] -eq 'volume' -and $args[1] -eq 'inspect') { return $script:volumeOwner }
    throw "Unexpected Docker call: $($args -join ' ')"
}
function Get-Phase10DriveState { param([string]$Path); if ($script:driveMissing) { throw 'Storage drive is unavailable' }; return $script:driveState }
function Get-Phase10HostSqlMachineName { param([string]$ConnectionString); return $script:sqlMachine }

try {
    $dockerCalls = @(); $dockerUnavailable = $false; $containerIds = @(); $volumeNames = @()
    Test-Case 'No port conflict makes read-only calls only' {
        Assert-Phase10PortOwnership -Ports @(1433, 5080)
        Assert-True ($dockerCalls.Count -eq 3)
    }
    Test-Case 'Own project container is accepted without stopping it' {
        $script:containerIds = @('test-id'); $script:containerOwner = 'xy-phase10'
        Assert-Phase10PortOwnership -Ports @(1433)
    }
    Test-Case 'Foreign project container fails without mutation' {
        $script:dockerCalls = @(); $script:containerOwner = 'another-project'
        Assert-Throws { Assert-Phase10PortOwnership -Ports @(1433) } 'outside xy-phase10'
        Assert-True (@($dockerCalls | Where-Object { $_[0] -notin @('context', 'ps', 'inspect') }).Count -eq 0)
    }
    Test-Case 'Unlabelled legacy container fails safely' {
        $script:containerOwner = ''
        Assert-Throws { Assert-Phase10PortOwnership -Ports @(1433) } 'outside xy-phase10'
    }
    Test-Case 'Unavailable daemon fails without continuing' {
        $script:dockerUnavailable = $true
        Assert-Throws { Assert-Phase10PortOwnership -Ports @(1433) } 'Cannot establish'
        $script:dockerUnavailable = $false
    }
    Test-Case 'Project override is rejected' {
        $env:COMPOSE_PROJECT_NAME = 'production'
        Assert-Throws { Assert-Phase10ComposeProject } 'Refusing'
        $env:COMPOSE_PROJECT_NAME = ''
    }
    Test-Case 'Integration run names create distinct paired databases' {
        $first = Get-IntegrationTestDatabaseNames -RunId ([Guid]::NewGuid().ToString('N'))
        $second = Get-IntegrationTestDatabaseNames -RunId ([Guid]::NewGuid().ToString('N'))
        $expectedDedicated = "$($first.shared)_TenantC"
        Assert-True ($first.shared -ne $second.shared -and $first.dedicated -eq $expectedDedicated) 'Run database pair contract is not unique.'
        Assert-IntegrationTestDatabaseNames -SharedDatabase $first.shared -DedicatedDatabase $first.dedicated
    }
    Test-Case 'Application, system, and malformed integration targets fail before SQL access' {
        Assert-Throws { Assert-IntegrationTestDatabaseNames -SharedDatabase 'OrderProcessingSystem_Dev' -DedicatedDatabase 'OrderProcessingSystem_TenantC_Dev' } 'run-owned'
        Assert-Throws { Assert-IntegrationTestDatabaseNames -SharedDatabase 'master' -DedicatedDatabase 'master_TenantC' } 'run-owned'
        Assert-Throws { Assert-IntegrationTestDatabaseNames -SharedDatabase 'OrderProcessingSystem_Integration_123' -DedicatedDatabase 'anything' } 'run-owned'
    }
    Test-Case 'Remote Docker host is rejected before any runtime mutation' {
        $env:DOCKER_HOST = 'tcp://remote.invalid:2376'
        Assert-Throws { Assert-Phase10LocalDockerEndpoint } 'Remote Docker hosts are forbidden'
        $env:DOCKER_HOST = ''
    }
    Test-Case 'Reset cancellation performs no Docker calls' {
        $script:dockerCalls = @()
        Assert-Throws { Confirm-Phase10Reset -Approve { $false } } 'cancelled'
        Assert-True ($dockerCalls.Count -eq 0)
    }
    Test-Case 'Reset approval is explicit' { Confirm-Phase10Reset -Approve { $true } }
    Test-Case 'ShouldProcess confirmation binds correctly through reset helper' {
        function Invoke-TestConfirmation {
            [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
            param()
            Confirm-Phase10Reset -Approve { $PSCmdlet.ShouldProcess('mock project', 'mock reset') }
        }
        Invoke-TestConfirmation -Confirm:$false
        Assert-Throws { Invoke-TestConfirmation -WhatIf } 'cancelled'
    }
    Test-Case 'Foreign SQL volume blocks reset' {
        $script:volumeNames = @('xy-phase10_phase10-sql-data'); $script:volumeOwner = 'another-project'
        Assert-Throws { Assert-Phase10VolumeOwnership } 'unverified ownership'
    }
    Test-Case 'Owned volumes are accepted' {
        $script:volumeOwner = 'xy-phase10'
        Assert-Phase10VolumeOwnership
    }
    Test-Case 'Docker host SQL defaults to 14330, supports override, and rejects invalid ports' {
        Assert-True ((Get-Phase10SqlHostPort -Settings @{}) -eq 14330)
        Assert-True ((Get-Phase10SqlHostPort -Settings @{LOCAL_SQL_HOST_PORT='14331'}) -eq 14331)
        foreach ($value in @('', 'not-a-port', '0', '65536')) {
            Assert-Throws { Get-Phase10SqlHostPort -Settings @{LOCAL_SQL_HOST_PORT=$value} } 'integer'
        }
    }
    Test-Case 'Host connection uses explicit loopback TCP and safely encodes passwords' {
        $canary = 'local;test=value'
        $connectionText = New-Phase10HostSqlConnectionString -Database 'master' -Password $canary -Settings @{}
        $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new($connectionText)
        Assert-True ($builder.DataSource -eq 'tcp:127.0.0.1,14330' -and $builder.Password -eq $canary)
    }
    Test-Case 'Matching physical SQL identity is accepted' {
        $script:containerIds = @('sql-test-id'); $script:sqlContainerHostname = 'docker-sql-test'
        $script:sqlMachine = 'docker-sql-test'; $script:sqlBinding = '127.0.0.1:14330'
        $connectionText = New-Phase10HostSqlConnectionString -Database 'master' -Password 'canary' -Settings @{}
        Assert-Phase10HostSqlIdentity -ConnectionString $connectionText
    }
    Test-Case 'Native Windows SQL identity is rejected without mutation' {
        $script:dockerCalls = @(); $script:sqlMachine = 'native-windows-sql'
        $connectionText = New-Phase10HostSqlConnectionString -Database 'master' -Password 'canary' -Settings @{}
        Assert-Throws { Assert-Phase10HostSqlIdentity -ConnectionString $connectionText } 'different SQL server'
        Assert-True (@($dockerCalls | Where-Object { $_[0] -notin @('context','ps','inspect','port') }).Count -eq 0)
    }
    Test-Case 'Wrong publication and old 1433 host endpoints are rejected' {
        $script:sqlBinding = '127.0.0.1:1433'
        $connectionText = New-Phase10HostSqlConnectionString -Database 'master' -Password 'canary' -Settings @{}
        Assert-Throws { Assert-Phase10HostSqlIdentity -ConnectionString $connectionText } 'published port'
        Assert-Throws { Assert-Phase10HostSqlIdentity -ConnectionString ($connectionText.Replace(',14330', ',1433')) } 'explicit TCP'
    }
    Test-Case 'TCP-prefixed localhost still requires host-mapping opt-in' {
        . (Join-Path $PSScriptRoot 'assert-docker-runtime-sql-guardrail.ps1')
        $connectionText = New-Phase10HostSqlConnectionString -Database 'OrderProcessingSystem_Dev' -Password 'canary' -Settings @{}
        Assert-Throws { Assert-DockerRuntimeSqlGuardrail -ScriptName 'test' -ConnectionString $connectionText } 'host-local'
        Assert-DockerRuntimeSqlGuardrail -ScriptName 'test' -ConnectionString $connectionText -AllowHostMappedDockerSql
    }
    Test-Case 'Docker test runner validates SQL identity before creating isolated test databases' {
        $source = Get-Content (Join-Path $PSScriptRoot 'run-integration-tests-docker.ps1') -Raw
        Assert-True ($source.IndexOf('Assert-Phase10HostSqlIdentity') -lt $source.IndexOf('$env:PHASE10_INTEGRATION_PROVISIONING_CONNECTION_STRING ='))
        Assert-True ($source -notmatch '\$env:ORDERPROCESSING_TEST_CONNECTION_STRING\s*=')
        Assert-True ($source -notmatch 'Write-Host.*\$connectionString')
        Assert-True ($source -notmatch 'Server=localhost,1433')
    }
    $driveState = [pscustomobject]@{ Root = 'G:\'; FileSystem = 'NTFS'; FreeBytes = 471GB; TotalBytes = 476GB }
    Test-Case 'Sufficient NTFS space permits full build' { Assert-Phase10StorageCapacity -Path 'G:\DockerStorage' -ForBuild | Out-Null }
    Test-Case 'Low free space blocks build' {
        $script:driveState.FreeBytes = 49GB
        Assert-Throws { Assert-Phase10StorageCapacity -Path 'G:\DockerStorage' -ForBuild } '50 GiB'
    }
    Test-Case 'Warning threshold is visible' {
        $script:driveState.FreeBytes = 75GB
        $warningOutput = @(Assert-Phase10StorageCapacity -Path 'G:\DockerStorage' -ForBuild 3>&1)
        Assert-True (@($warningOutput | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count -eq 1)
    }
    Test-Case 'Incompatible filesystem is rejected' {
        $script:driveState.FreeBytes = 471GB; $script:driveState.FileSystem = 'exFAT'
        Assert-Throws { Assert-Phase10StorageCapacity -Path 'G:\DockerStorage' } 'NTFS'
        $script:driveState.FileSystem = 'NTFS'
    }
    Test-Case 'Missing drive is rejected' {
        $script:driveMissing = $true
        Assert-Throws { Assert-Phase10StorageCapacity -Path 'G:\DockerStorage' } 'unavailable'
        $script:driveMissing = $false
    }
    Test-Case 'Missing local settings fails clearly' {
        Assert-Throws { Get-Phase10LocalSettings -Path (Join-Path $repoRoot '.tmp/nonexistent-phase10-test.env') } 'Missing'
    }
    Test-Case 'Placeholder validation never echoes the supplied value' {
        $canary = '<DO-NOT-LOG-THIS-VALUE>'
        $errorText = ''
        try { Assert-Phase10LocalSettings -Settings @{ LOCAL_SQL_PASSWORD = $canary } } catch { $errorText = $_.Exception.Message }
        Assert-True ($errorText -match 'LOCAL_SQL_PASSWORD' -and -not $errorText.Contains($canary))
    }
    Test-Case 'Log redaction removes distinct same-length credentials' {
        $firstCanary = 'same-length-A'; $secondCanary = 'same-length-B'
        Initialize-Phase10LogRedaction -Settings @{ LOCAL_SQL_PASSWORD = $firstCanary; LOCAL_KEYCLOAK_BACKEND_CLIENT_SECRET = $secondCanary }
        $result = "native failure $firstCanary $secondCanary" | Protect-Phase10Log
        Assert-True (-not $result.Contains($firstCanary) -and -not $result.Contains($secondCanary))
        Assert-True ($result.Contains('[REDACTED]'))
    }
    Test-Case 'Full stack requires explicit messaging enablement and EULA' {
        $settings = @{ LOCAL_SQL_PASSWORD = 'canary'; KEYCLOAK_TENANT_ADMIN_PASSWORD = 'canary'; LOCAL_KEYCLOAK_BACKEND_CLIENT_SECRET = 'canary'; SERVICEBUS_EMULATOR_SQL_PASSWORD = 'canary' }
        Assert-Throws { Assert-Phase10LocalSettings -Settings $settings -FullStack } 'explicit'
    }
    Test-Case 'Mutating commands are forbidden by diagnostic helper' {
        Assert-Throws { Invoke-Phase10DockerReadOnly -Arguments @('system', 'prune') } 'read-only'
    }
    Test-Case 'Startup WhatIf never touches Docker' {
        $script:dockerCalls = @()
        & (Join-Path $PSScriptRoot 'start-phase10-docker-dev.ps1') -ResetData -WhatIf
        Assert-True ($dockerCalls.Count -eq 0)
    }
    Test-Case 'E2E hook starts the stack before requiring a full-stack storage report' {
        $hook = Get-Content (Join-Path $PSScriptRoot 'run-phase10-docker-dev-e2e-hook.ps1') -Raw
        $startIndex = $hook.IndexOf('if (-not $ReuseExistingStack)')
        $beforeReportIndex = $hook.IndexOf("-ManifestPath (Join-Path `$runRoot 'storage-before.json')")
        $e2eIndex = $hook.IndexOf('-PaymentSuite $PaymentSuite')
        Assert-True ($startIndex -ge 0 -and $beforeReportIndex -gt $startIndex -and $e2eIndex -gt $beforeReportIndex) 'Fresh runs must start all services before the strict 13-container pre-test report.'
    }
    Test-Case 'Startup has no unconditional teardown or forced container removal' {
        $source = Get-Content (Join-Path $PSScriptRoot 'start-phase10-docker-dev.ps1') -Raw
        $bootstrapSource = Get-Content (Join-Path $PSScriptRoot 'invoke-phase10-database-bootstrap.ps1') -Raw
        Assert-True ($source -notmatch 'Stop-ContainersOnPort|docker (kill|stop|rm|rmi)|cached local Functions image|docker-compose-preflight-down')
        Assert-True ($source -match 'Confirm-Phase10Reset' -and $source -match 'if \(\$ResetData\)')
        Assert-True ($source -match 'build.*azurite' -and $source -match '--no-cache' -and $source -match 'No stale-image fallback')
        Assert-True ($source -match '\$appUpArguments = @\(' -and $source -match '\$functionUpArguments = @\(' -and $source -notmatch '@appUpBuildArg|@functionBuildArg') 'Up arguments must be constructed as arrays so PowerShell does not split scalar flags into service names.'
        Assert-True ($source -match '\$buildArgs = @\(' -and $bootstrapSource -match '\$buildOption = @\(\)' -and $bootstrapSource -notmatch '\$buildOption = if') 'Compose build options must be built as arrays, not single-item if-expression scalars.'
    }
    Test-Case 'Compose pins project, SQL storage, and bounded logging for every service' {
        $source = Get-Content (Join-Path $repoRoot 'compose/docker-compose.phase10.yml') -Raw
        Assert-True ($source -match '^name: xy-phase10')
        Assert-True ($source -match 'phase10-sql-data:/var/opt/mssql')
        Assert-True ($source.Contains('127.0.0.1:${LOCAL_SQL_HOST_PORT:-14330}:1433'))
        Assert-True ($source -match 'max-size: "10m"' -and $source -match 'max-file: "3"')
        Assert-True ($source -match 'org\.xydatalabs\.project: xy-phase10' -and $source -match 'org\.xydatalabs\.image-kind: application')
        Assert-True (([regex]::Matches($source, '    logging: \*local-logging')).Count -eq 13)
    }
    Test-Case 'Storage reporting is allowlisted and cannot serialize credentials' {
        $source = Get-Content (Join-Path $PSScriptRoot 'inspect-phase10-docker-storage.ps1') -Raw
        Assert-True ($source -notmatch '\$localSettings\s*\|\s*ConvertTo-Json|\$settings\s*\|\s*ConvertTo-Json')
        Assert-True ($source -match 'refusing to overwrite' -and $source -match 'resetProcedureVerified = \$false')
    }
    Test-Case 'Integration runner never exports the application DB as its fixture target' {
        $runner = Get-Content (Join-Path $PSScriptRoot 'invoke-integration-tests-isolated.ps1') -Raw
        $fixture = Get-Content (Join-Path $repoRoot 'tests/XYDataLabs.OrderProcessingSystem.Integration.Tests/Infrastructure/SqlServerFixture.cs') -Raw
        $recovery = Get-Content (Join-Path $PSScriptRoot 'cleanup-integration-test-databases.ps1') -Raw
        $databaseLease = Get-Content (Join-Path $PSScriptRoot 'integration-test-database.ps1') -Raw
        Assert-True ($runner -match 'Initialize-IntegrationTestDatabasePair' -and $runner -match '\$lease\.SharedConnectionString')
        Assert-True ($runner -match 'Get-ProviderMetadataFingerprint' -and $runner -match 'OrderProcessingSystem_TenantC_Dev' -and $runner -match 'unchanged = \$metadataUnchanged')
        Assert-True ($fixture -match 'OrderProcessingSystem_Integration_\[0-9a-f\]\{32\}' -and $fixture -match 'AssertRunOwnedDatabasePairExistsAsync')
        Assert-True ($recovery -match 'ShouldProcess' -and $recovery -match 'createdByRun' -and $recovery -match 'serverMachine')
        Assert-True ($recovery -notmatch 'docker (system prune|volume prune|rm)')
        Assert-True ($databaseLease -match 'DB_ID\(@database\) IS NULL THEN 0 ELSE 1' -and $databaseLease -match 'setup-failed-and-cleaned') 'SQL DBNull results must not be mistaken for existing databases; setup failures clean only the run-owned pair.'
    }
    Test-Case 'Build context excludes local credentials and disposable caches' {
        $patterns = Get-Content (Join-Path $repoRoot '.dockerignore')
        foreach ($pattern in @('**/.env.*', '**/.azure-cli', '**/.aws', '**/.docker', '**/.codex', '**/.venv', '**/.tmp*', '**/*.log')) {
            Assert-True ($pattern -in $patterns) "Missing build-context exclusion: $pattern"
        }
    }
    Test-Case 'Payment fixtures retain exact state and never rewrite provider credentials' {
        $source=Get-Content (Join-Path $PSScriptRoot 'local-payment-test-state.ps1') -Raw
        Assert-True ($source -match 'FileMode\]::CreateNew' -and $source -match 'Restore-Snapshot' -and $source -match 'Assert-Phase10HostSqlIdentity')
        Assert-True ($source -match 'version=2' -and $source -match 'registryRoute' -and $source -match 'businessDatabase' -and $source -match 'Prepared shared registry route did not persist')
        Assert-True ($source -notmatch 'UPDATE.+PrivateKey|UPDATE.+MerchantId|DELETE FROM|TRUNCATE TABLE')
        Assert-True ($source.IndexOf('Save-Manifest $snapshot', $source.IndexOf('$snapshot=[ordered]')) -lt $source.IndexOf("'UPDATE dbo.Tenants SET PaymentProviderCode=@provider"))
    }
    Test-Case 'Sandbox configuration is not silently replaced by localhost mocks' {
        $source=Get-Content (Join-Path $repoRoot 'frontend/apps/web/src/pages/PaymentPage.tsx') -Raw
        Assert-True ($source -notmatch 'createLocalRazorpayMockConstructor|if \(isLocalhost')
        Assert-True ($source -match 'adapterMode === "deterministic"')
    }
    Test-Case 'Additional payment safety scripts parse' {
        foreach($file in @('local-payment-test-state.ps1','run-local-payment-tests.ps1','sanitize-payment-artifacts.ps1','verify-local-payment-state.ps1','test-local-messaging.ps1','test-phase10-docker-persistence.ps1')) {
            $parseErrors=$null;$tokens=$null
            $null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file),[ref]$tokens,[ref]$parseErrors)
            Assert-True (@($parseErrors).Count-eq 0) "Parse failure in $file"
        }
    }
    Test-Case 'All modified safety scripts parse' {
        foreach ($file in @('phase10-docker-safety.ps1', 'inspect-phase10-docker-storage.ps1', 'maintain-phase10-docker-storage.ps1', 'integration-test-database.ps1', 'invoke-integration-tests-isolated.ps1', 'cleanup-integration-test-databases.ps1', 'run-integration-tests-local.ps1', 'inspect-phase10-docker-storage.ps1', 'retain-phase10-docker-storage.ps1', 'start-phase10-docker-dev.ps1', 'invoke-phase10-database-bootstrap.ps1', 'run-phase10-docker-dev-e2e-hook.ps1', 'run-phase10-local-container-stack-end-to-end.ps1', 'run-phase10-docker-nfr-proof.ps1', 'run-integration-tests-docker.ps1', 'run-phase10-local-nfr-proof.ps1', 'start-local-api-profile.ps1', 'verify-payment-run-physical.ps1', 'wait-phase10-local-container-stack-ready.ps1', 'assert-docker-runtime-sql-guardrail.ps1')) {
            $parseErrors = $null; $tokens = $null
            $null = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file), [ref]$tokens, [ref]$parseErrors)
            Assert-True (@($parseErrors).Count -eq 0) "Parse failure in $file"
        }
    }
    Test-Case 'Retention is separately gated, never purges, and checks exact offline paths' {
        $source = Get-Content (Join-Path $PSScriptRoot 'retain-phase10-docker-storage.ps1') -Raw
        Assert-True ($source -match 'if \(\[bool\]\$ResetProcedureVerified -eq \[bool\]\$ReinstallProcedureApproved\)' -and $source -match 'ShouldProcess')
        Assert-True ($source -match 'ReparsePoint' -and $source -match 'File\]::Open' -and $source -match 'Get-Process')
        Assert-True ($source -notmatch 'Remove-Item|wsl --unregister|docker system prune')
        Assert-True ($source.IndexOf('if ([bool]$ResetProcedureVerified -eq [bool]$ReinstallProcedureApproved)') -lt $source.IndexOf('Move-Item -LiteralPath'))
    }
}
finally {
    $env:COMPOSE_PROJECT_NAME = $previousProject
    $env:DOCKER_HOST = $previousDockerHost
    $env:DOCKER_CONTEXT = $previousDockerContext
    $env:LOCAL_SQL_HOST_PORT = $previousSqlPort
}
Write-Host "Docker safety tests: $passed passed; $failures failed (mocks only)."
if ($failures) { exit 1 }
