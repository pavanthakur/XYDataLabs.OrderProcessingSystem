# PowerShell script to extract ports from sharedsettings.json and update .env file
param(
    [string]$SharedSettingsPath = "Resources/Configuration/sharedsettings.json",
    [string]$EnvFilePath = ".env"
)

try {
    # Read and parse sharedsettings.json
    $sharedSettings = Get-Content $SharedSettingsPath -Raw | ConvertFrom-Json
    
    # Extract port values
    $apiHttpPort = $sharedSettings.ApiSettings.API.http.Port
    $apiHttpsPort = $sharedSettings.ApiSettings.API.https.Port
    $uiHttpPort = $sharedSettings.ApiSettings.UI.http.Port
    $uiHttpsPort = $sharedSettings.ApiSettings.UI.https.Port
    
    # Create .env content
    $envContent = @"
# Port configuration extracted from sharedsettings.json
# This file is auto-generated - do not edit manually
API_HTTP_PORT=$apiHttpPort
API_HTTPS_PORT=$apiHttpsPort
UI_HTTP_PORT=$uiHttpPort
UI_HTTPS_PORT=$uiHttpsPort
"@
    
    # Write to .env file
    $envContent | Out-File -FilePath $EnvFilePath -Encoding utf8 -NoNewline
    
    Write-Host "✅ Successfully updated $EnvFilePath with ports from $SharedSettingsPath"
    Write-Host "   API HTTP: $apiHttpPort"
    Write-Host "   API HTTPS: $apiHttpsPort"
    Write-Host "   UI HTTP: $uiHttpPort"
    Write-Host "   UI HTTPS: $uiHttpsPort"
}
catch {
    Write-Error "❌ Failed to extract ports from $SharedSettingsPath : $($_.Exception.Message)"
    exit 1
}
