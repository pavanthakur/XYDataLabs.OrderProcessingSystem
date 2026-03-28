# open-local-sql-firewall.ps1
# Opens (or closes) the Azure SQL firewall for your local machine's public IP.
# Run this after every fresh bootstrap/deploy to re-enable local SSMS/sqlcmd access.
#
# Usage:
#   Open  firewall: .\Resources\Azure-Deployment\open-local-sql-firewall.ps1 -Environment dev
#   Close firewall: .\Resources\Azure-Deployment\open-local-sql-firewall.ps1 -Environment dev -Close

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'dev',

    [switch]$Close
)

$ErrorActionPreference = 'Stop'

# Map environment to Azure resource suffix (staging → stg)
$envSuffix = switch ($Environment) {
    'staging' { 'stg' }
    default   { $Environment }
}

$sqlServer    = "orderprocessing-sql-$envSuffix"
$resourceGroup = "rg-orderprocessing-$envSuffix"
$ruleName     = "dev-machine"
$envSufDb     = switch ($Environment) { 'staging' { 'Stg' } 'prod' { 'Prod' } default { 'Dev' } }

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Azure SQL Firewall — $Environment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  SQL Server  : $sqlServer.database.windows.net" -ForegroundColor Gray
Write-Host "  Resource RG : $resourceGroup" -ForegroundColor Gray
Write-Host "  Rule name   : $ruleName" -ForegroundColor Gray
Write-Host ""

if ($Close) {
    Write-Host "🔒 Removing firewall rule '$ruleName'..." -ForegroundColor Yellow
    az sql server firewall-rule delete `
        --server $sqlServer `
        --resource-group $resourceGroup `
        --name $ruleName `
        --only-show-errors
    Write-Host "✅ Firewall rule removed. Local access is now blocked." -ForegroundColor Green
}
else {
    Write-Host "🌐 Detecting your public IP..." -ForegroundColor Yellow
    $myIp = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 10).Trim()
    Write-Host "   Your IP: $myIp" -ForegroundColor White

    Write-Host "🔓 Adding firewall rule '$ruleName'..." -ForegroundColor Yellow
    az sql server firewall-rule create `
        --server $sqlServer `
        --resource-group $resourceGroup `
        --name $ruleName `
        --start-ip-address $myIp `
        --end-ip-address $myIp `
        --only-show-errors | Out-Null

    Write-Host ""
    Write-Host "✅ Firewall open for $myIp" -ForegroundColor Green
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host "  SSMS / sqlcmd Connection Details" -ForegroundColor White
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host "  Server   : $sqlServer.database.windows.net" -ForegroundColor Cyan
    Write-Host "  Database (main)   : OrderProcessingSystem_$envSufDb" -ForegroundColor Cyan
    Write-Host "  Database (TenantC): OrderProcessingSystem_TenantC_$envSufDb" -ForegroundColor Cyan
    Write-Host "  Auth     : SQL Server Authentication" -ForegroundColor Cyan
    Write-Host "  Login    : sqladmin" -ForegroundColor Cyan
    $kvName = "kv-orderprocessing-$envSuffix"
    $sqlPwd = az keyvault secret show --vault-name $kvName --name "sql-admin-password" --query value -o tsv 2>$null
    if (-not [string]::IsNullOrWhiteSpace($sqlPwd)) {
        Write-Host "  Password : $sqlPwd" -ForegroundColor Cyan
    } else {
        Write-Host "  Password : (run: az keyvault secret show --vault-name $kvName --name sql-admin-password --query value -o tsv)" -ForegroundColor Yellow
    }
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "⚠️  Remember to close the rule when done:" -ForegroundColor Yellow
    Write-Host "   .\Resources\Azure-Deployment\open-local-sql-firewall.ps1 -Environment $Environment -Close" -ForegroundColor Gray
    Write-Host ""
}
