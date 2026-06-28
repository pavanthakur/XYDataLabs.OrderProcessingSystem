param(
    [ValidateRange(5, 300)]
    [int]$TimeoutSeconds = 180,

    [ValidateRange(1, 10)]
    [int]$PollIntervalSeconds = 2
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot

$launchSettingsPath = Join-Path $workspaceRoot 'XYDataLabs.OrderProcessingSystem.API\Properties\launchSettings.json'
if (-not (Test-Path $launchSettingsPath)) {
    throw "launchSettings.json not found: $launchSettingsPath"
}

$launchSettings = Get-Content $launchSettingsPath -Raw | ConvertFrom-Json
$sharedSettingsPath = $launchSettings.profiles.http.environmentVariables.SHAREDSETTINGS_PATH
if ([string]::IsNullOrWhiteSpace($sharedSettingsPath)) {
    throw "SHAREDSETTINGS_PATH is missing from the 'http' launch profile."
}

$apiProjectRoot = Split-Path -Parent (Split-Path -Parent $launchSettingsPath)
$resolvedSharedSettingsPath = [System.IO.Path]::GetFullPath((Join-Path $apiProjectRoot $sharedSettingsPath))
if (-not (Test-Path $resolvedSharedSettingsPath)) {
    $resolvedSharedSettingsPath = [System.IO.Path]::GetFullPath((Join-Path $workspaceRoot $sharedSettingsPath))
}

if (-not (Test-Path $resolvedSharedSettingsPath)) {
    throw "Shared settings file not found: $sharedSettingsPath"
}

$sharedSettings = Get-Content $resolvedSharedSettingsPath -Raw | ConvertFrom-Json
$connectionString = $sharedSettings.ConnectionStrings.OrderProcessingSystemDbConnection
if ([string]::IsNullOrWhiteSpace($connectionString)) {
    throw "ConnectionStrings:OrderProcessingSystemDbConnection is missing from $resolvedSharedSettingsPath"
}

function Format-ConnectionStringForLog {
    param([string]$Value)

    return ($Value -replace '(?i)(Password|Pwd)=([^;]+)', '$1=***')
}

function Test-SqlConnection {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConnectionString
    )

    Add-Type -AssemblyName System.Data
    $connection = New-Object System.Data.SqlClient.SqlConnection $ConnectionString
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = 'SELECT 1'
        [void]$command.ExecuteScalar()
        return $true
    }
    finally {
        if ($connection.State -ne 'Closed') {
            $connection.Close()
        }
        $connection.Dispose()
    }
}

Write-Host "Verifying local DB readiness for API launch..." -ForegroundColor Cyan
Write-Host "Shared settings: $resolvedSharedSettingsPath" -ForegroundColor DarkGray
Write-Host "Connection string: $(Format-ConnectionStringForLog $connectionString)" -ForegroundColor DarkGray

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$attempt = 0

while ((Get-Date) -lt $deadline) {
    $attempt++
    try {
        if (Test-SqlConnection -ConnectionString $connectionString) {
            Write-Host "Local DB is reachable and compatible." -ForegroundColor Green
            exit 0
        }
    }
    catch {
        $message = $_.Exception.Message
        Write-Host "Attempt $attempt failed: $message" -ForegroundColor Yellow

        if ($message -match 'requires encryption but this machine does not support it') {
            Write-Host ''
            Write-Host 'Action required:' -ForegroundColor Red
            Write-Host '  Update the local SQL target or connection-string contract so the API can connect without a TLS mismatch.' -ForegroundColor Red
            Write-Host '  This is a local environment prerequisite problem, not a Playwright problem.' -ForegroundColor Red
            throw
        }
    }

    Start-Sleep -Seconds $PollIntervalSeconds
}

throw "Timed out waiting for local DB readiness after $TimeoutSeconds seconds."
