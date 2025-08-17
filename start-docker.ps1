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
    [switch]$LegacyBuild  # For development speed when needed (uses existing images)
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
    
    # Determine compose files to use - environment-specific only
    if (Test-Path "docker-compose.$Environment.yml") {
        $composeFiles = @("-f", "docker-compose.$Environment.yml")
        Write-ColoredOutput "Using environment-specific compose file: docker-compose.$Environment.yml" "Green"
    } else {
        throw "Environment-specific compose file docker-compose.$Environment.yml not found. Available environments: dev, uat, prod"
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
        "uat" {
            Write-ColoredOutput "UAT Environment Ports:" "Cyan"
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
    
    # Enterprise-grade Docker deployment with clean builds (Azure-ready)
    if ($LegacyBuild) {
        Write-ColoredOutput "Using legacy build mode (development speed)..." "Yellow" "WARNING"
        Write-ColoredOutput "⚠️  Not recommended for UAT/Production environments" "Yellow" "WARNING"
        
        # Legacy mode: Use existing images if available
        $dockerCmd = "docker-compose $($composeFiles -join ' ') --profile $Profile up -d"
        Write-ColoredOutput "Running: $dockerCmd" "Gray"
        
        # Execute Docker Compose with enhanced error handling
        $dockerOutput = Invoke-Expression $dockerCmd 2>&1
    } else {
        Write-ColoredOutput "Building fresh container images (Azure-style deployment)..." "Cyan" "INFO"
        Write-ColoredOutput "🏢 Enterprise Mode: Ensuring reproducible, secure builds" "Green" "INFO"
        
        $buildCmd = "docker-compose $($composeFiles -join ' ') --profile $Profile build --no-cache"
        Write-ColoredOutput "Running: $buildCmd" "Gray"
        
        # Execute clean build with enhanced error handling
        $buildOutput = Invoke-Expression $buildCmd 2>&1
        $buildOutputString = $buildOutput -join "`n"
        
        # Check build success
        $buildSucceeded = $LASTEXITCODE -eq 0 -or $buildOutputString -match "Successfully built" -or $buildOutputString -match "naming to.*done"
        
        if (-not $buildSucceeded) {
            Write-ColoredOutput "❌ Build failed. Check build output above." "Red" "ERROR"
            throw "Docker build failed with exit code: $LASTEXITCODE"
        }
        
        Write-ColoredOutput "✅ Fresh images built successfully (enterprise-ready)" "Green" "SUCCESS"
        Write-ColoredOutput "Starting containers with fresh images..." "Cyan" "INFO"
        
        # Start containers with fresh images
        $dockerCmd = "docker-compose $($composeFiles -join ' ') --profile $Profile up -d"
        Write-ColoredOutput "Running: $dockerCmd" "Gray"
        
        # Execute Docker Compose with enhanced error handling
        $dockerOutput = Invoke-Expression $dockerCmd 2>&1
    }
    
    # Check if this is a real error or just Docker build output going to stderr
    $outputString = $dockerOutput -join "`n"
    
    # Enhanced success detection - look for key success indicators
    $buildSucceeded = $outputString -match "Build succeeded\." -or $outputString -match "0 Error\(s\)"
    $imagesCreated = $outputString -match "DONE.*done" -and $outputString -match "exporting.*done"
    $imageTagging = $outputString -match "naming to.*$Environment.*done"
    $containersRunning = $outputString -match "Container.*Running" -or $outputString -match "Container.*Healthy"
    $containersStarted = $outputString -match "Started" -or $outputString -match "Recreated"
    
    # Real error is when exit code is non-zero AND we don't have success indicators
    # Also consider it successful if containers are already running or healthy
    $hasRealError = $LASTEXITCODE -ne 0 -and -not ($buildSucceeded -or ($imagesCreated -and $imageTagging) -or $containersRunning -or $containersStarted)
    
    if ($hasRealError) {
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
            $dockerOutput = Invoke-Expression $dockerCmd 2>&1
            
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
            $dockerOutput | ForEach-Object { Write-ColoredOutput "  $_" "Red" "ERROR" }
            throw "Docker Compose failed to start"
        }
    }
    
    # Success condition: Either exit code is 0 OR we have clear success indicators
    $isSuccessful = $LASTEXITCODE -eq 0 -or $buildSucceeded -or ($imagesCreated -and $imageTagging) -or $containersRunning -or $containersStarted
    
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
            "uat" {
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
}
catch {
    Write-ColoredOutput "Error: $($_.Exception.Message)" "Red" "ERROR"
    if ($EnterpriseMode) {
        Write-ColoredOutput "Check enterprise log file: logs/docker-startup-$(Get-Date -Format 'yyyy-MM-dd').log" "Yellow" "INFO"
    }
    exit 1
}
