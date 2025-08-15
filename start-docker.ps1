# PowerShell script to start Docker Compose with environment-specific configurations and enterprise features
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("http", "https", "all")]
    [string]$Profile = "http",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("dev", "uat", "prod")]
    [string]$Environment = "dev",
    
    [Parameter(Mandatory=$false)]
    [string]$SharedSettingsPath = "",
    
    [Parameter(Mandatory=$false)]
    [string]$EnvFilePath = ".env",
    
    [Parameter(Mandatory=$false)]
    [switch]$Down,
    
    [Parameter(Mandatory=$false)]
    [switch]$CleanCache,
    
    [Parameter(Mandatory=$false)]
    [switch]$EnterpriseMode,
    
    [Parameter(Mandatory=$false)]
    [switch]$ConservativeClean,
    
    [Parameter(Mandatory=$false)]
    [switch]$PreservePersistentData,
    
    [Parameter(Mandatory=$false)]
    [switch]$BackupFirst
)

# Enterprise configuration for environment-specific settings
$EnterpriseConfig = @{
    "dev" = @{
        NetworkName = "xy-dev-network"
        CleanupPolicy = "aggressive"
        BackupRequired = $false
        SecurityLevel = "development"
    }
    "uat" = @{
        NetworkName = "xy-uat-network"
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
                    "uat" { "172.21.0.0/16" }
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

function Clean-DockerCache {
    param(
        [bool]$Force = $false,
        [string]$Environment = "dev",
        [bool]$Conservative = $false,
        [bool]$PreservePersistent = $true
    )
    
    if ($Force) {
        $config = if ($EnterpriseMode -and $EnterpriseConfig.ContainsKey($Environment)) { $EnterpriseConfig[$Environment] } else { @{ CleanupPolicy = "standard" } }
        
        Write-ColoredOutput "Performing Docker cache cleanup for $Environment environment..." "Yellow" "INFO"
        Write-ColoredOutput "Cleanup policy: $($config.CleanupPolicy)" "Gray" "INFO"
        
        if ($EnterpriseMode -and $Conservative) {
            Write-ColoredOutput "Using conservative enterprise cleanup mode" "Cyan" "INFO"
        }
        
        try {
            # Enterprise-aware cleanup
            if ($EnterpriseMode -and $config.CleanupPolicy -eq "aggressive" -and $Environment -eq "dev") {
                Write-ColoredOutput "Development environment: Full cleanup" "Yellow" "INFO"
                if ($PreservePersistent) {
                    # Clean but preserve persistent volumes and core networks
                    docker container prune -f --filter "label=environment=$Environment"
                    docker image prune -f --filter "dangling=true"
                    
                    # Remove specific application images to prevent "already exists" errors
                    $appImages = @("xydatalabs-orderprocessingsystem-api", "xydatalabs-orderprocessingsystem-ui")
                    foreach ($image in $appImages) {
                        $existingImage = docker images -q $image 2>$null
                        if ($existingImage) {
                            Write-ColoredOutput "Removing existing application image: $image" "Yellow" "INFO"
                            docker rmi $image -f 2>$null
                        }
                    }
                    
                    # Only prune networks that are NOT our core networks (xy-*-network)
                    $coreNetworks = @("xy-dev-network", "xy-uat-network", "xy-prod-network", "xy-database-network")
                    $allNetworks = docker network ls --filter "label=environment=$Environment" --format "{{.Name}}"
                    if ($allNetworks -and $allNetworks.Count -gt 0) {
                        foreach ($network in $allNetworks) {
                            if ($network -and $network -notin $coreNetworks) {
                                Write-ColoredOutput "Pruning non-core network: $network" "Yellow" "INFO"
                                docker network rm $network 2>$null
                            }
                        }
                    } else {
                        Write-ColoredOutput "No labeled networks found to prune for environment: $Environment" "Gray" "INFO"
                    }
                    docker builder prune -f
                    Write-ColoredOutput "Aggressive cleanup completed (persistent data and core networks preserved)" "Green" "SUCCESS"
                } else {
                    # Full system cleanup
                    $result = docker system prune -f --volumes --filter "label=environment=$Environment" 2>&1
                    Write-ColoredOutput "Full aggressive cleanup completed" "Green" "SUCCESS"
                }
            }
            elseif ($EnterpriseMode -and $config.CleanupPolicy -eq "conservative") {
                Write-ColoredOutput "UAT environment: Conservative cleanup" "Yellow" "INFO"
                # Only clean old containers and dangling images
                docker container prune -f --filter "until=24h" --filter "label=environment=$Environment"
                docker image prune -f --filter "dangling=true"
                docker builder prune -f
                Write-ColoredOutput "Conservative cleanup completed" "Green" "SUCCESS"
            }
            elseif ($EnterpriseMode -and $config.CleanupPolicy -eq "minimal") {
                Write-ColoredOutput "Production environment: Minimal cleanup" "Yellow" "INFO"
                # Only clean dangling images and build cache
                docker image prune -f --filter "dangling=true"
                docker builder prune -f
                Write-ColoredOutput "Minimal cleanup completed (production safe)" "Green" "SUCCESS"
            }
            else {
                # Standard cleanup for non-enterprise mode
                Write-ColoredOutput "Standard cleanup mode" "Gray" "INFO"
                
                # Remove specific application images to prevent "already exists" errors
                $appImages = @("xydatalabs-orderprocessingsystem-api", "xydatalabs-orderprocessingsystem-ui")
                foreach ($image in $appImages) {
                    $existingImage = docker images -q $image 2>$null
                    if ($existingImage) {
                        Write-ColoredOutput "Removing existing application image: $image" "Yellow" "INFO"
                        docker rmi $image -f 2>$null
                    }
                }
                
                $result = docker system prune -f --volumes 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-ColoredOutput "Docker cache cleanup completed" "Green" "SUCCESS"
                    if ($result -and ($result -join "`n") -match "Total reclaimed space: (.+)") {
                        Write-ColoredOutput "Space reclaimed: $($matches[1])" "Cyan" "INFO"
                    }
                }
            }
        }
        catch {
            Write-ColoredOutput "Warning: Cache cleanup failed: $($_.Exception.Message)" "Yellow" "WARNING"
        }
    } else {
        $cleanupFlag = if ($EnterpriseMode) { "-CleanCache or -ConservativeClean" } else { "-CleanCache" }
        Write-ColoredOutput "Add $cleanupFlag flag to perform Docker cache cleanup before starting" "Cyan" "INFO"
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
        $configFiles = @("Resources/Configuration/sharedsettings.$Environment.json", "docker-compose.$Environment.yml")
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

try {
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
            throw "Environment-specific compose file docker-compose.$Environment.yml not found. Available environments: dev, uat, prod"
        }
        
        $downCmd = "docker-compose $($composeFiles -join ' ') --profile $Profile down"
        Invoke-Expression $downCmd
        return
    }

    Write-ColoredOutput "Starting Docker Compose Environment: $Environment, Profile: $Profile" "Cyan" "INFO"
    
    # Set default SharedSettingsPath if not provided
    if ([string]::IsNullOrEmpty($SharedSettingsPath)) {
        $SharedSettingsPath = "Resources/Configuration/sharedsettings.$Environment.json"
    }
    
    # Enterprise backup if required
    if ($EnterpriseMode -and ($BackupFirst -or $EnterpriseConfig[$Environment].BackupRequired)) {
        if (-not (Backup-EnterpriseData -Environment $Environment)) {
            throw "Enterprise backup failed. Cannot proceed without backup for $Environment environment."
        }
        Write-ColoredOutput "" "White"
    }
    
    # Clean Docker cache if requested with enterprise awareness
    if ($CleanCache -or $ConservativeClean) {
        $cleanupParams = @{
            Force = $true
            Environment = $Environment
            Conservative = $ConservativeClean
            PreservePersistent = $PreservePersistentData
        }
        Clean-DockerCache @cleanupParams
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
    if (-not (Test-Path $SharedSettingsPath)) {
        throw "SharedSettings file not found at: $SharedSettingsPath"
    }
    
    $sharedSettings = Get-Content $SharedSettingsPath -Raw | ConvertFrom-Json
    
    # Extract port values
    $apiHttpPort = $sharedSettings.ApiSettings.API.http.Port
    $apiHttpsPort = $sharedSettings.ApiSettings.API.https.Port
    $uiHttpPort = $sharedSettings.ApiSettings.UI.http.Port
    $uiHttpsPort = $sharedSettings.ApiSettings.UI.https.Port
    
    # Validate ports
    if (-not ($apiHttpPort -and $apiHttpsPort -and $uiHttpPort -and $uiHttpsPort)) {
        throw "Failed to extract all required ports from sharedsettings.json"
    }
    
    # Create .env content
    $envContent = @"
# Port configuration extracted from sharedsettings.json
# Generated on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# Environment: $Environment
API_HTTP_PORT=$apiHttpPort
API_HTTPS_PORT=$apiHttpsPort
UI_HTTP_PORT=$uiHttpPort
UI_HTTPS_PORT=$uiHttpsPort
"@
    
    # Write to .env file
    $envContent | Out-File -FilePath $EnvFilePath -Encoding utf8 -NoNewline
    
    Write-ColoredOutput "Updated $EnvFilePath with ports:" "Green"
    Write-ColoredOutput "   API HTTP: $apiHttpPort" "White"
    Write-ColoredOutput "   API HTTPS: $apiHttpsPort" "White"
    Write-ColoredOutput "   UI HTTP: $uiHttpPort" "White"
    Write-ColoredOutput "   UI HTTPS: $uiHttpsPort" "White"
    
    # Determine compose files to use - environment-specific only
    if (Test-Path "docker-compose.$Environment.yml") {
        $composeFiles = @("-f", "docker-compose.$Environment.yml")
        Write-ColoredOutput "Using environment-specific compose file: docker-compose.$Environment.yml" "Green"
    } else {
        throw "Environment-specific compose file docker-compose.$Environment.yml not found. Available environments: dev, uat, prod"
    }
    
    # Start Docker Compose with the specified environment and profile
    $dockerCmd = "docker-compose $($composeFiles -join ' ') --profile $Profile up -d"
    Write-ColoredOutput "Running: $dockerCmd" "Gray"
    
    Invoke-Expression $dockerCmd
    
    if ($LASTEXITCODE -eq 0) {
        $modeInfo = if ($EnterpriseMode) { "Enterprise Docker Management" } else { "Docker Compose" }
        Write-ColoredOutput "$modeInfo started successfully!" "Green" "SUCCESS"
        
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
        if ($Profile -eq "http" -or $Profile -eq "all") {
            Write-ColoredOutput "   API (HTTP):  http://localhost:$apiHttpPort/swagger" "White" "INFO"
            Write-ColoredOutput "   UI (HTTP):   http://localhost:$uiHttpPort" "White" "INFO"
        }
        if ($Profile -eq "https" -or $Profile -eq "all") {
            Write-ColoredOutput "   API (HTTPS): https://localhost:$apiHttpsPort/swagger" "White" "INFO"
            Write-ColoredOutput "   UI (HTTPS):  https://localhost:$uiHttpsPort" "White" "INFO"
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
        } elseif ($Environment -eq "uat") {
            Write-ColoredOutput "" "White"
            Write-ColoredOutput "UAT Environment Notes:" "Cyan" "INFO"
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
        Write-ColoredOutput "  View logs:    docker-compose -f docker-compose.$Environment.yml logs -f" "White" "INFO"
        Write-ColoredOutput "  Stop:         .\start-docker.ps1 -Environment $Environment -Profile $Profile -Down" "White" "INFO"
        
        if ($EnterpriseMode) {
            Write-ColoredOutput "  Enterprise Commands:" "Cyan" "INFO"
            Write-ColoredOutput "  Conservative clean: .\start-docker.ps1 -Environment $Environment -Profile $Profile -ConservativeClean -EnterpriseMode" "White" "INFO"
            Write-ColoredOutput "  Backup & start:     .\start-docker.ps1 -Environment $Environment -Profile $Profile -BackupFirst -EnterpriseMode" "White" "INFO"
            Write-ColoredOutput "  Safe persistent:    .\start-docker.ps1 -Environment $Environment -Profile $Profile -PreservePersistentData -EnterpriseMode" "White" "INFO"
        } else {
            Write-ColoredOutput "  Clean start:  .\start-docker.ps1 -Environment $Environment -Profile $Profile -CleanCache" "White" "INFO"
            Write-ColoredOutput "  Enterprise:   .\start-docker.ps1 -Environment $Environment -Profile $Profile -EnterpriseMode" "Cyan" "INFO"
        }
    } else {
        throw "Docker Compose failed to start"
    }
}
catch {
    Write-ColoredOutput "Error: $($_.Exception.Message)" "Red" "ERROR"
    if ($EnterpriseMode) {
        Write-ColoredOutput "Check enterprise log file: logs/docker-startup-$(Get-Date -Format 'yyyy-MM-dd').log" "Yellow" "INFO"
    }
    exit 1
}
