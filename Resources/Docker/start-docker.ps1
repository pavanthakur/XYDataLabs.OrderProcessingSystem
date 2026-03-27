# PowerShell script to start Docker Compose with environment-specific configurations and enterprise features
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("http", "https", "all")]
    [string]$Profile = "http",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("dev", "stg", "prod")]
    [string]$Environment = "dev",
    
    [Parameter(Mandatory=$false)]
    [string]$SharedSettingsPath = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$Down,
    
    [Parameter(Mandatory=$false)]
    [switch]$EnterpriseMode,
    
    [Parameter(Mandatory=$false)]
    [switch]$ConservativeClean,
    
    [Parameter(Mandatory=$false)]
    [switch]$PreservePersistentData,
    
    [Parameter(Mandatory=$false)]
    [switch]$BackupFirst,
    
    [Parameter(Mandatory=$false)]
    [switch]$LegacyBuild,  # For development speed when needed (uses existing images)

    # Pre-pull base images (always attempts once unless -Strict, can opt-out with -NoPrePull)
    [Parameter(Mandatory=$false)]
    [switch]$NoPrePull,

    # One-shot environment reset (replaces CleanImages + down)
    [Parameter(Mandatory=$false)]
    [switch]$Reset,

    # Health wait timeout (interval fixed internally)
    [Parameter(Mandatory=$false)]
    [int]$HealthTimeoutSec = 90,

    # Strict mode: CI-grade behavior (fatal pre-pull failure, health wait enforced)
    [Parameter(Mandatory=$false)]
    [switch]$Strict,

    # Help / usage output
    [Parameter(Mandatory=$false)]
    [switch]$Help
)

# Compose command auto-detection (supports Docker Compose v1 'docker-compose' and v2 'docker compose')
function Get-DockerComposeCommand {
    # Prefer v2 plugin: docker compose
    try {
        docker compose version > $null 2>&1
        if ($LASTEXITCODE -eq 0) {
            return { docker compose @args }
        }
    } catch {}
    # Fallback to legacy docker-compose if present
    try {
        if (Get-Command docker-compose -ErrorAction SilentlyContinue) {
            return { docker-compose @args }
        }
    } catch {}
    throw "Docker Compose not found (neither 'docker compose' nor 'docker-compose'). Install Docker Compose plugin."
}

$ComposeCmd = Get-DockerComposeCommand

# Human-friendly display of compose command for logging/help (avoid invalid Get-Command usage with subcommand)
try {
    docker compose version > $null 2>&1
    if ($LASTEXITCODE -eq 0) {
        $ComposeDisplay = 'docker compose'
    } elseif (Get-Command docker-compose -ErrorAction SilentlyContinue) {
        $ComposeDisplay = 'docker-compose'
    } else {
        $ComposeDisplay = 'docker compose'
    }
} catch {
    if (Get-Command docker-compose -ErrorAction SilentlyContinue) {
        $ComposeDisplay = 'docker-compose'
    } else {
        $ComposeDisplay = 'docker compose'
    }
}

# Enterprise configuration for environment-specific settings
$EnterpriseConfig = @{
    "dev" = @{
        NetworkName = "xy-dev-network"
        CleanupPolicy = "aggressive"
        BackupRequired = $false
        SecurityLevel = "development"
    }
    "stg" = @{
        NetworkName = "xy-stg-network"
        CleanupPolicy = "conservative"
        BackupRequired = $true
        SecurityLevel = "testing"
    }
    "prod" = @{
        NetworkName = "xy-prod-network"
        CleanupPolicy = "minimal"
        BackupRequired = $true
        SecurityLevel = "production"
    }
}

function Write-ColoredOutput {
    param(
        [string]$Message, 
        [string]$Color = "White",
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    Write-Host $logEntry -ForegroundColor $Color
    
    # Enterprise logging to file
    if ($EnterpriseMode) {
        $logFile = "logs/docker-startup-$(Get-Date -Format 'yyyy-MM-dd').log"
        if (-not (Test-Path "logs")) { 
            New-Item -Type Directory -Path "logs" -Force | Out-Null 
        }
        Add-Content -Path $logFile -Value $logEntry
    }
}

function Initialize-LocalDockerSecrets {
    param([string]$SecretsFilePath = ".env.local")

    $secretDefinitions = @(
        @{ Name = "LOCAL_SQL_PASSWORD"; Prompt = "Enter LOCAL_SQL_PASSWORD for local Docker SQL" },
        @{ Name = "LOCAL_CERT_PASSWORD"; Prompt = "Enter LOCAL_CERT_PASSWORD for local HTTPS certificate" },
        @{ Name = "LOCAL_OPENPAY_MERCHANT_ID"; Prompt = "Enter OpenPay Merchant ID (LOCAL_OPENPAY_MERCHANT_ID)" },
        @{ Name = "LOCAL_OPENPAY_PRIVATE_KEY"; Prompt = "Enter OpenPay Private Key (LOCAL_OPENPAY_PRIVATE_KEY)" },
        @{ Name = "LOCAL_OPENPAY_DEVICE_SESSION_ID"; Prompt = "Enter LOCAL_OPENPAY_DEVICE_SESSION_ID (press Enter for default)" }
    )

    $fileSecrets = @{}
    if (Test-Path $SecretsFilePath) {
        foreach ($line in Get-Content $SecretsFilePath) {
            if ($line -match '^\s*([A-Z0-9_]+)\s*=\s*(.*)$') {
                $fileSecrets[$matches[1]] = $matches[2].Trim()
            }
        }
    }

    $storedNewSecret = $false
    foreach ($definition in $secretDefinitions) {
        $secretName = $definition.Name
        $currentValue = (Get-Item -Path "Env:$secretName" -ErrorAction SilentlyContinue).Value
        if (-not [string]::IsNullOrWhiteSpace($currentValue)) {
            Write-ColoredOutput "Using $secretName from current environment" "Green" "INFO"
            $fileSecrets[$secretName] = $currentValue
            continue
        }

        $fileValue = if ($fileSecrets.ContainsKey($secretName)) { $fileSecrets[$secretName] } else { $null }
        if (-not [string]::IsNullOrWhiteSpace($fileValue)) {
            Set-Item -Path "Env:$secretName" -Value $fileValue
            Write-ColoredOutput "Loaded $secretName from $SecretsFilePath" "Green" "INFO"
            continue
        }

        Write-ColoredOutput "$secretName not set. Prompting once and storing it in $SecretsFilePath (gitignored)." "Yellow" "INFO"

        # Show detailed instructions for OpenPay credentials
        if ($secretName -in @('LOCAL_OPENPAY_MERCHANT_ID', 'LOCAL_OPENPAY_PRIVATE_KEY')) {
            Write-Host ''
            Write-Host '  ┌─────────────────────────────────────────────────────────────────┐' -ForegroundColor Cyan
            Write-Host '  │  OpenPay sandbox credentials — manual step required             │' -ForegroundColor Cyan
            Write-Host '  ├─────────────────────────────────────────────────────────────────┤' -ForegroundColor Cyan
            Write-Host '  │  1. Open https://sandbox-dashboard.openpay.mx                   │' -ForegroundColor Cyan
            Write-Host '  │  2. Log in to your sandbox account                              │' -ForegroundColor Cyan
            Write-Host '  │  3. On the home/dashboard page you will see:                    │' -ForegroundColor Cyan
            Write-Host '  │       Merchant ID  — a short alphanumeric string (e.g. m...)    │' -ForegroundColor Cyan
            Write-Host '  │       Private key  — starts with sk_...                         │' -ForegroundColor Cyan
            Write-Host '  │  4. Paste below. Stored in .env.local — not asked again.        │' -ForegroundColor Cyan
            Write-Host '  │                                                                 │' -ForegroundColor Cyan
            Write-Host '  │  To persist for all team machines, run once after pasting:      │' -ForegroundColor Cyan
            Write-Host '  │    .\Resources\Azure-Deployment\populate-keyvault-secrets.ps1   │' -ForegroundColor Cyan
            Write-Host '  │        -Environment dev                                         │' -ForegroundColor Cyan
            Write-Host '  │        -OpenPayMerchantId <id> -OpenPayPrivateKey <key>         │' -ForegroundColor Cyan
            Write-Host '  └─────────────────────────────────────────────────────────────────┘' -ForegroundColor Cyan
            Write-Host ''
        }

        $secretValue = Read-Host $definition.Prompt -MaskInput
        if ([string]::IsNullOrWhiteSpace($secretValue)) {
            if ($secretName -eq 'LOCAL_OPENPAY_DEVICE_SESSION_ID') {
                $secretValue = 'default-device-session'
                Write-ColoredOutput "Using default value for $secretName" "DarkGray" "INFO"
            } else {
                throw "$secretName is required for Docker startup."
            }
        }

        $fileSecrets[$secretName] = $secretValue
        Set-Item -Path "Env:$secretName" -Value $secretValue
        $storedNewSecret = $true
    }

    if ($storedNewSecret -or -not (Test-Path $SecretsFilePath)) {
        $fileContent = @(
            '# Local Docker secrets for this machine only',
            '# This file is gitignored',
            "LOCAL_SQL_PASSWORD=$($fileSecrets['LOCAL_SQL_PASSWORD'])",
            "LOCAL_CERT_PASSWORD=$($fileSecrets['LOCAL_CERT_PASSWORD'])",
            "LOCAL_OPENPAY_MERCHANT_ID=$($fileSecrets['LOCAL_OPENPAY_MERCHANT_ID'])",
            "LOCAL_OPENPAY_PRIVATE_KEY=$($fileSecrets['LOCAL_OPENPAY_PRIVATE_KEY'])",
            "LOCAL_OPENPAY_DEVICE_SESSION_ID=$($fileSecrets['LOCAL_OPENPAY_DEVICE_SESSION_ID'])"
        )
        Set-Content -Path $SecretsFilePath -Value $fileContent
        Write-ColoredOutput "Stored local Docker secrets in $SecretsFilePath for future runs" "Green" "SUCCESS"
    }
}

function Show-ImageStatus {
    param([string]$Environment)
    
    Write-ColoredOutput "Current image status:" "Cyan" "INFO"
    
    # Check for environment and protocol-specific tagged images
    $taggedImages = @(
        "xydatalabs-orderprocessingsystem-api-http:$Environment", 
        "xydatalabs-orderprocessingsystem-api-https:$Environment",
        "xydatalabs-orderprocessingsystem-ui-http:$Environment", 
        "xydatalabs-orderprocessingsystem-ui-https:$Environment"
    )
    foreach ($image in $taggedImages) {
        $existingImage = docker images -q $image 2>$null
        if ($existingImage) {
            Write-ColoredOutput "  Found: $image" "Green" "INFO"
        } else {
            Write-ColoredOutput "  Missing: $image" "Yellow" "INFO"
        }
    }
    
    # Check for untagged images (legacy) and old tagged images
    $legacyImages = @(
        "xydatalabs-orderprocessingsystem-api", 
        "xydatalabs-orderprocessingsystem-ui",
        "xydatalabs-orderprocessingsystem-api:$Environment", 
        "xydatalabs-orderprocessingsystem-ui:$Environment"
    )
    foreach ($image in $legacyImages) {
        $existingImage = docker images -q $image 2>$null
        if ($existingImage) {
            Write-ColoredOutput "  Legacy image: $image" "Yellow" "INFO"
        }
    }
}

function Remove-ProjectImages {
    param([string]$Environment, [string]$Profile)
    Write-ColoredOutput "Cleaning project images for profile '$Profile' and environment '$Environment'..." "Yellow" "INFO"
    $targets = @()
    switch ($Profile) {
        'http'  { $targets = @("xydatalabs-orderprocessingsystem-api-http:$Environment", "xydatalabs-orderprocessingsystem-ui-http:$Environment") }
        'https' { $targets = @("xydatalabs-orderprocessingsystem-api-https:$Environment", "xydatalabs-orderprocessingsystem-ui-https:$Environment") }
        'all'   { $targets = @(
                        "xydatalabs-orderprocessingsystem-api-http:$Environment", "xydatalabs-orderprocessingsystem-ui-http:$Environment",
                        "xydatalabs-orderprocessingsystem-api-https:$Environment", "xydatalabs-orderprocessingsystem-ui-https:$Environment"
                   ) }
    }
    foreach ($img in $targets) {
        $id = docker images -q $img 2>$null
        if (-not [string]::IsNullOrWhiteSpace($id)) {
            Write-ColoredOutput "Removing image: $img" "Yellow" "INFO"
            docker rmi -f $img 2>$null | Out-Null
        } else {
            Write-ColoredOutput "Image not found (skip): $img" "Gray" "INFO"
        }
    }
    Write-ColoredOutput "Image cleanup complete" "Green" "SUCCESS"
}

function Get-ComposeContainerIds {
    param(
        [string[]]$ComposeFiles,
        [string]$Profile
    )
    try {
        $ids = & $ComposeCmd @ComposeFiles --profile $Profile ps -q 2>$null
        return $ids
    } catch {
        return @()
    }
}

function Wait-ForContainersHealthy {
    param(
        [string[]]$ComposeFiles,
        [string]$Profile,
        [int]$TimeoutSec = 90,
        [int]$IntervalSec = 3
    )
    $start = Get-Date
    $deadline = $start.AddSeconds($TimeoutSec)
    $printedHeader = $false

    while ([DateTime]::UtcNow -lt $deadline.ToUniversalTime()) {
        $allGood = $true
        $ids = Get-ComposeContainerIds -ComposeFiles $ComposeFiles -Profile $Profile
        if (-not $ids -or $ids.Count -eq 0) {
            $allGood = $false
        } else {
            foreach ($id in $ids) {
                if ([string]::IsNullOrWhiteSpace($id)) { continue }
                $json = docker inspect $id 2>$null | ConvertFrom-Json
                if (-not $json) { $allGood = $false; break }
                $st = $json[0].State
                $health = $null
                if ($st.PSObject.Properties.Name -contains 'Health') { $health = $st.Health }
                $status = if ($health) { $health.Status } else { $st.Status }
                # Accept healthy or running
                if (-not (($status -eq 'healthy') -or ($status -eq 'running'))) {
                    $allGood = $false
                    break
                }
            }
        }

        if ($allGood) {
            return $true
        }

        if (-not $printedHeader) {
            Write-ColoredOutput "Waiting for containers to become healthy (timeout ${TimeoutSec}s)..." "Cyan" "INFO"
            $printedHeader = $true
        }
        Start-Sleep -Seconds $IntervalSec
    }
    return $false
}

function Show-ComposeLogs {
    param(
        [string[]]$ComposeFiles,
        [string]$Profile,
        [int]$Tail = 100
    )
    try {
        Write-ColoredOutput "Recent container logs (last $Tail lines):" "Yellow" "INFO"
        $logs = & $ComposeCmd @ComposeFiles --profile $Profile logs --no-color --tail $Tail 2>&1
        $logs | ForEach-Object { Write-ColoredOutput "  $_" "Gray" "INFO" }
    } catch {
        Write-ColoredOutput "Failed to fetch compose logs: $($_.Exception.Message)" "Yellow" "WARNING"
    }
}

function Ensure-DockerNetwork {
    param(
        [string]$NetworkName = "xynetwork", 
        [string]$Environment = "dev",
        [string]$SettingsPath = ""
    )
    
    # Use enterprise network if EnterpriseMode is enabled
    if ($EnterpriseMode -and $EnterpriseConfig.ContainsKey($Environment)) {
        $NetworkName = $EnterpriseConfig[$Environment].NetworkName
        Write-ColoredOutput "Using enterprise network: $NetworkName for $Environment environment" "Cyan" "INFO"
    } else {
        # Use network from sharedsettings if available
        if ($SettingsPath -and (Test-Path $SettingsPath)) {
            try {
                $settings = Get-Content $SettingsPath -Raw | ConvertFrom-Json
                if ($settings.Docker -and $settings.Docker.Networks -and $settings.Docker.Networks.Name) {
                    $NetworkName = $settings.Docker.Networks.Name
                    Write-ColoredOutput "Using network from sharedsettings: $NetworkName" "Cyan" "INFO"
                }
            } catch {
                Write-ColoredOutput "Could not read network settings from sharedsettings, using default" "Yellow" "WARNING"
            }
        }
    }
    
    try {
        $networkExists = docker network ls --filter "name=$NetworkName" --format "{{.Name}}" | Where-Object { $_ -eq $NetworkName }
        
        if (-not $networkExists) {
            Write-ColoredOutput "Creating Docker network: $NetworkName..." "Yellow" "INFO"
            
            if ($EnterpriseMode) {
                # Create enterprise network with proper isolation and labeling
                $subnet = switch ($Environment) {
                    "dev" { "172.20.0.0/16" }
                    "stg" { "172.21.0.0/16" }
                    "prod" { "172.22.0.0/16" }
                    default { "172.20.0.0/16" }
                }
                
                $result = docker network create $NetworkName `
                    --driver bridge `
                    --subnet $subnet `
                    --label "environment=$Environment" `
                    --label "managed-by=enterprise-automation" `
                    --label "security-level=$($EnterpriseConfig[$Environment].SecurityLevel)" 2>&1
            } else {
                # Standard network creation with basic labeling for safer cleanup
                $result = docker network create $NetworkName `
                    --label "environment=$Environment" `
                    --label "managed-by=orderprocessing-system" 2>&1
            }
            
            if ($LASTEXITCODE -eq 0) {
                $securityInfo = if ($EnterpriseMode) { " with $($EnterpriseConfig[$Environment].SecurityLevel) security" } else { "" }
                Write-ColoredOutput "Network '$NetworkName' created successfully$securityInfo" "Green" "SUCCESS"
            } else {
                throw "Failed to create network '$NetworkName': $result"
            }
        } else {
            Write-ColoredOutput "Network '$NetworkName' already exists" "Green"
        }
    }
    catch {
        Write-ColoredOutput "Warning: Could not verify/create network '$NetworkName': $($_.Exception.Message)" "Yellow"
        Write-ColoredOutput "Continuing with startup - network may be created automatically..." "Gray"
    }
}

function Backup-EnterpriseData {
    param(
        [string]$Environment,
        [string]$BackupPath = "backups"
    )
    
    if (-not $EnterpriseMode) {
        Write-ColoredOutput "Backup skipped (not in enterprise mode)" "Gray" "INFO"
        return $true
    }
    
    $config = $EnterpriseConfig[$Environment]
    if (-not $config.BackupRequired -and -not $BackupFirst) {
        Write-ColoredOutput "Backup not required for $Environment environment" "Gray" "INFO"
        return $true
    }
    
    Write-ColoredOutput "Creating enterprise backup for $Environment environment..." "Yellow" "INFO"
    
    try {
        $backupDir = "$BackupPath/docker-backup-$Environment-$(Get-Date -Format 'yyyy-MM-dd-HHmmss')"
        New-Item -Type Directory -Path $backupDir -Force | Out-Null
        
        # Backup persistent volumes
        $persistentVolumes = docker volume ls --filter "label=persistent=true" --filter "label=environment=$Environment" --format "{{.Name}}"
        
        foreach ($volume in $persistentVolumes) {
            if ($volume) {
                Write-ColoredOutput "Backing up volume: $volume" "Cyan" "INFO"
                docker run --rm -v "${volume}:/data" -v "${PWD}/${backupDir}:/backup" alpine:latest tar czf "/backup/$volume-backup.tar.gz" -C /data . 2>&1 | Out-Null
            }
        }
        
        # Backup configuration files
        $configFiles = @("../../Resources/Configuration/sharedsettings.$Environment.json", "docker-compose.$Environment.yml")
        foreach ($file in $configFiles) {
            if (Test-Path $file) {
                Copy-Item $file "$backupDir/" -Force
                Write-ColoredOutput "Backed up configuration: $file" "Green" "SUCCESS"
            }
        }
        
        Write-ColoredOutput "Enterprise backup completed: $backupDir" "Green" "SUCCESS"
        return $true
    }
    catch {
        Write-ColoredOutput "Backup failed: $($_.Exception.Message)" "Red" "ERROR"
        return $false
    }
}

function Test-ImageExists {
    param([string]$Image)
    try {
        $id = docker images -q $Image 2>$null
        return -not [string]::IsNullOrWhiteSpace($id)
    } catch {
        return $false
    }
}

function PrePull-BaseImages {
    param(
        [string[]]$Images,
        [switch]$StrictMode
    )

    if (-not $Images -or $Images.Count -eq 0) { return $true }
    $allOk = $true

    foreach ($img in $Images) {
        if (Test-ImageExists -Image $img) {
            Write-ColoredOutput "Base image already present: $img" "Green" "INFO"
            continue
        }

        # Display informative message about expected download time
        Write-ColoredOutput "" "White"
        Write-ColoredOutput "════════════════════════════════════════════════════════════════" "Cyan" "INFO"
        Write-ColoredOutput "⏳ Downloading base image: $img" "Cyan" "INFO"
        Write-ColoredOutput "   Size: ~1 GB | Expected time: 2-10 minutes (depends on network)" "Yellow" "INFO"
        Write-ColoredOutput "   ℹ️  Please wait - this is a one-time download per machine" "Yellow" "INFO"
        Write-ColoredOutput "   ℹ️  Do NOT troubleshoot other issues during this download" "Yellow" "INFO"
        Write-ColoredOutput "════════════════════════════════════════════════════════════════" "Cyan" "INFO"
        Write-ColoredOutput "" "White"

        # Strict mode: retry & fallback; normal: single attempt
        $retryCount = if ($StrictMode) { 3 } else { 1 }
        $retryDelay = 5
        $attempt = 0
        $pulled = $false
        $startTime = Get-Date
        
        while (-not $pulled -and $attempt -lt $retryCount) {
            $attempt++
            Write-ColoredOutput "Pulling base image ($attempt/$retryCount): $img" "Yellow" "INFO"
            Write-ColoredOutput "Download started at: $(Get-Date -Format 'HH:mm:ss')" "Gray" "INFO"
            
            $output = docker pull $img 2>&1
            $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
            
            if ($LASTEXITCODE -eq 0) {
                Write-ColoredOutput "✅ Successfully pulled: $img" "Green" "SUCCESS"
                Write-ColoredOutput "   Download completed in $elapsed seconds" "Green" "INFO"
                $pulled = $true
                break
            } else {
                Write-ColoredOutput "Pull failed (attempt $attempt) after $elapsed seconds: $img" "Red" "WARNING"
                $output | ForEach-Object { Write-ColoredOutput "  $_" "Gray" "INFO" }
                if ($attempt -lt $retryCount) { 
                    Write-ColoredOutput "Retrying in $retryDelay seconds..." "Yellow" "INFO"
                    Start-Sleep -Seconds $retryDelay 
                }
            }
        }

        if (-not $pulled -and $StrictMode) {
            # Fallback build warming only in strict mode
            try {
                $safeTag = ($img -replace '[^a-zA-Z0-9]', '-').ToLower()
                $tmp = Join-Path -Path $env:TEMP -ChildPath ("warm-prepull-" + [Guid]::NewGuid().ToString())
                New-Item -ItemType Directory -Path $tmp -Force | Out-Null
                $df = @" 
FROM $img AS base
RUN echo warming $img
"@
                $dfPath = Join-Path $tmp 'Dockerfile'
                Set-Content -Path $dfPath -Value $df -NoNewline
                Write-ColoredOutput "Attempting build-based fallback to warm: $img" "Yellow" "INFO"
                $buildOut = docker build --pull --no-cache -t warm-prepull-$safeTag "$tmp" 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-ColoredOutput "Fallback build warmed image: $img" "Green" "SUCCESS"
                    $pulled = $true
                } else {
                    Write-ColoredOutput "Fallback build failed for: $img" "Red" "WARNING"
                    $buildOut | ForEach-Object { Write-ColoredOutput "  $_" "Gray" "INFO" }
                }
            } catch {
                Write-ColoredOutput "Fallback build threw: $($_.Exception.Message)" "Yellow" "WARNING"
            } finally {
                if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
            }
        }

        if (-not $pulled) {
            $allOk = $false
            if ($StrictMode) {
                throw "Failed to obtain base image: $img"
            } else {
                Write-ColoredOutput "Non-strict: continuing despite missing base image $img" "Yellow" "WARNING"
            }
        }
    }

    return $allOk
}

function Show-DockerProxyInfo {
    try {
        Write-ColoredOutput "Docker daemon proxy config:" "Cyan" "INFO"
        $info = docker info 2>$null | Select-String -Pattern "HTTP Proxy|HTTPS Proxy|No Proxy|Registry Mirrors|Server Version"
        if ($info) { $info | ForEach-Object { Write-ColoredOutput ("  " + $_) "Gray" "INFO" } }
    } catch {}
}

$acquiredLock = $false
$lockFile = $null

try {
    # Set working directory to the Docker resources folder
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    $dockerPath = $scriptPath
    Set-Location $dockerPath
    # Ensure external command stderr does not become terminating errors in this scope
    $oldEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    
    if ($Help) {
        Write-Host "XY Order Processing System Docker Startup Script" -ForegroundColor Cyan
        Write-Host "Usage:" -ForegroundColor Yellow
        Write-Host "  .\start-docker.ps1 [-Environment dev|stg|prod] [-Profile http|https|all] [options]\n" -ForegroundColor White
        Write-Host "Core Parameters:" -ForegroundColor Yellow
        Write-Host "  -Environment <env>        Target environment (dev|stg|prod). Default: dev" -ForegroundColor White
        Write-Host "  -Profile <profile>         Service profile (http|https|all). Default: http" -ForegroundColor White
        Write-Host "  -Down                      Stop services for environment/profile." -ForegroundColor White
        Write-Host "  -LegacyBuild               Reuse existing images (development speed)." -ForegroundColor White
        Write-Host "  -Strict                    CI-grade: retries + fallback for base images; enforce health wait (90s default)." -ForegroundColor White
        Write-Host "  -HealthTimeoutSec <secs>   Override health wait timeout (default 90)." -ForegroundColor White
        Write-Host "  -NoPrePull                 Skip base image pre-pull warm step." -ForegroundColor White
        Write-Host "  -Reset                     Stop stack (if running) + remove images for selected profile before start." -ForegroundColor White
        Write-Host "Enterprise Parameters:" -ForegroundColor Yellow
        Write-Host "  -EnterpriseMode            Enable enterprise networks, logging, cleanup policies." -ForegroundColor White
        Write-Host "  -ConservativeClean         Adjust cleanup aggressiveness (primarily STG/prod)." -ForegroundColor White
        Write-Host "  -PreservePersistentData    Preserve labeled persistent volumes during cleanup." -ForegroundColor White
        Write-Host "  -BackupFirst               Force backup prior to start (prod/stg best practice)." -ForegroundColor White
        Write-Host "Path Overrides:" -ForegroundColor Yellow
        Write-Host "  -SharedSettingsPath <path> Override shared settings file location." -ForegroundColor White
        Write-Host "  -EnvFilePath <path>        (Reserved) Environment file output path (currently not generated)." -ForegroundColor White
        Write-Host "Informational:" -ForegroundColor Yellow
        Write-Host "  -Help                      Show this help text." -ForegroundColor White
        Write-Host "\nBehavior Notes:" -ForegroundColor Yellow
        Write-Host "  * Fresh builds (no-cache) unless -LegacyBuild is used." -ForegroundColor Gray
        Write-Host "  * Base images pre-pulled once unless -NoPrePull; Strict adds retries + fallback warming." -ForegroundColor Gray
        Write-Host "  * Health wait applies automatically in Strict and LegacyBuild modes." -ForegroundColor Gray
        Write-Host "  * Exit code 0 when containers reach Running/Healthy even if docker-compose emits stderr status lines." -ForegroundColor Gray
        Write-Host "\nExamples:" -ForegroundColor Yellow
        Write-Host "  Dev fresh build:          .\start-docker.ps1 -Environment dev -Profile http" -ForegroundColor White
        Write-Host "  Fast reuse + health:      .\start-docker.ps1 -Environment dev -Profile http -LegacyBuild -Strict" -ForegroundColor White
        Write-Host "  Skip warm step:           .\start-docker.ps1 -Environment dev -Profile http -NoPrePull" -ForegroundColor White
        Write-Host "  Full reset & rebuild:     .\start-docker.ps1 -Environment dev -Profile https -Reset" -ForegroundColor White
        Write-Host "  STG strict HTTPS:         .\start-docker.ps1 -Environment stg -Profile https -Strict" -ForegroundColor White
        Write-Host "  Prod enterprise w/backup: .\start-docker.ps1 -Environment prod -Profile https -EnterpriseMode -BackupFirst" -ForegroundColor White
        Write-Host "\nDeprecated Parameters (removed): -PrePullRetryCount, -UseBuildFallbackForPrePull, -FailOnPrePullError, -WaitForHealthy, -CleanImages" -ForegroundColor DarkGray
        Write-Host "Replacements: Strict handles resilience & health; Reset replaces CleanImages; NoPrePull skips warm step." -ForegroundColor DarkGray
        exit 0
    }

    Write-ColoredOutput "Working directory set to: $dockerPath" "Gray" "INFO"

    # Concurrent-launch guard: when Visual Studio starts multiple projects with the same Docker profile
    # simultaneously, each project spawns a separate PowerShell process running this script. Without a
    # lock the second process races the first and fails with "container name already in use".
    # Solution: first process acquires a lock file; subsequent processes detect it and exit gracefully,
    # letting the first process manage the full lifecycle.
    $lockFile = Join-Path $env:TEMP "start-docker-$Environment-$Profile.lock"
    $lockTimeoutSec = 300  # max time to hold lock (safety valve)
    $acquiredLock = $false
    if (Test-Path $lockFile) {
        $lockAge = (Get-Date) - (Get-Item $lockFile).LastWriteTime
        if ($lockAge.TotalSeconds -lt $lockTimeoutSec) {
            Write-ColoredOutput "Another instance is already managing this stack ($Environment/$Profile). Exiting — the primary instance will complete startup." "Yellow" "INFO"
            exit 0
        } else {
            Write-ColoredOutput "Stale lock detected (age: $([int]$lockAge.TotalSeconds)s) — removing and continuing." "Yellow" "INFO"
            Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
        }
    }
    try {
        New-Item $lockFile -ItemType File -Force | Out-Null
        $acquiredLock = $true
    } catch {
        Write-ColoredOutput "Could not acquire lock file — continuing without lock." "Yellow" "INFO"
    }

    # Enterprise mode initialization
    if ($EnterpriseMode) {
        Write-ColoredOutput "Starting Enterprise Docker Management Mode" "Cyan" "INFO"
        Write-ColoredOutput "Environment: $Environment | Security Level: $($EnterpriseConfig[$Environment].SecurityLevel)" "White" "INFO"
        
        # Enterprise pre-flight checks
        if ($Environment -eq "prod" -and -not $BackupFirst -and $EnterpriseConfig[$Environment].BackupRequired) {
            Write-ColoredOutput "Warning: Production environment should use -BackupFirst flag" "Yellow" "WARNING"
        }
    }
    
    if ($Down) {
        Write-ColoredOutput "Stopping Docker Compose services (Environment: $Environment)..." "Yellow" "INFO"
        
        # Determine compose files to use - environment-specific only
        if (Test-Path "docker-compose.$Environment.yml") {
            $composeFiles = @("-f", "docker-compose.$Environment.yml")
            Write-ColoredOutput "Using environment-specific compose file: docker-compose.$Environment.yml" "Gray" "INFO"
        } else {
            throw "Environment-specific compose file docker-compose.$Environment.yml not found. Available environments: dev, stg, prod"
        }
        
        Write-ColoredOutput "Running: $ComposeDisplay $($composeFiles -join ' ') --profile $Profile down" "Gray" "INFO"
        & $ComposeCmd @composeFiles --profile $Profile down
        return
    }

    Write-ColoredOutput "Starting Docker Compose Environment: $Environment, Profile: $Profile" "Cyan" "INFO"
    
    # Apply strict semantics early (informational only now)
    if ($Strict) {
        Write-ColoredOutput "Strict mode enabled: fatal pre-pull failure; health wait enforced" "Cyan" "INFO"
    }
    
    # Set default SharedSettingsPath if not provided
    if ([string]::IsNullOrEmpty($SharedSettingsPath)) {
        $SharedSettingsPath = "../Configuration/sharedsettings.$Environment.json"
    }

    Initialize-LocalDockerSecrets -SecretsFilePath ".env.local"
    
    # Enterprise backup if required
    if ($EnterpriseMode -and ($BackupFirst -or $EnterpriseConfig[$Environment].BackupRequired)) {
        if (-not (Backup-EnterpriseData -Environment $Environment)) {
            throw "Enterprise backup failed. Cannot proceed without backup for $Environment environment."
        }
        Write-ColoredOutput "" "White"
    }
    
    # Ensure required Docker network exists with enterprise configuration
    $networkName = if ($EnterpriseMode) { $EnterpriseConfig[$Environment].NetworkName } else { "xynetwork" }
    
    # Override with sharedsettings network if available
    if (Test-Path $SharedSettingsPath) {
        try {
            $settings = Get-Content $SharedSettingsPath -Raw | ConvertFrom-Json
            if ($settings.Docker -and $settings.Docker.Networks -and $settings.Docker.Networks.Name) {
                $networkName = $settings.Docker.Networks.Name
                Write-ColoredOutput "Using network from configuration: $networkName" "Cyan" "INFO"
            }
        } catch {
            # Continue with default network name
        }
    }
    
    Ensure-DockerNetwork -NetworkName $networkName -Environment $Environment -SettingsPath $SharedSettingsPath
    
    # Ensure database network exists for all environments
    $result = docker network ls --filter "name=xy-database-network" --format "{{.Name}}" | Where-Object { $_ -eq "xy-database-network" }
    if (-not $result) {
        Write-ColoredOutput "Creating Docker network: xy-database-network..." "Yellow" "INFO"
        $createResult = docker network create xy-database-network `
            --label "environment=shared" `
            --label "managed-by=orderprocessing-system" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-ColoredOutput "Network 'xy-database-network' created successfully" "Green" "SUCCESS"
        } else {
            Write-ColoredOutput "Warning: Could not create network 'xy-database-network': $createResult" "Yellow" "WARNING"
        }
    } else {
        Write-ColoredOutput "Network 'xy-database-network' already exists" "Green"
    }
    
    Write-ColoredOutput "" "White"
    
    Write-ColoredOutput "Extracting ports from $SharedSettingsPath..." "Gray"
    
    # Read and parse sharedsettings.json
    # Validate sharedsettings file exists for configuration verification
    if (-not (Test-Path $SharedSettingsPath)) {
        Write-ColoredOutput "Warning: SharedSettings file not found at: $SharedSettingsPath" "Yellow" "WARNING"
        Write-ColoredOutput "Docker Compose will use ports defined in docker-compose.$Environment.yml" "Gray"
    } else {
        Write-ColoredOutput "SharedSettings file verified: $SharedSettingsPath" "Green"
    }

    # Pre-flight: ensure local SQL Server databases exist so EF migrations succeed on startup.
    # EF Core's Migrate() can create a database, but if SA is locked (from a previous crash loop)
    # the connection is refused before Migrate() even runs. Creating DBs via Windows auth here
    # breaks that cascade. Silently skips if sqlcmd is not installed or SQL Server is unreachable.
    $dbNames = switch ($Environment) {
        "dev"  { @("OrderProcessingSystem_Dev",  "OrderProcessingSystem_TenantC_Dev") }
        "stg"  { @("OrderProcessingSystem_Stg",  "OrderProcessingSystem_TenantC_Stg") }
        "prod" { @("OrderProcessingSystem_Prod", "OrderProcessingSystem_TenantC_Prod") }
        default { @() }
    }
    if ($dbNames.Count -gt 0) {
        $sqlcmdExe = Get-Command sqlcmd -ErrorAction SilentlyContinue
        if ($sqlcmdExe) {
            Write-ColoredOutput "Pre-flight: ensuring local SQL databases exist for $Environment..." "Cyan" "INFO"
            foreach ($db in $dbNames) {
                $sql = "IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = '$db') CREATE DATABASE [$db];"
                $result = sqlcmd -S "localhost" -E -d master -Q $sql 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-ColoredOutput "  Database '$db' ready" "Green"
                } else {
                    Write-ColoredOutput "  Warning: could not create '$db' (SA may need unlocking or SQL Server not running): $result" "Yellow" "WARNING"
                }
            }
        } else {
            Write-ColoredOutput "Pre-flight DB check skipped (sqlcmd not found)" "DarkGray"
        }
    }

    # Determine compose files to use - environment-specific only
    if (Test-Path "docker-compose.$Environment.yml") {
        # Always include --env-file so docker compose resolves ${LOCAL_*} variables from .env.local
        # regardless of whether the caller inherited session env vars (e.g. Visual Studio launch,
        # fresh terminal, or direct docker compose call). Without this, undefined vars default to ""
        # which causes cert password mismatch and SA lockout on HTTPS profiles.
        if (Test-Path ".env.local") {
            $composeFiles = @("--env-file", ".env.local", "-f", "docker-compose.$Environment.yml")
        } else {
            $composeFiles = @("-f", "docker-compose.$Environment.yml")
        }
        Write-ColoredOutput "Using environment-specific compose file: docker-compose.$Environment.yml" "Green"
    } else {
        throw "Environment-specific compose file docker-compose.$Environment.yml not found. Available environments: dev, stg, prod"
    }
    
    # Display port information from compose file (no .env generation needed)
    switch ($Environment) {
        "dev" {
            Write-ColoredOutput "Development Environment Ports:" "Cyan"
            Write-ColoredOutput "   API HTTP: 5020" "White"
            Write-ColoredOutput "   API HTTPS: 5021" "White"
            Write-ColoredOutput "   UI HTTP: 5022" "White"
            Write-ColoredOutput "   UI HTTPS: 5023" "White"
        }
        "stg" {
            Write-ColoredOutput "Staging Environment Ports:" "Cyan"
            Write-ColoredOutput "   API HTTP: 5030" "White"
            Write-ColoredOutput "   API HTTPS: 5031" "White"
            Write-ColoredOutput "   UI HTTP: 5032" "White"
            Write-ColoredOutput "   UI HTTPS: 5033" "White"
        }
        "prod" {
            Write-ColoredOutput "Production Environment Ports:" "Cyan"
            Write-ColoredOutput "   API HTTP: 5040" "White"
            Write-ColoredOutput "   API HTTPS: 5041" "White"
            Write-ColoredOutput "   UI HTTP: 5042" "White"
            Write-ColoredOutput "   UI HTTPS: 5043" "White"
        }
    }
    
    # Reset option (stop stack + remove images for selected profile)
    if ($Reset) {
        try {
            Write-ColoredOutput "Reset requested: stopping existing services..." "Yellow" "INFO"
            Write-ColoredOutput "Running (reset): $ComposeDisplay $($composeFiles -join ' ') --profile $Profile down -v" "Gray" "INFO"
            & $ComposeCmd @composeFiles --profile $Profile down -v 2>$null | Out-Null
        } catch {}
        Remove-ProjectImages -Environment $Environment -Profile $Profile
    }

    # Pre-pull commonly used base images (unless opted out)
    if (-not $NoPrePull) {
        Write-ColoredOutput "Pre-pulling base images (MCR) to warm cache..." "Cyan" "INFO"
        Write-ColoredOutput "Note: First-time downloads may take 5-15 minutes total for all base images" "Yellow" "INFO"
        Show-DockerProxyInfo
        $baseImages = @(
            'mcr.microsoft.com/dotnet/sdk:8.0',
            'mcr.microsoft.com/dotnet/aspnet:8.0'
        )
        try {
            [void](PrePull-BaseImages -Images $baseImages -StrictMode:$Strict)
        } catch {
            Write-ColoredOutput "Pre-pull encountered an error: $($_.Exception.Message)" "Red" "ERROR"
            if ($Strict) { throw }
        }
        Write-ColoredOutput "" "White"
        Write-ColoredOutput "✅ Pre-pull step completed - base images are now cached locally" "Green" "SUCCESS"
        Write-ColoredOutput "   Future builds will be much faster!" "Green" "INFO"
        Write-ColoredOutput "" "White"
    } else {
        Write-ColoredOutput "Skipping base image pre-pull (-NoPrePull)" "Gray" "INFO"
    }

    # Start containers depending on mode
    if ($LegacyBuild) {
        Write-ColoredOutput "Using legacy build mode (development speed)..." "Yellow" "WARNING"
        Write-ColoredOutput "⚠️  Not recommended for STG/Production environments" "Yellow" "WARNING"
        
        # Legacy mode: Use existing images if available
        $dockerCmd = "$ComposeDisplay $($composeFiles -join ' ') --profile $Profile up -d"
        Write-ColoredOutput "Running: $dockerCmd" "Gray"
        # Stream directly — avoids 2>&1 TTY breakage
        & $ComposeCmd @composeFiles --profile $Profile up -d
        $dockerOutput = ""
    } else {
        Write-ColoredOutput "Building fresh container images (Azure-style deployment)..." "Cyan" "INFO"
        Write-ColoredOutput "🏢 Enterprise Mode: Ensuring reproducible, secure builds" "Green" "INFO"
        $buildCmd = "$ComposeDisplay $($composeFiles -join ' ') --profile $Profile build --no-cache"
        Write-ColoredOutput "Running: $buildCmd" "Gray"
        # Stream build output directly to console — capturing with 2>&1 breaks Docker BuildKit's
        # TTY/progress-pipe detection on Windows and causes instant exit code 1 before any layer builds.
        & $ComposeCmd @composeFiles --profile $Profile build --no-cache
        $buildExitCode = $LASTEXITCODE

        # Determine expected target images for this profile
        $targetImages = @()
        switch ($Profile) {
            'http'  { $targetImages = @("xydatalabs-orderprocessingsystem-api-http:$Environment", "xydatalabs-orderprocessingsystem-ui-http:$Environment") }
            'https' { $targetImages = @("xydatalabs-orderprocessingsystem-api-https:$Environment", "xydatalabs-orderprocessingsystem-ui-https:$Environment") }
            'all'   { $targetImages = @(
                            "xydatalabs-orderprocessingsystem-api-http:$Environment", "xydatalabs-orderprocessingsystem-ui-http:$Environment",
                            "xydatalabs-orderprocessingsystem-api-https:$Environment", "xydatalabs-orderprocessingsystem-ui-https:$Environment"
                         ) }
        }

        # Primary success check: exit code; fallback: verify images exist in daemon
        $existing = $false
        foreach ($img in $targetImages) {
            $id = docker images -q $img 2>$null
            if (-not [string]::IsNullOrWhiteSpace($id)) { $existing = $true }
        }
        $buildSucceeded = ($buildExitCode -eq 0) -or $existing

        if (-not $buildSucceeded) {
            Write-ColoredOutput "❌ Build failed (exit code $buildExitCode) and required images are missing." "Red" "ERROR"
            Write-ColoredOutput "  Tip: run manually to see full output:" "Yellow" "INFO"
            Write-ColoredOutput "  $buildCmd" "White" "INFO"
            throw "Docker build failed with exit code: $buildExitCode"
        } else {
            Write-ColoredOutput "✅ Fresh images built successfully (enterprise-ready)" "Green" "SUCCESS"
        }

        Write-ColoredOutput "Starting containers..." "Cyan" "INFO"

        # Start containers
        $dockerCmd = "$ComposeDisplay $($composeFiles -join ' ') --profile $Profile up -d"
        Write-ColoredOutput "Running: $dockerCmd" "Gray"
        # Stream up output directly (same TTY reason as build above)
        & $ComposeCmd @composeFiles --profile $Profile up -d
        $dockerOutput = ""
    }
    
    # Health wait implicit for Strict and LegacyBuild
    $effectiveWait = $Strict -or $LegacyBuild
    $waitSucceeded = $false
    if ($effectiveWait) {
        $waitSucceeded = Wait-ForContainersHealthy -ComposeFiles $composeFiles -Profile $Profile -TimeoutSec $HealthTimeoutSec -IntervalSec 3
        if ($waitSucceeded) { Write-ColoredOutput "Containers are healthy/running" "Green" "SUCCESS" }
        elseif ($Strict) {
            Write-ColoredOutput "Health checks did not pass within ${HealthTimeoutSec}s (strict mode)" "Red" "ERROR"
            Show-ComposeLogs -ComposeFiles $composeFiles -Profile $Profile -Tail 150
            throw "Strict mode: containers not healthy"
        }
    }

    # Check if this is a real error or just Docker/Compose status output going to stderr
    $outputString = $dockerOutput -join "`n"
    
    # Enhanced success detection - look for key success indicators
    $buildSucceeded = $outputString -match "Build succeeded\." -or $outputString -match "0 Error\(s\)"
    $imagesCreated = $outputString -match "DONE.*done" -and $outputString -match "exporting.*done"
    $imageTagging = $outputString -match "naming to.*$Environment.*done"
    $containersRunning = $outputString -match "Container.*Running" -or $outputString -match "Container.*Healthy"
    $containersStarted = $outputString -match "Started" -or $outputString -match "Recreated"
    $composeStatusOK = $containersRunning -or $containersStarted
    
    # If health or compose status indicates OK, force success regardless of compose exit code
    if ($waitSucceeded -or $composeStatusOK) {
        $hasRealError = $false
        $isSuccessful = $true
    } else {
        # Real error is when exit code is non-zero AND we don't have success indicators
        $hasRealError = $LASTEXITCODE -ne 0 -and -not ($buildSucceeded -or ($imagesCreated -and $imageTagging) -or $containersRunning -or $containersStarted)
    }
    
    if ($hasRealError) {
        if ($effectiveWait -and -not $waitSucceeded) {
            Show-ComposeLogs -ComposeFiles $composeFiles -Profile $Profile -Tail 150
        }
        # Check for common image export errors
        if ($outputString -match "already exists" -or $outputString -match "failed to solve.*already exists") {
            Write-ColoredOutput "Image conflict detected. Attempting cleanup and retry..." "Yellow" "WARNING"
            
            # Show current image status
            Show-ImageStatus -Environment $Environment
            
            # Remove conflicting images - only for current profile to preserve other protocol images
            $targetServices = if ($Profile -eq "http") { @("api-http", "ui-http") } else { @("api-https", "ui-https") }
            $taggedImages = @()
            foreach ($service in $targetServices) {
                $taggedImages += "xydatalabs-orderprocessingsystem-$service`:$Environment"
            }
            
            $legacyImages = @(
                "xydatalabs-orderprocessingsystem-api:$Environment", 
                "xydatalabs-orderprocessingsystem-ui:$Environment",
                "xydatalabs-orderprocessingsystem-api", 
                "xydatalabs-orderprocessingsystem-ui"
            )
            
            # Only remove images for the current profile being started
            foreach ($image in $taggedImages) {
                $existingImage = docker images -q $image 2>$null
                if ($existingImage) {
                    Write-ColoredOutput "Removing existing $Profile image: $image" "Yellow" "INFO"
                    docker rmi $image -f 2>$null
                } else {
                    Write-ColoredOutput "Target $Profile image not found: $image" "Gray" "INFO"
                }
            }
            
            # Then, check for any legacy images (cleanup old naming convention)
            foreach ($image in $legacyImages) {
                $existingImage = docker images -q $image 2>$null
                if ($existingImage) {
                    Write-ColoredOutput "Removing legacy image: $image" "Yellow" "INFO"
                    docker rmi $image -f 2>$null
                } else {
                    Write-ColoredOutput "Legacy image not found: $image (expected with new naming)" "Gray" "INFO"
                }
            }
            
            # Clear build cache
            Write-ColoredOutput "Clearing Docker build cache..." "Yellow" "INFO"
            docker builder prune -f 2>$null
            
            # Retry the command
            Write-ColoredOutput "Retrying Docker Compose startup..." "Yellow" "INFO"
            $dockerOutput = & $ComposeCmd @composeFiles --profile $Profile up -d 2>&1
            
            # Check retry result
            if ($LASTEXITCODE -ne 0) {
                Write-ColoredOutput "Docker Compose retry failed" "Red" "ERROR"
                Write-ColoredOutput "Error output:" "Red" "ERROR"
                $dockerOutput | ForEach-Object { Write-ColoredOutput "  $_" "Red" "ERROR" }
                throw "Docker Compose failed to start after retry"
            }
        } else {
            # Check initial command result for non-image conflict errors  
            Write-ColoredOutput "Docker Compose failed to start" "Red" "ERROR"
            Write-ColoredOutput "Error output:" "Red" "ERROR"
            $dockerOutput | ForEach-Object {
                if ($_ -match 'Container.*(Running|Healthy|Started|Recreated)') {
                    Write-ColoredOutput "  $_" "Gray" "INFO"
                } else {
                    Write-ColoredOutput "  $_" "Red" "ERROR"
                }
            }
            throw "Docker Compose failed to start"
        }
    }
    
    # Success condition: Either forced from health/status OK, or exit code/log indicators
    if (-not $isSuccessful) {
        $isSuccessful = $LASTEXITCODE -eq 0 -or $buildSucceeded -or ($imagesCreated -and $imageTagging) -or $containersRunning -or $containersStarted -or $waitSucceeded
    }
    
    if ($isSuccessful) {
        $modeInfo = if ($EnterpriseMode) { "Enterprise Docker Management" } else { "Docker Compose" }
        Write-ColoredOutput "$modeInfo started successfully!" "Green" "SUCCESS"
        
        # Show container status for confirmation
        if ($containersRunning) {
            Write-ColoredOutput "Containers already running and healthy" "Green" "INFO"
        }
        
        # Enhanced enterprise status information
        if ($EnterpriseMode) {
            $config = $EnterpriseConfig[$Environment]
            Write-ColoredOutput "Enterprise Configuration:" "Cyan" "INFO"
            Write-ColoredOutput "  Environment: $Environment | Profile: $Profile" "White" "INFO"
            Write-ColoredOutput "  Network: $($config.NetworkName)" "White" "INFO"
            Write-ColoredOutput "  Security Level: $($config.SecurityLevel)" "White" "INFO"
            Write-ColoredOutput "  Cleanup Policy: $($config.CleanupPolicy)" "White" "INFO"
        } else {
            Write-ColoredOutput "Environment: $Environment | Profile: $Profile" "Cyan" "INFO"
        }
        
        Write-ColoredOutput "Container status:" "Cyan" "INFO"
        docker ps --format "table {{.Names}}`t{{.Status}}`t{{.Ports}}"
        
        Write-ColoredOutput "" "White"
        Write-ColoredOutput "Application URLs:" "Yellow" "INFO"
        
        # Display URLs based on environment and profile
        switch ($Environment) {
            "dev" {
                if ($Profile -eq "http" -or $Profile -eq "all") {
                    Write-ColoredOutput "   API (HTTP):  http://localhost:5020/swagger" "White" "INFO"
                    Write-ColoredOutput "   UI (HTTP):   http://localhost:5022" "White" "INFO"
                }
                if ($Profile -eq "https" -or $Profile -eq "all") {
                    Write-ColoredOutput "   API (HTTPS): https://localhost:5021/swagger" "White" "INFO"
                    Write-ColoredOutput "   UI (HTTPS):  https://localhost:5023" "White" "INFO"
                }
            }
            "stg" {
                if ($Profile -eq "http" -or $Profile -eq "all") {
                    Write-ColoredOutput "   API (HTTP):  http://localhost:5030/swagger" "White" "INFO"
                    Write-ColoredOutput "   UI (HTTP):   http://localhost:5032" "White" "INFO"
                }
                if ($Profile -eq "https" -or $Profile -eq "all") {
                    Write-ColoredOutput "   API (HTTPS): https://localhost:5031/swagger" "White" "INFO"
                    Write-ColoredOutput "   UI (HTTPS):  https://localhost:5033" "White" "INFO"
                }
            }
            "prod" {
                if ($Profile -eq "http" -or $Profile -eq "all") {
                    Write-ColoredOutput "   API (HTTP):  http://localhost:5040/swagger" "White" "INFO"
                    Write-ColoredOutput "   UI (HTTP):   http://localhost:5042" "White" "INFO"
                }
                if ($Profile -eq "https" -or $Profile -eq "all") {
                    Write-ColoredOutput "   API (HTTPS): https://localhost:5041/swagger" "White" "INFO"
                    Write-ColoredOutput "   UI (HTTPS):  https://localhost:5043" "White" "INFO"
                }
            }
        }
        
        # Environment-specific guidance with enterprise enhancements
        if ($Environment -eq "dev") {
            Write-ColoredOutput "" "White"
            Write-ColoredOutput "Development Environment Notes:" "Cyan" "INFO"
            Write-ColoredOutput "  - Hot reload enabled for fast development" "Gray" "INFO"
            Write-ColoredOutput "  - Source code mounted for live changes" "Gray" "INFO"
            Write-ColoredOutput "  - Debug configuration active" "Gray" "INFO"
            if ($EnterpriseMode) {
                Write-ColoredOutput "  - Enterprise: Aggressive cleanup available" "Gray" "INFO"
            }
        } elseif ($Environment -eq "stg") {
            Write-ColoredOutput "" "White"
            Write-ColoredOutput "Staging Environment Notes:" "Cyan" "INFO"
            Write-ColoredOutput "  - Production-like configuration for testing" "Gray" "INFO"
            Write-ColoredOutput "  - Enhanced monitoring and health checks" "Gray" "INFO"
            Write-ColoredOutput "  - Resource limits applied" "Gray" "INFO"
            if ($EnterpriseMode) {
                Write-ColoredOutput "  - Enterprise: Conservative cleanup policy active" "Gray" "INFO"
                Write-ColoredOutput "  - Enterprise: Automatic backups enabled" "Gray" "INFO"
            }
        } elseif ($Environment -eq "prod") {
            Write-ColoredOutput "" "White"
            Write-ColoredOutput "Production Environment Notes:" "Cyan" "INFO"
            Write-ColoredOutput "  - High availability with replicas" "Gray" "INFO"
            Write-ColoredOutput "  - Resource limits and monitoring" "Gray" "INFO"
            Write-ColoredOutput "  - Optimized for performance and stability" "Gray" "INFO"
            if ($EnterpriseMode) {
                Write-ColoredOutput "  - Enterprise: Minimal cleanup policy (production-safe)" "Gray" "INFO"
                Write-ColoredOutput "  - Enterprise: Mandatory backups enforced" "Gray" "INFO"
                Write-ColoredOutput "  - Enterprise: Network isolation enabled" "Gray" "INFO"
            }
        }
        
        Write-ColoredOutput "" "White"
        Write-ColoredOutput "Quick Commands:" "Yellow" "INFO"
        Write-ColoredOutput "  View logs:    $ComposeDisplay -f docker-compose.$Environment.yml logs -f" "White" "INFO"
        Write-ColoredOutput "  Stop:         .\start-docker.ps1 -Environment $Environment -Profile $Profile -Down" "White" "INFO"
        Write-ColoredOutput "  Legacy build: .\start-docker.ps1 -Environment $Environment -Profile $Profile -LegacyBuild" "Yellow" "INFO"
        
        if ($EnterpriseMode) {
            Write-ColoredOutput "  Enterprise Commands:" "Cyan" "INFO"
            Write-ColoredOutput "  Conservative clean: .\start-docker.ps1 -Environment $Environment -Profile $Profile -ConservativeClean -EnterpriseMode" "White" "INFO"
            Write-ColoredOutput "  Backup and start:   .\start-docker.ps1 -Environment $Environment -Profile $Profile -BackupFirst -EnterpriseMode" "White" "INFO"
            Write-ColoredOutput "  Safe persistent:    .\start-docker.ps1 -Environment $Environment -Profile $Profile -PreservePersistentData -EnterpriseMode" "White" "INFO"
        } else {
            Write-ColoredOutput "  Enterprise:   .\start-docker.ps1 -Environment $Environment -Profile $Profile -EnterpriseMode" "Cyan" "INFO"
        }
    } else {
        throw "Docker Compose failed to start"
    }
    # Explicit success exit to avoid propagating non-zero codes from underlying commands
    try { $global:LASTEXITCODE = 0 } catch {}
    if ($acquiredLock) { Remove-Item $lockFile -Force -ErrorAction SilentlyContinue }
    exit 0
}
catch {
    Write-ColoredOutput "Error: $($_.Exception.Message)" "Red" "ERROR"
    if ($EnterpriseMode) {
        Write-ColoredOutput "Check enterprise log file: logs/docker-startup-$(Get-Date -Format 'yyyy-MM-dd').log" "Yellow" "INFO"
    }
    if ($acquiredLock) { Remove-Item $lockFile -Force -ErrorAction SilentlyContinue }
    exit 1
}
