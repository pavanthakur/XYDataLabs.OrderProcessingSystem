#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('BeforeSwitch', 'AfterSwitch', 'Report')]
    [string]$Mode = 'BeforeSwitch',
    [string]$TargetPath = 'G:\DockerStorage\DockerDesktopWSL',
    [string]$ManifestPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'phase10-docker-safety.ps1')
$repoRoot = Split-Path -Parent $PSScriptRoot
$report = [ordered]@{
    schemaVersion = 1
    capturedUtc = [DateTime]::UtcNow.ToString('o')
    mode = $Mode
    targetPath = [IO.Path]::GetFullPath($TargetPath)
    retainedPath = 'F:\DockerRetained\DockerDesktopWSL-before-G'
    configuredDiskLocation = $null
    diskFiles = @()
    targetDrive = $null
    localConfigurationPresent = Test-Path -LiteralPath (Join-Path $repoRoot 'Resources/Docker/.env.local')
    status = 'blocked'
    failures = @()
    diagnostics = [ordered]@{}
    retentionVerified = $false
    resetProcedureVerified = $false
    note = 'Read-only diagnostics; optional manifest is the only write. This is not a verified disk backup or permission to reset Docker.'
}

try {
    Assert-Phase10ComposeProject
    Assert-Phase10LocalDockerEndpoint
    $report.targetDrive = Assert-Phase10StorageCapacity -Path $TargetPath -ForBuild
    if ($Mode -ne 'Report') {
        $localSettings = Get-Phase10LocalSettings -Path (Join-Path $repoRoot 'Resources/Docker/.env.local')
        Assert-Phase10LocalSettings -Settings $localSettings -FullStack
    }
    $report.configuredDiskLocation = Get-Phase10DockerDiskLocation
    if ($Mode -eq 'BeforeSwitch') {
        if ($report.configuredDiskLocation.TrimEnd('\') -ine 'F:\DockerStorage\DockerDesktopWSL') { throw 'BeforeSwitch requires the expected original F: location. Review the actual configuration before retention.' }
        if (Test-Path -LiteralPath $report.retainedPath) { throw 'Retention destination already exists; do not overwrite it.' }
    }
    if (-not (Test-Path -LiteralPath $report.configuredDiskLocation)) { throw 'Configured Docker disk directory does not exist. Verify it before any reset.' }
    $report.diskFiles = @(Get-ChildItem -LiteralPath $report.configuredDiskLocation -Recurse -File -Filter '*.vhdx' -ErrorAction Stop |
        ForEach-Object { [ordered]@{ path = $_.FullName; bytes = $_.Length; lastWriteUtc = $_.LastWriteTimeUtc.ToString('o') } })
    $report.diagnostics.server = Invoke-Phase10DockerReadOnly -Arguments @('version', '--format', '{{.Server.Version}}')
    $report.diagnostics.compose = Invoke-Phase10DockerReadOnly -Arguments @('compose', 'version', '--short')
    $desktopExe = Join-Path $env:ProgramFiles 'Docker/Docker/Docker Desktop.exe'
    if (Test-Path -LiteralPath $desktopExe) { $report.diagnostics.desktopVersion = (Get-Item -LiteralPath $desktopExe).VersionInfo.ProductVersion }
    $report.diagnostics.os = Invoke-Phase10DockerReadOnly -Arguments @('info', '--format', '{{.OSType}}')
    if ($report.diagnostics.os -ne 'linux') { throw 'Linux containers/WSL2 are required.' }
    $report.diagnostics.containers = Invoke-Phase10DockerReadOnly -Arguments @('ps', '-a', '--format', '{{.ID}} {{.Names}} {{.Image}} {{.Status}}')
    $report.diagnostics.images = Invoke-Phase10DockerReadOnly -Arguments @('images', '--format', '{{.ID}} {{.Repository}}:{{.Tag}} {{.Size}}')
    $report.diagnostics.volumes = Invoke-Phase10DockerReadOnly -Arguments @('volume', 'ls', '--format', '{{.Name}}')
    if ($Mode -eq 'AfterSwitch') {
        if ($report.configuredDiskLocation.TrimEnd('\') -ine $report.targetPath.TrimEnd('\')) { throw 'Docker is not configured for the exact G: target. Do not build or delete F:.' }
        if ($report.diskFiles.Count -eq 0) { throw 'No backing VHDX found at the target location.' }
        if ($report.diagnostics.containers -or $report.diagnostics.images -or $report.diagnostics.volumes) { throw 'Fresh-disk acceptance requires empty containers, images, and volumes before rebuilding.' }
    }
    if ($Mode -eq 'Report') {
        $report.diagnostics.usage = Invoke-Phase10DockerReadOnly -Arguments @('system', 'df')
        $report.diagnostics.builders = Invoke-Phase10DockerReadOnly -Arguments @('buildx', 'ls')
        $report.diagnostics.buildCache = Invoke-Phase10DockerReadOnly -Arguments @('buildx', 'du', '--builder', 'desktop-linux')
        $gcOutput = @(& docker buildx inspect desktop-linux 2>&1 | Protect-Phase10Log)
        if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect desktop-linux BuildKit GC policy.' }
        $gcPolicyLines = @($gcOutput | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^(GC Policy rule#|\s+(All|Filters|Keep Duration|Reserved Space|Max Used Space):)' })
        $report.diagnostics.cacheGcPolicy = [ordered]@{
            builder = 'desktop-linux'
            enabled = ($gcPolicyLines -match '^GC Policy rule#').Count -gt 0
            twentyGiBTargetPresent = ($gcPolicyLines -match '^\s+Reserved Space:\s*20(?:\.0+)?GiB\s*$').Count -gt 0
            policy = $gcPolicyLines
            appliesTo = 'eligible BuildKit cache only; not images, SQL data, or total VHDX size'
        }
        if (-not $report.diagnostics.cacheGcPolicy.enabled -or -not $report.diagnostics.cacheGcPolicy.twentyGiBTargetPresent) {
            $report.failures += 'BuildKit GC is not confirmed enabled with a 20GiB retained-space target; inspect Docker Desktop settings before continuing.'
        }
        $projectContainerIds = @(& docker ps -a --filter 'label=com.docker.compose.project=xy-phase10' -q)
        $report.diagnostics.logRotation = @()
        foreach ($containerId in $projectContainerIds) {
            $rotation = & docker inspect --format '{{.Name}}|{{.HostConfig.LogConfig.Type}}|{{json .HostConfig.LogConfig.Config}}' $containerId
            if ($LASTEXITCODE -ne 0) { throw 'Could not inspect Phase 10 container log rotation.' }
            $parts = ([string]$rotation).Split('|', 3)
            $logSettings = if ($parts.Count -eq 3) { $parts[2] | ConvertFrom-Json -AsHashtable } else { @{} }
            $matchesExpected = $parts.Count -eq 3 -and $parts[1] -eq 'json-file' -and $logSettings['max-size'] -eq '10m' -and $logSettings['max-file'] -eq '3'
            $report.diagnostics.logRotation += [ordered]@{ container = $parts[0].TrimStart('/'); driver = if ($parts.Count -ge 2) { $parts[1] } else { 'unknown' }; maxSize = $logSettings['max-size']; maxFile = $logSettings['max-file']; matchesExpected = [bool]$matchesExpected }
        }
        $report.diagnostics.logRotationMismatchCount = @($report.diagnostics.logRotation | Where-Object { -not $_.matchesExpected }).Count
        if ($projectContainerIds.Count -ne 13 -or $report.diagnostics.logRotationMismatchCount -gt 0) {
            $report.failures += "Expected 13 Phase 10 containers with json-file 10m x 3 rotation; found $($projectContainerIds.Count) containers and $($report.diagnostics.logRotationMismatchCount) mismatches."
        }
        try {
            $localSettings = Get-Phase10LocalSettings -Path (Join-Path $repoRoot 'Resources/Docker/.env.local')
            $sqlConnection = New-Phase10HostSqlConnectionString -Database 'master' -Password $localSettings.LOCAL_SQL_PASSWORD -Settings $localSettings
            Assert-Phase10HostSqlIdentity -ConnectionString $sqlConnection
            $connection = [System.Data.SqlClient.SqlConnection]::new($sqlConnection)
            try {
                $connection.Open()
                $command = $connection.CreateCommand()
                $applicationDatabases = @('OrderProcessingSystem_Dev') + @((Get-Phase10ComposeDedicatedTenantDatabaseMap).Values | Sort-Object -Unique)
                $databaseList = ($applicationDatabases | ForEach-Object { "N'$_'" }) -join ', '
                $command.CommandText = @"
SELECT DB_NAME(database_id) AS DatabaseName,
       SUM(CASE WHEN type_desc = 'ROWS' THEN size ELSE 0 END) * 8.0 / 1024 AS DataMiB,
       SUM(CASE WHEN type_desc = 'LOG' THEN size ELSE 0 END) * 8.0 / 1024 AS LogMiB
FROM sys.master_files
WHERE DB_NAME(database_id) IN ($databaseList)
GROUP BY database_id
ORDER BY DatabaseName;
"@
                $reader = $command.ExecuteReader()
                $allocations = @()
                while ($reader.Read()) {
                    $allocations += [ordered]@{ database = [string]$reader['DatabaseName']; dataMiB = [double]$reader['DataMiB']; logMiB = [double]$reader['LogMiB'] }
                }
                $reader.Dispose()
                $report.diagnostics.applicationSqlAllocation = $allocations
                $totalSqlMiB = 0.0
                foreach ($allocation in $allocations) { $totalSqlMiB += $allocation.dataMiB + $allocation.logMiB }
                $totalSqlGiB = $totalSqlMiB / 1024
                $report.diagnostics.applicationSqlAllocationWarning = ($totalSqlGiB -gt 20)
                $report.diagnostics.applicationSqlAllocationGiB = [Math]::Round($totalSqlGiB, 2)
            }
            finally { $connection.Dispose() }
        }
        catch { $report.diagnostics.applicationSqlAllocationStatus = 'unavailable'; $report.diagnostics.applicationSqlAllocationError = 'SQL allocation could not be measured; details omitted.'; $report.failures += 'Required application SQL allocation evidence is unavailable.' }
    }
    $report.status = if ($report.failures.Count -eq 0) { 'passed' } else { 'failed' }
}
catch { $report.failures += $_.Exception.Message }

$json = $report | ConvertTo-Json -Depth 8
if ($ManifestPath) {
    $manifestFullPath = [IO.Path]::GetFullPath($ManifestPath)
    $artifactRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'TestResults')).TrimEnd('\') + '\'
    if (-not $manifestFullPath.StartsWith($artifactRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Manifests must be written under repository TestResults on Q:.' }
    if (Test-Path -LiteralPath $manifestFullPath) { throw 'Manifest already exists; refusing to overwrite retention evidence.' }
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $manifestFullPath) -Force
    Set-Content -LiteralPath $manifestFullPath -Value $json -Encoding utf8
}
$json
if ($report.status -ne 'passed') { exit 1 }
