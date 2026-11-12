# Shared local-only guardrails. Dot-source; this file does not mutate Docker or disk state.
function Assert-Phase10ComposeProject {
    if ($env:COMPOSE_PROJECT_NAME -and $env:COMPOSE_PROJECT_NAME -ne 'xy-phase10') {
        throw 'COMPOSE_PROJECT_NAME must be unset or xy-phase10. Refusing to target another project.'
    }
}

function Get-Phase10SqlHostPort {
    param([hashtable]$Settings)
    if ($null -eq $Settings) {
        $environmentPort = [Environment]::GetEnvironmentVariable('LOCAL_SQL_HOST_PORT')
        if ($null -ne $environmentPort) {
            $Settings = @{ LOCAL_SQL_HOST_PORT = $environmentPort }
        }
        else {
            $Settings = Get-Phase10LocalSettings -Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'Resources/Docker/.env.local')
        }
    }
    $value = $Settings.LOCAL_SQL_HOST_PORT
    if ($null -eq $value) { return 14330 }
    $port = 0
    if (-not [int]::TryParse([string]$value, [ref]$port) -or $port -lt 1 -or $port -gt 65535) { throw 'LOCAL_SQL_HOST_PORT must be an integer from 1 to 65535.' }
    return $port
}

function New-Phase10HostSqlConnectionString {
    param([Parameter(Mandatory)][string]$Database, [Parameter(Mandatory)][string]$Password, [hashtable]$Settings)
    $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source'] = 'tcp:127.0.0.1,{0}' -f (Get-Phase10SqlHostPort -Settings $Settings)
    $builder['Initial Catalog'] = $Database
    $builder['User ID'] = 'sa'
    $builder['Password'] = $Password
    $builder['Encrypt'] = $false
    $builder['TrustServerCertificate'] = $true
    $builder['MultipleActiveResultSets'] = $true
    $builder['Connect Timeout'] = 5
    return $builder.ConnectionString
}

function Get-Phase10HostSqlMachineName {
    param([Parameter(Mandatory)][string]$ConnectionString)
    $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new($ConnectionString)
    $builder['Initial Catalog'] = 'master'
    $connection = [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = "SELECT CAST(SERVERPROPERTY('MachineName') AS nvarchar(128));"
        $command.CommandTimeout = 5
        return [string]$command.ExecuteScalar()
    }
    finally { $connection.Dispose() }
}

function Assert-Phase10HostSqlIdentity {
    param([Parameter(Mandatory)][string]$ConnectionString)
    Assert-Phase10ComposeProject
    Assert-Phase10LocalDockerEndpoint
    $port = Get-Phase10SqlHostPort
    $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new($ConnectionString)
    if ($builder.DataSource -ine "tcp:127.0.0.1,$port") { throw 'Host SQL connection must use the configured explicit TCP Docker endpoint.' }
    $ids = @(& docker ps --filter 'label=com.docker.compose.project=xy-phase10' --filter 'label=com.docker.compose.service=sql-server' --format '{{.ID}}')
    if ($LASTEXITCODE -ne 0 -or $ids.Count -ne 1 -or -not $ids[0]) { throw 'Expected exactly one running xy-phase10 application SQL container.' }
    $expectedMachine = & docker inspect --format '{{.Config.Hostname}}' $ids[0]
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($expectedMachine)) { throw 'Cannot establish Docker SQL container hostname.' }
    $bindings = @(& docker port $ids[0] '1433/tcp')
    if ($LASTEXITCODE -ne 0 -or "127.0.0.1:$port" -notin $bindings) { throw 'Docker SQL published port does not match the configured loopback host port.' }
    $actualMachine = $null
    foreach ($attempt in 1..12) {
        try { $actualMachine = Get-Phase10HostSqlMachineName -ConnectionString $ConnectionString; break }
        catch {
            if ($attempt -eq 12) { throw 'Cannot verify Docker SQL server identity. Host-side database work is blocked; connection details omitted.' }
            Start-Sleep -Seconds 2
        }
    }
    if ([string]::IsNullOrWhiteSpace($actualMachine) -or $actualMachine.Trim() -ine ([string]$expectedMachine).Trim()) {
        throw 'Host SQL endpoint reaches a different SQL server than the xy-phase10 container. Host-side database work is blocked.'
    }
}

function Assert-Phase10PortOwnership {
    param([int[]]$Ports)
    Assert-Phase10ComposeProject
    Assert-Phase10LocalDockerEndpoint
    foreach ($port in $Ports) {
        $ids = @(& docker ps --filter "publish=$port" --format '{{.ID}}')
        if ($LASTEXITCODE -ne 0) { throw "Cannot inspect port $port; no containers were stopped." }
        foreach ($id in $ids) {
            if ([string]::IsNullOrWhiteSpace($id)) { continue }
            $owner = & docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' $id
            if ($LASTEXITCODE -ne 0) { throw "Cannot establish container ownership on port $port." }
            if (([string]$owner).Trim() -ne 'xy-phase10') {
                throw "Port $port belongs to container $id outside xy-phase10. Stop it yourself or change its ports; nothing was removed."
            }
        }
    }
}

function Assert-Phase10LocalDockerEndpoint {
    $endpoint = if ($env:DOCKER_HOST -and -not $env:DOCKER_CONTEXT) { $env:DOCKER_HOST } else {
        $result = & docker context inspect --format '{{.Endpoints.docker.Host}}'
        if ($LASTEXITCODE -ne 0) { throw 'Cannot establish the Docker endpoint; no runtime changes are allowed.' }
        ([string]$result).Trim()
    }
    if ($endpoint -notin @('npipe:////./pipe/docker_engine', 'npipe:////./pipe/dockerDesktopLinuxEngine')) {
        throw 'This operation requires the local Docker Desktop named-pipe endpoint. Remote Docker hosts are forbidden.'
    }
}

function Get-Phase10DockerDiskLocation {
    $settingsPath = Join-Path $env:APPDATA 'Docker/settings-store.json'
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        throw 'Docker settings-store.json is unavailable. Verify Disk image location in Docker Desktop.'
    }
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    # Docker Desktop versions use different property names; never dump the full settings file.
    foreach ($key in @('CustomWslDistroDir', 'customWslDistroDir', 'dataFolder', 'DataFolder')) {
        if ($settings.$key) { return [System.IO.Path]::GetFullPath([string]$settings.$key) }
    }
    throw 'Cannot determine the configured Docker disk location. Verify it in Docker Desktop; refusing to guess.'
}

function Get-Phase10DriveState {
    param([Parameter(Mandatory)][string]$Path)
    $root = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($Path))
    $drive = [System.IO.DriveInfo]::new($root)
    if (-not $drive.IsReady) { throw "Docker storage drive $root is unavailable." }
    [pscustomobject]@{ Root = $root; FileSystem = $drive.DriveFormat; FreeBytes = $drive.AvailableFreeSpace; TotalBytes = $drive.TotalSize }
}

function Assert-Phase10StorageCapacity {
    param([Parameter(Mandatory)][string]$Path, [switch]$ForBuild)
    $state = Get-Phase10DriveState -Path $Path
    if ($state.FileSystem -ne 'NTFS') { throw "Docker storage drive $($state.Root) must be NTFS for this Windows setup. Do not format it automatically." }
    if ($ForBuild -and $state.FreeBytes -lt 50GB) {
        throw "Less than 50 GiB free on $($state.Root). Full build blocked."
    }
    if ($state.FreeBytes -lt 100GB) { Write-Warning "Less than 100 GiB free on $($state.Root). Review Docker storage before continuing." }
    $state
}

function Assert-Phase10VolumeOwnership {
    foreach ($name in @('xy-phase10_phase10-sql-data', 'xy-phase10_phase10-azurite-data')) {
        $names = @(& docker volume ls --filter "name=$name" --format '{{.Name}}')
        if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect project volumes; reset blocked.' }
        if ($name -in $names) {
            $owner = & docker volume inspect --format '{{index .Labels "com.docker.compose.project"}}' $name
            if ($LASTEXITCODE -ne 0 -or ([string]$owner).Trim() -ne 'xy-phase10') { throw "Volume $name has unverified ownership; reset blocked." }
        }
    }
}

function Get-Phase10LocalSettings {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw 'Missing Resources/Docker/.env.local. Configure local-only secrets first.' }
    $values = @{}
    # Match Compose precedence: example, local file, then process environment.
    $paths = @()
    if (Test-Path -LiteralPath "$Path.example") { $paths += "$Path.example" }
    $paths += $Path
    foreach ($settingsFile in $paths) {
        foreach ($line in Get-Content -LiteralPath $settingsFile) {
            if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$') {
                $values[$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'")
            }
        }
    }
    foreach ($key in @($values.Keys)) {
        $override = [Environment]::GetEnvironmentVariable($key)
        if ($null -ne $override) { $values[$key] = $override }
    }
    return $values
}

function Get-Phase10ComposeDedicatedTenantDatabaseMap {
    $compose = Join-Path (Split-Path -Parent $PSScriptRoot) 'compose/docker-compose.phase10.yml'
    if (-not (Test-Path -LiteralPath $compose)) { throw 'Phase 10 Compose topology is unavailable.' }
    $content = Get-Content -LiteralPath $compose -Raw
    $map = @{}
    foreach ($match in [regex]::Matches($content, 'DedicatedTenantConnectionStrings__(?<tenant>[A-Za-z0-9_-]+)\s*:\s*Server=sql-server,1433;Database=(?<database>[A-Za-z0-9_]+);', [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        $tenant = $match.Groups['tenant'].Value
        $database = $match.Groups['database'].Value
        if ($map.ContainsKey($tenant) -and $map[$tenant] -ne $database) { throw "Dedicated tenant '$tenant' has conflicting local database mappings." }
        $map[$tenant] = $database
    }
    return $map
}

function Resolve-Phase10LocalTenantDatabaseFromRegistry {
    param(
        [Parameter(Mandatory)][string]$TenantCode,
        [Parameter(Mandatory)][string]$TenantTier,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][hashtable]$DedicatedDatabaseMap
    )
    if ($TenantCode -notmatch '^[A-Za-z0-9_-]{1,64}$') { throw 'Tenant code is malformed.' }
    if ($Status -ne 'Active') { throw "Tenant '$TenantCode' is not active." }
    if ($TenantTier -eq 'SharedPool') { return 'OrderProcessingSystem_Dev' }
    if ($TenantTier -ne 'Dedicated') { throw "Tenant '$TenantCode' has unsupported tier '$TenantTier'." }
    if (-not $DedicatedDatabaseMap.ContainsKey($TenantCode)) { throw "Active dedicated tenant '$TenantCode' has no project-local database mapping." }
    $database = [string]$DedicatedDatabaseMap[$TenantCode]
    if ($database -notmatch '^OrderProcessingSystem_[A-Za-z0-9_]+$') { throw "Dedicated tenant '$TenantCode' has an invalid project-local database mapping." }
    return $database
}

function Resolve-Phase10LocalTenantDatabase {
    param([Parameter(Mandatory)][string]$TenantCode, [Parameter(Mandatory)][hashtable]$Settings)
    if ($TenantCode -notmatch '^[A-Za-z0-9_-]{1,64}$') { throw 'Tenant code is malformed.' }
    $connectionString = New-Phase10HostSqlConnectionString -Database 'OrderProcessingSystem_Dev' -Password $Settings.LOCAL_SQL_PASSWORD -Settings $Settings
    Assert-Phase10HostSqlIdentity -ConnectionString $connectionString
    $connection = [System.Data.SqlClient.SqlConnection]::new($connectionString)
    try {
        $connection.Open(); $command = $connection.CreateCommand()
        $command.CommandText = 'SELECT TenantTier,Status FROM dbo.Tenants WHERE Code=@code;'
        [void]$command.Parameters.AddWithValue('@code', $TenantCode)
        $reader = $command.ExecuteReader()
        if (-not $reader.Read()) { throw "Tenant '$TenantCode' was not found in the shared registry." }
        $tier = $reader.GetString(0); $status = $reader.GetString(1); $reader.Dispose()
        $map = Get-Phase10ComposeDedicatedTenantDatabaseMap
        return Resolve-Phase10LocalTenantDatabaseFromRegistry -TenantCode $TenantCode -TenantTier $tier -Status $status -DedicatedDatabaseMap $map
    } finally { $connection.Dispose() }
}

function Assert-Phase10LocalSettings {
    param([Parameter(Mandatory)][hashtable]$Settings, [switch]$FullStack)
    $required = @('LOCAL_SQL_PASSWORD', 'KEYCLOAK_TENANT_ADMIN_PASSWORD', 'LOCAL_KEYCLOAK_BACKEND_CLIENT_SECRET')
    if ($FullStack) { $required += 'SERVICEBUS_EMULATOR_SQL_PASSWORD' }
    foreach ($key in $required) {
        $value = $Settings[$key]
        if ([string]::IsNullOrWhiteSpace($value) -or $value -match '^<.*>$') { throw "Local setting $key is missing or still a placeholder. Values are not logged." }
    }
    if ($FullStack -and ($Settings.LOCAL_SERVICEBUS_ENABLED -ne 'true' -or $Settings.SERVICEBUS_EMULATOR_ACCEPT_EULA -ne 'Y')) {
        throw 'Full-stack setup requires LOCAL_SERVICEBUS_ENABLED=true and explicit SERVICEBUS_EMULATOR_ACCEPT_EULA=Y in .env.local.'
    }
    # Do not silently replace real-provider testing with deterministic adapters.
    if ($Settings.LOCAL_DETERMINISTIC_PAYMENT_ADAPTERS -ne 'true') {
        foreach ($key in @('LOCAL_OPENPAY_MERCHANT_ID', 'LOCAL_OPENPAY_PUBLIC_KEY', 'LOCAL_OPENPAY_PRIVATE_KEY', 'LOCAL_RAZORPAY_MERCHANT_ID', 'LOCAL_RAZORPAY_PRIVATE_KEY')) {
            if ([string]::IsNullOrWhiteSpace($Settings[$key]) -or $Settings[$key] -match '^<.*>$') { throw "Real-provider mode needs $key. Configure it without printing credentials." }
        }
        if ($Settings.LOCAL_RAZORPAY_MERCHANT_ID -notlike 'rzp_test_*') { throw 'Local sandbox testing requires a Razorpay rzp_test_ key. Live or unknown keys are forbidden.' }
    }
}

function Initialize-Phase10LogRedaction {
    param([hashtable]$Settings)
    $script:phase10LogSecrets = @($Settings.Keys | Where-Object { $_ -match 'PASSWORD|SECRET|KEY|TOKEN|CONNECTION_STRING' } |
        ForEach-Object { [string]$Settings[$_] } |
        Where-Object { $_.Length -ge 4 -and $_ -notmatch '^<.*>$' } |
        Sort-Object -Unique -CaseSensitive | Sort-Object { $_.Length } -Descending)
}

function Protect-Phase10Log {
    param([Parameter(ValueFromPipeline)]$InputObject)
    process {
        $line = [string]$InputObject
        foreach ($value in $script:phase10LogSecrets) { $line = $line.Replace($value, '[REDACTED]') }
        $line
    }
}

function Confirm-Phase10Reset {
    param([Parameter(Mandatory)][scriptblock]$Approve)
    Assert-Phase10ComposeProject
    if (-not (& $Approve)) { throw 'Reset cancelled; no Docker data was changed.' }
}

function Invoke-Phase10DockerReadOnly {
    param([Parameter(Mandatory)][string[]]$Arguments, [int]$TimeoutSeconds = 30)
    $allowed = @('version', 'info', 'ps', 'images', 'system df', 'volume ls', 'buildx du', 'buildx ls', 'buildx inspect', 'compose version')
    $verb = $Arguments[0]
    if ($verb -in @('system', 'volume', 'buildx', 'compose')) { $verb = "$verb $($Arguments[1])" }
    if ($verb -notin $allowed) { throw 'This diagnostic helper only accepts read-only Docker commands.' }
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = (Get-Command docker -ErrorAction Stop).Source
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            $process.WaitForExit()
            throw "Docker diagnostic '$verb' exceeded $TimeoutSeconds seconds. No Docker data was changed."
        }
        if ($process.ExitCode -ne 0) { throw "Docker diagnostic '$verb' failed. Check Docker Desktop and access from your terminal; raw output is omitted to avoid credential exposure." }
        return $stdout.GetAwaiter().GetResult().Trim()
    }
    finally { $process.Dispose() }
}
