#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Sets up .env file for local non-Docker development profiles
.DESCRIPTION
    This script configures the .env file with local development ports (5010 series)
    for Visual Studio non-Docker profiles (http/https).
.PARAMETER ProjectType
    The type of project being launched (API or UI)
.PARAMETER Profile  
    The profile being launched (http or https)
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("API", "UI")]
    [string]$ProjectType = "API",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("http", "https")]
    [string]$Profile = "http"
)

# Set error handling
$ErrorActionPreference = "Stop"

# Define local development ports (5010 series)
$LOCAL_API_HTTP_PORT = 5010
$LOCAL_API_HTTPS_PORT = 5011
$LOCAL_UI_HTTP_PORT = 5012
$LOCAL_UI_HTTPS_PORT = 5013

# Define .env file path
$EnvFilePath = ".env"

function Write-ColoredOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Update-EnvFile {
    Write-ColoredOutput "[INFO] Setting up .env file for local non-Docker development..." "Cyan"
    
    # Create .env content for local development
    $envContent = @"
# Port configuration for local non-Docker development
# Generated on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# Environment: local
API_HTTP_PORT=$LOCAL_API_HTTP_PORT
API_HTTPS_PORT=$LOCAL_API_HTTPS_PORT
UI_HTTP_PORT=$LOCAL_UI_HTTP_PORT
UI_HTTPS_PORT=$LOCAL_UI_HTTPS_PORT
# Database configuration for local development
ConnectionStrings__OrderProcessingSystemDbConnection=Server=localhost,1433;Database=OrderProcessingSystem_Local;User Id=sa;Password=Admin100@;TrustServerCertificate=True;
"@
    
    # Write to .env file
    $envContent | Out-File -FilePath $EnvFilePath -Encoding utf8 -NoNewline
    
    Write-ColoredOutput "[SUCCESS] Updated $EnvFilePath with local development configuration:" "Green"
    Write-ColoredOutput "   API HTTP: $LOCAL_API_HTTP_PORT" "White"
    Write-ColoredOutput "   API HTTPS: $LOCAL_API_HTTPS_PORT" "White"
    Write-ColoredOutput "   UI HTTP: $LOCAL_UI_HTTP_PORT" "White"
    Write-ColoredOutput "   UI HTTPS: $LOCAL_UI_HTTPS_PORT" "White"
    Write-ColoredOutput "   Database: OrderProcessingSystem_Local" "Yellow"
}

function Show-LaunchInfo {
    Write-ColoredOutput "[LAUNCH] Launching $ProjectType in $Profile mode..." "Yellow"
    
    if ($ProjectType -eq "API") {
        if ($Profile -eq "http") {
            $url = "http://localhost:$LOCAL_API_HTTP_PORT/swagger"
        } else {
            $url = "https://localhost:$LOCAL_API_HTTPS_PORT/swagger"
        }
        Write-ColoredOutput "   API will be available at: $url" "Green"
    } else {
        if ($Profile -eq "http") {
            $url = "http://localhost:$LOCAL_UI_HTTP_PORT"
        } else {
            $url = "https://localhost:$LOCAL_UI_HTTPS_PORT"
        }
        Write-ColoredOutput "   UI will be available at: $url" "Green"
    }
    
    Write-ColoredOutput "   Database: OrderProcessingSystem_Local (localhost SQL Server)" "Cyan"
}

try {
    Write-ColoredOutput "===============================================" "Magenta"
    Write-ColoredOutput "   Local Non-Docker Environment Setup" "Magenta"
    Write-ColoredOutput "===============================================" "Magenta"
    
    # Update .env file
    Update-EnvFile
    
    # Show launch information
    Show-LaunchInfo
    
    Write-ColoredOutput "[SUCCESS] Environment setup complete! Ready for Visual Studio launch." "Green"
    
} catch {
    Write-ColoredOutput "[ERROR] Error setting up local environment: $($_.Exception.Message)" "Red"
    exit 1
}
