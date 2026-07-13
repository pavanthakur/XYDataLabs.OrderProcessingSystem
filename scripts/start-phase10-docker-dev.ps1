param(
    [ValidateSet('up', 'down')]
    [string]$Action = 'up',

    [ValidateSet('apps', 'all')]
    [string]$Profile = 'apps',

    [ValidateRange(60, 900)]
    [int]$HealthTimeoutSec = 300
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $workspaceRoot 'compose\docker-compose.phase10.yml'
$envFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local'
$logRoot = Join-Path $workspaceRoot 'TestResults\Playwright\phase10-docker-http'
$dockerConfigRoot = Join-Path $workspaceRoot '.tmp\docker-config'
$latestPointerPath = Join-Path $logRoot 'latest-playwright-profile.txt'
$rootMarkerPath = Join-Path $workspaceRoot 'TestResults\Playwright\latest-playwright-run.txt'
$runStamp = "$(Get-Date -Format 'yyyyMMdd-HHmmss')_profile"
$runDir = Join-Path $logRoot $runStamp
$startupLogPath = Join-Path $runDir '00-start-profile.log'
$progressLogPath = Join-Path $runDir '01-env-ready.log'
$summaryPath = Join-Path $runDir 'summary.json'

New-Item -ItemType Directory -Path $runDir -Force | Out-Null
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $rootMarkerPath) -Force | Out-Null
New-Item -ItemType Directory -Path $dockerConfigRoot -Force | Out-Null

$previousDockerConfig = $env:DOCKER_CONFIG
$env:DOCKER_CONFIG = $dockerConfigRoot
Set-Content -Path $latestPointerPath -Value $runDir -Encoding utf8
Set-Content -Path $rootMarkerPath -Value $runDir -Encoding utf8
Set-Content -Path (Join-Path $runDir 'run-plan.txt') -Value @(
    'Phase 10 local container stack run',
    'Goal: start the Phase 10 local container stack with SQL and Redis.',
    'Stages:',
    '1. Bring up the compose stack.',
    '2. Wait Ready + Keycloak.',
    '3. Write summary.json and update latest pointers.'
) -Encoding utf8
    Set-Content -Path $startupLogPath -Value "[$(Get-Date -Format o)] Phase 10 Docker profile startup`n" -Encoding utf8
    Set-Content -Path $progressLogPath -Value "Phase 10 Docker profile readiness log initialized.`n" -Encoding utf8

if (-not (Test-Path $composeFile)) {
    throw "Compose file not found: $composeFile"
}

function Wait-ForUrl {
    param(
        [string]$Url,
        [int]$TimeoutSec
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 5
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
                return
            }
        } catch {
        }

        Start-Sleep -Seconds 2
    }

    throw "Timed out waiting for $Url after $TimeoutSec seconds."
}

function Stop-ContainersOnPort {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Port
    )

    $containers = & docker ps --filter "publish=$Port" --format '{{.ID}} {{.Names}}'
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to inspect Docker containers on port $Port."
    }

    if ([string]::IsNullOrWhiteSpace($containers)) {
        return
    }

    foreach ($line in $containers -split "`r?`n") {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $containerId = ($line -split '\s+')[0]
        Add-Content -Path $progressLogPath -Value "Stopping container on port ${Port}: $line"
        & docker stop $containerId 2>&1 | Tee-Object -FilePath (Join-Path $runDir "docker-stop-$Port.log") | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to stop Docker container $containerId on port $Port."
        }
    }
}

function Get-EnvLocalValue {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not (Test-Path $envFile)) {
        return $null
    }

    $line = Get-Content -LiteralPath $envFile | Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*=" } | Select-Object -First 1
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

function Escape-SqlLiteral {
    param([Parameter(Mandatory = $false)][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ''
    }

    return $Value.Replace("'", "''")
}

function Remove-Phase10LocalImages {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImageTag
    )

    $imageOwner = if ([string]::IsNullOrWhiteSpace($env:PHASE10_IMAGE_OWNER)) { 'pavanthakur' } else { $env:PHASE10_IMAGE_OWNER }
    $imageNames = @(
        "ghcr.io/$imageOwner/orderprocessing-orders:$ImageTag",
        "ghcr.io/$imageOwner/orderprocessing-inventory:$ImageTag",
        "ghcr.io/$imageOwner/orderprocessing-notifications:$ImageTag",
        "ghcr.io/$imageOwner/orderprocessing-gateway:$ImageTag",
        "ghcr.io/$imageOwner/orderprocessing-ui:$ImageTag"
    )

    foreach ($imageName in $imageNames) {
        $exists = & docker image inspect $imageName 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($exists)) {
            Add-Content -Path $progressLogPath -Value "Removing stale local image: $imageName"
            & docker image rm -f $imageName 2>&1 | Tee-Object -FilePath (Join-Path $runDir 'docker-image-prune.log') | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to remove stale local image $imageName."
            }
        }
    }
}

function Get-Phase10Databases {
    @(
        'OrderProcessingSystem_Dev',
        'OrderProcessingSystem_TenantC_Dev'
    )
}

function Invoke-Phase10SqlCmdInComposeContainer {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$Query
    )

    $normalizedQuery = ($Query -replace "`r?`n", ' ').Trim()
    $escapedQuery = $normalizedQuery.Replace('"', '\"')
    $shellCommand = [string]::Format(
        'if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then SQLCMD=/opt/mssql-tools18/bin/sqlcmd; else SQLCMD=/opt/mssql-tools/bin/sqlcmd; fi; "$SQLCMD" -C -S localhost -U sa -P "$SA_PASSWORD" -d "{0}" -h -1 -W -Q "SET NOCOUNT ON; {1}"',
        $Database,
        $escapedQuery)

    $attempt = 1
    while ($attempt -le 30) {
        $output = & docker compose --env-file $envFile -f $composeFile --profile $Profile exec -T sql-server /bin/sh -lc $shellCommand 2>&1
        if ($LASTEXITCODE -eq 0) {
            return @($output | ForEach-Object { $_.ToString() })
        }

        if ($attempt -eq 30) {
            throw ([string]::Join([Environment]::NewLine, @($output | ForEach-Object { $_.ToString() }))).Trim()
        }

        Start-Sleep -Seconds 5
        $attempt++
    }
}

function Invoke-Phase10EfDatabaseUpdate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,

        [Parameter(Mandatory = $true)]
        [string]$SqlPassword
    )

    $connectionString = "Server=localhost,1433;Database=$DatabaseName;User Id=sa;Password=$SqlPassword;Encrypt=False;TrustServerCertificate=True;MultipleActiveResultSets=true;"
    $arguments = @(
        'ef', 'database', 'update',
        '--project', 'XYDataLabs.OrderProcessingSystem.Infrastructure',
        '--startup-project', 'XYDataLabs.OrderProcessingSystem.API',
        '--context', 'OrderProcessingSystemDbContext',
        '--connection', $connectionString,
        '--verbose'
    )

    $output = & dotnet @arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ([string]::Join([Environment]::NewLine, @($output | ForEach-Object { $_.ToString() }))).Trim()
    }
}

function Invoke-Phase10DatabaseBootstrap {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SqlPassword,

        [Parameter(Mandatory = $true)]
        [string]$OpenPayMerchantId,

        [Parameter(Mandatory = $true)]
        [string]$OpenPayPublicKey
    )

    Write-Host 'Applying Phase 10 local EF migrations...' -ForegroundColor Cyan
    foreach ($databaseName in @('OrderProcessingSystem_Dev', 'OrderProcessingSystem_TenantC_Dev')) {
        Write-Host "  Migrating $databaseName..." -ForegroundColor Yellow
        Invoke-Phase10EfDatabaseUpdate -DatabaseName $databaseName -SqlPassword $SqlPassword
    }

    Write-Host 'Seeding Phase 10 local payment-provider rows...' -ForegroundColor Cyan
    $escapedOpenPayMerchantId = Escape-SqlLiteral -Value $OpenPayMerchantId
    $escapedOpenPayPublicKey = Escape-SqlLiteral -Value $OpenPayPublicKey
    $providerSeedQuery = @"
DECLARE @TenantId int = (SELECT TOP (1) [Id] FROM [dbo].[Tenants] WHERE [Code] = '{0}' ORDER BY [Id]);

IF @TenantId IS NULL
BEGIN
    THROW 50000, 'Required tenant row was not found.', 1;
END

IF NOT EXISTS (
    SELECT 1
    FROM [payments].[PaymentProviders]
    WHERE [TenantId] = @TenantId AND [Name] = 'OpenPay'
)
BEGIN
    INSERT INTO [payments].[PaymentProviders]
        ([Name], [APIUrl], [IsProduction], [IsActive], [ProviderType], [MerchantId], [PublicKey], [PrivateKeyConfigurationKey], [Use3DSecure], [TenantId], [CreatedBy], [CreatedDate])
    VALUES
        ('OpenPay', 'https://sandbox-api.openpay.mx/v1', 0, 1, 'OpenPay', '{1}', '{2}', 'PaymentProviders:{0}:OpenPay:PrivateKey', 1, @TenantId, 1, GETUTCDATE());
END
"@

    foreach ($databaseName in @('OrderProcessingSystem_Dev', 'OrderProcessingSystem_TenantC_Dev')) {
        $tenantCodes = if ($databaseName -eq 'OrderProcessingSystem_Dev') { @('TenantA', 'TenantB') } else { @('TenantC') }

        foreach ($tenantCode in $tenantCodes) {
            $query = [string]::Format($providerSeedQuery, $tenantCode, $escapedOpenPayMerchantId, $escapedOpenPayPublicKey)
            Invoke-Phase10SqlCmdInComposeContainer -Database $databaseName -Query $query | Out-Null
            Add-Content -Path $progressLogPath -Value "Seeded OpenPay provider for $tenantCode in $databaseName"
        }
    }
}

function Ensure-Phase10Databases {
    Write-Host 'Ensuring Phase 10 local SQL databases exist...' -ForegroundColor Cyan

    foreach ($databaseName in (Get-Phase10Databases)) {
        $query = @"
IF DB_ID(N'$databaseName') IS NULL
BEGIN
    CREATE DATABASE [$databaseName];
END
"@

        Invoke-Phase10SqlCmdInComposeContainer -Database 'master' -Query $query | Out-Null
        Add-Content -Path $progressLogPath -Value "Ensured database exists: $databaseName"
    }
}

Push-Location $workspaceRoot
try {
    $summary = [ordered]@{
        target = 'phase10-docker-http'
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
        finishedUtc = $null
        status = 'running'
        runDir = $runDir
        latestPointerPath = $latestPointerPath
    }

    if ($Action -eq 'down') {
        Add-Content -Path $progressLogPath -Value 'Stopping Phase 10 local container stack.'
        & docker compose --env-file $envFile -f $composeFile --profile $Profile down -v 2>&1 | Tee-Object -FilePath (Join-Path $runDir 'docker-compose-down.log')
        if ($LASTEXITCODE -ne 0) {
            throw "Docker compose down failed with exit code $LASTEXITCODE"
        }

        $summary.status = 'passed'
        return
    }

    Add-Content -Path $progressLogPath -Value 'Starting Phase 10 local container stack.'
    foreach ($port in @(8081, 1433, 6379, 5022)) {
        Stop-ContainersOnPort -Port $port
    }
    & docker compose --env-file $envFile -f $composeFile --profile $Profile down -v 2>&1 | Tee-Object -FilePath (Join-Path $runDir 'docker-compose-preflight-down.log') | Out-Null
    $imageTag = if ([string]::IsNullOrWhiteSpace($env:PHASE10_IMAGE_TAG)) { 'dev' } else { $env:PHASE10_IMAGE_TAG }
    Remove-Phase10LocalImages -ImageTag $imageTag
    & docker compose --env-file $envFile -f $composeFile --profile $Profile up -d --build 2>&1 | Tee-Object -FilePath (Join-Path $runDir 'docker-compose-up.log')
    if ($LASTEXITCODE -ne 0) {
        throw "Docker compose up failed with exit code $LASTEXITCODE"
    }

    Ensure-Phase10Databases
    $localSqlPassword = Get-EnvLocalValue -Name 'LOCAL_SQL_PASSWORD'
    $localOpenPayMerchantId = Get-EnvLocalValue -Name 'LOCAL_OPENPAY_MERCHANT_ID'
    $localOpenPayPublicKey = Get-EnvLocalValue -Name 'LOCAL_OPENPAY_PUBLIC_KEY'

    if ([string]::IsNullOrWhiteSpace($localSqlPassword)) {
        throw "LOCAL_SQL_PASSWORD was not found in $envFile."
    }
    if ([string]::IsNullOrWhiteSpace($localOpenPayMerchantId)) {
        throw "LOCAL_OPENPAY_MERCHANT_ID was not found in $envFile."
    }
    if ([string]::IsNullOrWhiteSpace($localOpenPayPublicKey)) {
        throw "LOCAL_OPENPAY_PUBLIC_KEY was not found in $envFile."
    }

    Invoke-Phase10DatabaseBootstrap -SqlPassword $localSqlPassword -OpenPayMerchantId $localOpenPayMerchantId -OpenPayPublicKey $localOpenPayPublicKey

    Wait-ForUrl -Url 'http://localhost:5080/health/alive' -TimeoutSec $HealthTimeoutSec
    Wait-ForUrl -Url 'http://localhost:5022/' -TimeoutSec $HealthTimeoutSec

    Add-Content -Path $progressLogPath -Value 'Phase 10 local container stack is ready.'
    Write-Host 'Phase 10 local container stack is ready.'
    Write-Host 'Gateway: http://localhost:5080'
    Write-Host 'UI:      http://localhost:5022'
    Write-Host 'Orders:  http://localhost:5081'
    Write-Host 'Inventory: http://localhost:5082'
    Write-Host 'Notifications: http://localhost:5083'
    $summary.status = 'passed'
}
finally {
    $summary.finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
    Set-Content -Path $summaryPath -Value ($summary | ConvertTo-Json -Depth 5) -Encoding utf8
    Set-Content -Path $latestPointerPath -Value $runDir -Encoding utf8
    Set-Content -Path $rootMarkerPath -Value $runDir -Encoding utf8
    if ([string]::IsNullOrWhiteSpace($previousDockerConfig)) {
        Remove-Item Env:DOCKER_CONFIG -ErrorAction SilentlyContinue
    }
    else {
        $env:DOCKER_CONFIG = $previousDockerConfig
    }
    Pop-Location
}
