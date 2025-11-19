param(
  [Parameter(Mandatory=$true)][string]$ResourceGroup = "rg-orderprocessing-dev",
  [Parameter(Mandatory=$true)][string]$Location = "centralindia",
  [Parameter(Mandatory=$true)][string]$WorkspaceName = "logs-orderprocessing-dev",
  [Parameter(Mandatory=$true)][string]$ApiAppName = "orderprocessing-api-xyapp-dev",
  [Parameter(Mandatory=$true)][string]$UiAppName  = "orderprocessing-ui-xyapp-dev",
  [Parameter(Mandatory=$true)][string]$ApiAppInsights = "ai-orderprocessing-api-dev",
  [Parameter(Mandatory=$true)][string]$UiAppInsights  = "ai-orderprocessing-ui-dev"
)

$ErrorActionPreference = 'Stop'

function Write-Info($m){ Write-Host $m -ForegroundColor Cyan }
function Write-Ok($m){ Write-Host $m -ForegroundColor Green }
function Write-Warn($m){ Write-Host $m -ForegroundColor Yellow }
function Write-Err($m){ Write-Host $m -ForegroundColor Red }

# Simple retry/backoff wrapper for flaky CLI calls
function Invoke-WithRetry {
  param(
    [Parameter(Mandatory=$true)][scriptblock]$Action,
    [Parameter(Mandatory=$true)][string]$Description,
    [int]$MaxAttempts = 5,
    [int]$InitialDelaySeconds = 2
  )
  $attempt = 1
  $delay = $InitialDelaySeconds
  while ($true) {
    try {
      Write-Info ("[Attempt {0}/{1}] {2}" -f $attempt, $MaxAttempts, $Description)
      $output = & $Action
      if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "ExitCode $LASTEXITCODE" }
      return $output
    } catch {
      if ($attempt -ge $MaxAttempts) {
        Write-Err ("Failed: {0}. Last error: {1}" -f $Description, $_.Exception.Message)
        throw
      }
      Write-Warn ("Transient failure for '{0}'. Retrying in {1}s..." -f $Description, $delay)
      Start-Sleep -Seconds $delay
      $attempt++
      $delay = [Math]::Min($delay * 2, 30)
    }
  }
}

Write-Info "Ensuring Log Analytics workspace '$WorkspaceName' in '$ResourceGroup'..."
$wsShow = { az monitor log-analytics workspace show -g $ResourceGroup -n $WorkspaceName --only-show-errors }
$wsExists = $false
try { $null = Invoke-WithRetry -Action $wsShow -Description "Check workspace" -MaxAttempts 3 } catch { $wsExists = $false }
if (-not $wsExists) {
  Invoke-WithRetry -Action { az monitor log-analytics workspace create -g $ResourceGroup -n $WorkspaceName -l $Location --only-show-errors } -Description "Create workspace" | Out-Null
  Write-Ok "Workspace created."
} else { Write-Info "Workspace exists." }
$workspaceId = (Invoke-WithRetry -Action { az monitor log-analytics workspace show -g $ResourceGroup -n $WorkspaceName --query id -o tsv --only-show-errors } -Description "Get workspace id").Trim()

Write-Info "Ensuring Application Insights (API): '$ApiAppInsights'..."
$apiShow = { az monitor app-insights component show -g $ResourceGroup -a $ApiAppInsights --only-show-errors }
$apiExists = $true
try { $null = Invoke-WithRetry -Action $apiShow -Description "Check API AI" -MaxAttempts 3 } catch { $apiExists = $false }
if (-not $apiExists) {
  Invoke-WithRetry -Action { az monitor app-insights component create -g $ResourceGroup -a $ApiAppInsights -l $Location --application-type web --only-show-errors } -Description "Create API AI" | Out-Null
  Write-Ok "API App Insights created."
} else { Write-Info "API App Insights exists." }
Write-Info "Linking API App Insights to workspace..."
Invoke-WithRetry -Action { az monitor app-insights component update -g $ResourceGroup -a $ApiAppInsights --workspace $workspaceId --only-show-errors } -Description "Link API AI to workspace" | Out-Null
$apiConn = (Invoke-WithRetry -Action { az monitor app-insights component show -g $ResourceGroup -a $ApiAppInsights --query connectionString -o tsv --only-show-errors } -Description "Get API AI connection string").Trim()

Write-Info "Ensuring Application Insights (UI): '$UiAppInsights'..."
$uiShow = { az monitor app-insights component show -g $ResourceGroup -a $UiAppInsights --only-show-errors }
$uiExists = $true
try { $null = Invoke-WithRetry -Action $uiShow -Description "Check UI AI" -MaxAttempts 3 } catch { $uiExists = $false }
if (-not $uiExists) {
  Invoke-WithRetry -Action { az monitor app-insights component create -g $ResourceGroup -a $UiAppInsights -l $Location --application-type web --only-show-errors } -Description "Create UI AI" | Out-Null
  Write-Ok "UI App Insights created."
} else { Write-Info "UI App Insights exists." }
Write-Info "Linking UI App Insights to workspace..."
Invoke-WithRetry -Action { az monitor app-insights component update -g $ResourceGroup -a $UiAppInsights --workspace $workspaceId --only-show-errors } -Description "Link UI AI to workspace" | Out-Null
$uiConn = (Invoke-WithRetry -Action { az monitor app-insights component show -g $ResourceGroup -a $UiAppInsights --query connectionString -o tsv --only-show-errors } -Description "Get UI AI connection string").Trim()

Write-Info "Setting APPLICATIONINSIGHTS_CONNECTION_STRING and enabling auto-instrumentation on web apps..."
Invoke-WithRetry -Action { az webapp config appsettings set -g $ResourceGroup -n $ApiAppName --settings APPLICATIONINSIGHTS_CONNECTION_STRING=$apiConn ApplicationInsightsAgent_EXTENSION_VERSION=~3 XDT_MicrosoftApplicationInsights_Mode=recommended --only-show-errors } -Description "Set API app settings" | Out-Null
Invoke-WithRetry -Action { az webapp config appsettings set -g $ResourceGroup -n $UiAppName  --settings APPLICATIONINSIGHTS_CONNECTION_STRING=$uiConn  ApplicationInsightsAgent_EXTENSION_VERSION=~3 XDT_MicrosoftApplicationInsights_Mode=recommended --only-show-errors } -Description "Set UI app settings" | Out-Null

$apiId = (Invoke-WithRetry -Action { az webapp show -g $ResourceGroup -n $ApiAppName --query id -o tsv --only-show-errors } -Description "Get API app id").Trim()
$uiId  = (Invoke-WithRetry -Action { az webapp show -g $ResourceGroup -n $UiAppName  --query id -o tsv --only-show-errors } -Description "Get UI app id").Trim()

Write-Info "Creating/Updating diagnostic settings to route logs/metrics to workspace..."
$diagNameApi = "send-to-la"
$diagNameUi  = "send-to-la"

# Determine if settings exist
$hasDiagApi = az monitor diagnostic-settings list --resource $apiId --query "length(value)" -o tsv --only-show-errors
$hasDiagUi  = az monitor diagnostic-settings list --resource $uiId  --query "length(value)" -o tsv --only-show-errors

$logsJson = @'
[
  {"category": "AppServiceHTTPLogs",    "enabled": true},
  {"category": "AppServiceConsoleLogs",  "enabled": true},
  {"category": "AppServiceAppLogs",      "enabled": true},
  {"category": "AppServicePlatformLogs", "enabled": true}
]
'@
$metricsJson = '[{"category":"AllMetrics","enabled":true}]'

if([int]$hasDiagApi -eq 0){
  Invoke-WithRetry -Action { az monitor diagnostic-settings create --name $diagNameApi --resource $apiId --workspace $workspaceId --logs $logsJson --metrics $metricsJson --only-show-errors } -Description "Create API diagnostic settings" | Out-Null
  Write-Ok "API diagnostic settings created."
}else{
  # Update: delete then recreate (simpler for idempotency across categories)
  $existing = az monitor diagnostic-settings list --resource $apiId -o json --only-show-errors | ConvertFrom-Json
  foreach($d in $existing.value){ Invoke-WithRetry -Action { az monitor diagnostic-settings delete --name $d.name --resource $apiId --only-show-errors } -Description ("Delete API diag setting {0}" -f $d.name) | Out-Null }
  Invoke-WithRetry -Action { az monitor diagnostic-settings create --name $diagNameApi --resource $apiId --workspace $workspaceId --logs $logsJson --metrics $metricsJson --only-show-errors } -Description "Recreate API diagnostic settings" | Out-Null
  Write-Ok "API diagnostic settings updated."
}

if([int]$hasDiagUi -eq 0){
  Invoke-WithRetry -Action { az monitor diagnostic-settings create --name $diagNameUi --resource $uiId --workspace $workspaceId --logs $logsJson --metrics $metricsJson --only-show-errors } -Description "Create UI diagnostic settings" | Out-Null
  Write-Ok "UI diagnostic settings created."
}else{
  $existingUi = az monitor diagnostic-settings list --resource $uiId -o json --only-show-errors | ConvertFrom-Json
  foreach($d in $existingUi.value){ Invoke-WithRetry -Action { az monitor diagnostic-settings delete --name $d.name --resource $uiId --only-show-errors } -Description ("Delete UI diag setting {0}" -f $d.name) | Out-Null }
  Invoke-WithRetry -Action { az monitor diagnostic-settings create --name $diagNameUi --resource $uiId --workspace $workspaceId --logs $logsJson --metrics $metricsJson --only-show-errors } -Description "Recreate UI diagnostic settings" | Out-Null
  Write-Ok "UI diagnostic settings updated."
}

$apiHost = (Invoke-WithRetry -Action { az webapp show -g $ResourceGroup -n $ApiAppName --query defaultHostName -o tsv --only-show-errors } -Description "Get API hostname").Trim()
$uiHost  = (Invoke-WithRetry -Action { az webapp show -g $ResourceGroup -n $UiAppName  --query defaultHostName -o tsv --only-show-errors } -Description "Get UI hostname").Trim()
Write-Ok ("API Host: https://{0}" -f $apiHost)
Write-Ok ("UI  Host: https://{0}" -f $uiHost)

Write-Ok "Done."