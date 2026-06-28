#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('dev', 'stg', 'prod')]
    [string]$Environment
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($env:DOCKER_CONFIG)) {
    $env:DOCKER_CONFIG = Join-Path $env:TEMP 'orderprocessing-docker-config'
}
if (-not (Test-Path $env:DOCKER_CONFIG)) {
    New-Item -ItemType Directory -Path $env:DOCKER_CONFIG | Out-Null
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$envLocalPath = Join-Path $repoRoot 'Resources\Docker\.env.local'
$sqlContainerName = 'orderprocessing-sqlserver'

function Get-EnvLocalValue {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not (Test-Path $envLocalPath)) {
        return $null
    }

    $line = Get-Content $envLocalPath | Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*=" } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($line)) {
        return $null
    }

    $value = (($line -split '=', 2)[1]).Trim()
    if ($value.StartsWith('"') -and $value.EndsWith('"') -and $value.Length -ge 2) {
        $value = $value.Substring(1, $value.Length - 2)
    }

    if ($value.StartsWith("'") -and $value.EndsWith("'") -and $value.Length -ge 2) {
        $value = $value.Substring(1, $value.Length - 2)
    }

    return $value.Trim()
}

function Get-ExpectedDatabases {
    param([Parameter(Mandatory = $true)][string]$TargetEnvironment)

    switch ($TargetEnvironment) {
        'dev' { return @('OrderProcessingSystem_Dev', 'OrderProcessingSystem_TenantC_Dev') }
        'stg' { return @('OrderProcessingSystem_Stg', 'OrderProcessingSystem_TenantC_Stg') }
        'prod' { return @('OrderProcessingSystem_Prod', 'OrderProcessingSystem_TenantC_Prod') }
        default { throw "Unsupported environment: $TargetEnvironment" }
    }
}

function Invoke-SqlCmdInContainer {
    param(
        [Parameter(Mandatory = $true)][string]$Database,
        [Parameter(Mandatory = $true)][string]$Query,
        [Parameter(Mandatory = $true)][string]$SqlPassword
    )

    $escapedQuery = $Query.Replace('"', '\"')
    $shellCommand = [string]::Format(
        'if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then SQLCMD=/opt/mssql-tools18/bin/sqlcmd; else SQLCMD=/opt/mssql-tools/bin/sqlcmd; fi; "$SQLCMD" -C -S localhost -U sa -P "$SA_PASSWORD" -d "{0}" -h -1 -W -Q "{1}"',
        $Database,
        $escapedQuery)

    & docker exec -e "SA_PASSWORD=$SqlPassword" $sqlContainerName /bin/sh -lc $shellCommand 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "SQL command failed for database '$Database'."
    }
}

$sqlPassword = Get-EnvLocalValue -Name 'LOCAL_SQL_PASSWORD'
if ([string]::IsNullOrWhiteSpace($sqlPassword)) {
    throw "LOCAL_SQL_PASSWORD was not found in Resources\Docker\.env.local."
}

Write-Host "Ensuring Phase 9 Docker databases exist for $Environment..." -ForegroundColor Cyan

Push-Location (Join-Path $repoRoot 'Resources\Docker')
try {
    & docker compose --env-file .env.local -f docker-compose.database.yml up -d sql-server
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to start the shared Docker SQL container."
    }
}
finally {
    Pop-Location
}

$expectedDatabases = @(Get-ExpectedDatabases -TargetEnvironment $Environment)
foreach ($databaseName in $expectedDatabases) {
    Write-Host "Checking database $databaseName..." -ForegroundColor Yellow
    $query = @"
IF DB_ID(N'$databaseName') IS NULL
BEGIN
    CREATE DATABASE [$databaseName];
END
"@

    Invoke-SqlCmdInContainer -Database 'master' -Query $query -SqlPassword $sqlPassword | Out-Null
}

Write-Host "Phase 9 Docker database bootstrap completed for $Environment." -ForegroundColor Green
