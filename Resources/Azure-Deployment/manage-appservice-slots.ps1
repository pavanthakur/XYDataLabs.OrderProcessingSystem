<#
.SYNOPSIS
  Manage Azure App Service deployment slots (create, list, deploy, warmup, swap, rollback, delete).
.DESCRIPTION
  Provides repeatable operations for blue/green or canary style deployments for a single Web App.
  Maintains a simple state file recording last successful swap for rollback.
.PARAMETER ResourceGroup
  Resource group containing the Web App.
.PARAMETER WebAppName
  Name of the production Web App.
.PARAMETER Action
  Operation to perform: list|create|deploy|warmup|swap|rollback|delete
.PARAMETER SlotName
  Slot to target (default 'staging').
.PARAMETER PackagePath
  Path to zip package or folder for deployment (deploy action). If folder, will zip temporarily.
.PARAMETER HealthUrl
  URL used for warmup/health checks (warmup action).
.PARAMETER WarmupTimeoutSeconds
  Max seconds to wait for successful 200 response on HealthUrl.
.PARAMETER PollIntervalSeconds
  Interval between health checks.
.PARAMETER Force
  When deleting a slot, bypass confirmation.
.EXAMPLE
  ./manage-appservice-slots.ps1 -ResourceGroup rg-orderprocessing-prod -WebAppName orderprocessing-api-xyapp-prod -Action create -SlotName staging
.EXAMPLE
  ./manage-appservice-slots.ps1 -ResourceGroup rg-orderprocessing-prod -WebAppName orderprocessing-api-xyapp-prod -Action deploy -SlotName staging -PackagePath .\publish
.EXAMPLE
  ./manage-appservice-slots.ps1 -ResourceGroup rg-orderprocessing-prod -WebAppName orderprocessing-api-xyapp-prod -Action warmup -SlotName staging -HealthUrl https://orderprocessing-api-xyapp-prod-staging.azurewebsites.net/health
.EXAMPLE
  ./manage-appservice-slots.ps1 -ResourceGroup rg-orderprocessing-prod -WebAppName orderprocessing-api-xyapp-prod -Action swap -SlotName staging
.EXAMPLE
  ./manage-appservice-slots.ps1 -ResourceGroup rg-orderprocessing-prod -WebAppName orderprocessing-api-xyapp-prod -Action rollback
#>
param(
  [Parameter(Mandatory=$true)] [string]$ResourceGroup,
  [Parameter(Mandatory=$true)] [string]$WebAppName,
  [Parameter(Mandatory=$true)] [ValidateSet('list','create','deploy','warmup','swap','rollback','delete')] [string]$Action,
  [Parameter(Mandatory=$false)] [string]$SlotName = 'staging',
  [Parameter(Mandatory=$false)] [string]$PackagePath = '.\\publish',
  [Parameter(Mandatory=$false)] [string]$HealthUrl,
  [Parameter(Mandatory=$false)] [int]$WarmupTimeoutSeconds = 180,
  [Parameter(Mandatory=$false)] [int]$PollIntervalSeconds = 5,
  [switch]$Force
)

$stateFile = Join-Path $PSScriptRoot "slot-state-$WebAppName.json"

function Write-State($data) {
  $data | ConvertTo-Json | Out-File $stateFile -Encoding UTF8
}
function Read-State() {
  if (Test-Path $stateFile) { Get-Content $stateFile | ConvertFrom-Json } else { return $null }
}

Write-Host "[Slot Manager] Action: $Action | WebApp: $WebAppName | Slot: $SlotName" -ForegroundColor Cyan

switch ($Action) {
  'list' {
    az webapp deployment slot list -g $ResourceGroup -n $WebAppName -o table
  }
  'create' {
    $exists = az webapp deployment slot list -g $ResourceGroup -n $WebAppName --query "[?name=='$SlotName']" -o tsv
    if ($exists) { Write-Host "Slot already exists: $SlotName" -ForegroundColor Yellow; break }
    az webapp deployment slot create -g $ResourceGroup -n $WebAppName --slot $SlotName | Out-Null
    Write-Host "Created slot: $SlotName" -ForegroundColor Green
  }
  'deploy' {
    $slotExists = az webapp deployment slot list -g $ResourceGroup -n $WebAppName --query "[?name=='$SlotName']" -o tsv
    if (-not $slotExists) { Write-Host "Slot missing: $SlotName" -ForegroundColor Red; break }
    if (-not (Test-Path $PackagePath)) { Write-Host "PackagePath not found: $PackagePath" -ForegroundColor Red; break }
    $zipPath = $PackagePath
    if ((Get-Item $PackagePath).PSIsContainer) {
      $zipPath = Join-Path $env:TEMP "slot-deploy-$SlotName.zip"
      if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
      Add-Type -AssemblyName System.IO.Compression.FileSystem
      [System.IO.Compression.ZipFile]::CreateFromDirectory($PackagePath, $zipPath)
    }
    az webapp deploy --resource-group $ResourceGroup --name $WebAppName --slot $SlotName --src-path $zipPath --type zip | Out-Null
    Write-Host "Deployed package to slot: $SlotName" -ForegroundColor Green
    if ($zipPath -ne $PackagePath -and (Test-Path $zipPath)) { Remove-Item $zipPath -Force }
  }
  'warmup' {
    if (-not $HealthUrl) { Write-Host "HealthUrl required for warmup." -ForegroundColor Red; break }
    $deadline = (Get-Date).AddSeconds($WarmupTimeoutSeconds)
    $lastStatus = $null
    while (Get-Date -lt $deadline) {
      try {
        $resp = Invoke-WebRequest -Uri $HealthUrl -Method Get -TimeoutSec 15
        $lastStatus = $resp.StatusCode
        if ($resp.StatusCode -eq 200) { Write-Host "Healthy (200)" -ForegroundColor Green; break }
        Write-Host "Status: $($resp.StatusCode) retrying..." -ForegroundColor Yellow
      } catch { Write-Host "Error: $($_.Exception.Message)" -ForegroundColor DarkYellow }
      Start-Sleep -Seconds $PollIntervalSeconds
    }
    if ($lastStatus -ne 200) { Write-Host "Warmup failed or timed out." -ForegroundColor Red }
  }
  'swap' {
    $slotExists = az webapp deployment slot list -g $ResourceGroup -n $WebAppName --query "[?name=='$SlotName']" -o tsv
    if (-not $slotExists) { Write-Host "Slot missing: $SlotName" -ForegroundColor Red; break }
    az webapp deployment slot swap -g $ResourceGroup -n $WebAppName --slot $SlotName --target-slot production | Out-Null
    Write-Host "Swap completed: $SlotName -> production" -ForegroundColor Green
    Write-State @{ lastSwapFrom = $SlotName; lastSwapTo = 'production'; timestamp = (Get-Date) }
  }
  'rollback' {
    $state = Read-State
    if (-not $state) { Write-Host "No swap state found (cannot rollback)." -ForegroundColor Red; break }
    $from = $state.lastSwapTo
    $to = $state.lastSwapFrom
    if ($from -ne 'production') { Write-Host "State invalid (expected production as lastSwapTo)." -ForegroundColor Red; break }
    az webapp deployment slot swap -g $ResourceGroup -n $WebAppName --slot $to --target-slot production | Out-Null
    Write-Host "Rollback completed: production -> $to" -ForegroundColor Green
    Write-State @{ lastSwapFrom = 'production'; lastSwapTo = $to; timestamp = (Get-Date) }
  }
  'delete' {
    if (-not $Force) { Write-Host "Use -Force to delete slot." -ForegroundColor Yellow; break }
    $slotExists = az webapp deployment slot list -g $ResourceGroup -n $WebAppName --query "[?name=='$SlotName']" -o tsv
    if (-not $slotExists) { Write-Host "Slot not found: $SlotName" -ForegroundColor Yellow; break }
    az webapp deployment slot delete -g $ResourceGroup -n $WebAppName --slot $SlotName | Out-Null
    Write-Host "Deleted slot: $SlotName" -ForegroundColor Green
  }
}

Write-Host "Done." -ForegroundColor Cyan
