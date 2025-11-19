<#
.SYNOPSIS
  Waits for one or more Azure App Services (and optional App Service Plan) to reach readiness before CI/CD deployment.
.DESCRIPTION
  Polls the App Service Plan provisioning state and each Web App's runtime state & HTTP responsiveness.
  Intended for GitHub Actions gating: fail early if environment not yet stable (prevents premature deployments).
  Success criteria for each WebApp:
    - Exists via CLI
    - state == Running
    - HTTP GET to root returns 200 OR 404 (404 acceptable when app not deployed yet)
    - Rejects persistent 5xx responses
  Plan (optional): provisioningState == Succeeded AND status == Ready.
.PARAMETER ResourceGroup
  Resource group containing the resources.
.PARAMETER PlanName
  (Optional) App Service Plan name to verify readiness.
.PARAMETER WebApps
  Comma-separated list of WebApp names to verify.
.PARAMETER TimeoutMinutes
  Maximum wait time (default: 20).
.PARAMETER IntervalSeconds
  Poll interval (default: 30).
.EXAMPLE
  ./wait-appservice-ready.ps1 -ResourceGroup rg-orderprocessing-dev -PlanName asp-orderprocessing-dev -WebApps orderprocessing-api-xyapp-dev,orderprocessing-ui-xyapp-dev
  Exits 0 when ready, 1 on timeout/failure.
#>
param(
  [Parameter(Mandatory=$true)][string]$ResourceGroup,
  [string]$PlanName,
  [Parameter(Mandatory=$true)][string]$WebApps,
  [int]$TimeoutMinutes = 20,
  [int]$IntervalSeconds = 30
)

$ErrorActionPreference = 'SilentlyContinue'
$webAppList = $WebApps.Split(',',[System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() } | Where-Object { $_ }
if (-not $webAppList) { Write-Host "[ERROR] No webapps specified" -ForegroundColor Red; exit 1 }

Write-Host "[WAIT] Gating deployment until resources are ready..." -ForegroundColor Cyan
Write-Host "  ResourceGroup: $ResourceGroup" -ForegroundColor Gray
if ($PlanName) { Write-Host "  Plan: $PlanName" -ForegroundColor Gray }
Write-Host "  WebApps: $($webAppList -join ', ')" -ForegroundColor Gray

$timeoutSeconds = $TimeoutMinutes * 60
$elapsed = 0
$planReady = (-not $PlanName) # If no plan specified treat as ready
$appStatus = @{}
foreach ($w in $webAppList) { $appStatus[$w] = $false }

Write-Host "  [PROGRESS] [" -NoNewline -ForegroundColor Cyan
$progressChars = [math]::Ceiling($timeoutSeconds / $IntervalSeconds)
$progressPrinted = 0

function Test-HttpOk($url) {
  try {
    $resp = Invoke-WebRequest -Uri $url -Method Get -TimeoutSec 8 -ErrorAction SilentlyContinue
    if (-not $resp) { return $false }
    if ($resp.StatusCode -eq 200 -or $resp.StatusCode -eq 404) { return $true }
    if ($resp.StatusCode -ge 500) { return $false }
    return $false
  } catch { return $false }
}

while ($elapsed -lt $timeoutSeconds -and (
    (-not $planReady) -or ($appStatus.Values | Where-Object { $_ -eq $false }).Count -gt 0)) {
  Start-Sleep -Seconds $IntervalSeconds
  $elapsed += $IntervalSeconds
  $progressPrinted++
  if ($progressPrinted -le $progressChars) { Write-Host "#" -NoNewline -ForegroundColor Green }

  if (-not $planReady -and $PlanName) {
    $pInfo = az appservice plan show -g $ResourceGroup -n $PlanName --query "{prov:provisioningState,status:status}" -o json 2>$null | ConvertFrom-Json
    if ($pInfo -and $pInfo.prov -eq 'Succeeded' -and $pInfo.status -eq 'Ready') {
      $planReady = $true
      Write-Host "`n  [OK] Plan ready after $([math]::Round($elapsed/60,1)) min" -ForegroundColor Green
      Write-Host "  [PROGRESS] [" -NoNewline -ForegroundColor Cyan; for ($i=0;$i -lt $progressPrinted;$i++){ Write-Host "#" -NoNewline -ForegroundColor Green }
    }
  }

  foreach ($w in $webAppList) {
    if ($appStatus[$w]) { continue }
    $info = az webapp show -g $ResourceGroup -n $w --query "{state:state,host:defaultHostName}" -o json 2>$null | ConvertFrom-Json
    if ($info) {
      $url = "https://$w.azurewebsites.net"
      $httpOk = Test-HttpOk $url
      if ($info.state -eq 'Running' -and $httpOk) {
        $appStatus[$w] = $true
        Write-Host "`n  [OK] $w ready (Running + HTTP) after $([math]::Round($elapsed/60,1)) min" -ForegroundColor Green
        Write-Host "  [PROGRESS] [" -NoNewline -ForegroundColor Cyan; for ($i=0;$i -lt $progressPrinted;$i++){ Write-Host "#" -NoNewline -ForegroundColor Green }
      }
    }
  }
}
Write-Host "]" -ForegroundColor Cyan

$incompleteApps = $appStatus.GetEnumerator() | Where-Object { -not $_.Value } | Select-Object -ExpandProperty Name
if ($planReady -and $incompleteApps.Count -eq 0) {
  Write-Host "[SUCCESS] All readiness criteria satisfied." -ForegroundColor Green
  exit 0
}
Write-Host "[FAIL] Readiness incomplete. PlanReady=$planReady; PendingApps=$($incompleteApps -join ', ')" -ForegroundColor Yellow
exit 1
