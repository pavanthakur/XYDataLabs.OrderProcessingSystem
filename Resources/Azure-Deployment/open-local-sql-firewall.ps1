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
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding          = [System.Text.Encoding]::UTF8

# ANSI color helper — writes to stdout (capturable) with color in ANSI terminals.
# Write-Host writes to the PowerShell host stream which is not captured by tools/redirects.
function Msg {
    param([string]$Text, [string]$Color = 'White')
    $codes = @{ Cyan='36'; Green='32'; Yellow='33'; Gray='90'; White='37'; DarkGray='90'; Red='31' }
    $code  = if ($codes.ContainsKey($Color)) { $codes[$Color] } else { '37' }
    [Console]::WriteLine("`e[${code}m${Text}`e[0m")
}

# Map environment to Azure resource suffix (staging → stg)
$envSuffix = switch ($Environment) {
    'staging' { 'stg' }
    default   { $Environment }
}

$sqlServer    = "orderprocessing-sql-$envSuffix"
$resourceGroup = "rg-orderprocessing-$envSuffix"
$ruleName     = "dev-machine"
$envSufDb     = switch ($Environment) { 'staging' { 'Stg' } 'prod' { 'Prod' } default { 'Dev' } }

Msg "========================================" Cyan
Msg "  Azure SQL Firewall — $Environment" Cyan
Msg "========================================" Cyan
Msg ""
Msg "  SQL Server  : $sqlServer.database.windows.net" Gray
Msg "  Resource RG : $resourceGroup" Gray
Msg "  Rule name   : $ruleName" Gray
Msg ""

if ($Close) {
    Msg "Removing firewall rule '$ruleName'..." Yellow
    az sql server firewall-rule delete `
        --server $sqlServer `
        --resource-group $resourceGroup `
        --name $ruleName `
        --only-show-errors
    Msg "Firewall rule removed. Local access is now blocked." Green
}
else {
    Msg "Detecting your public IP..." Yellow
    $myIp = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 10).Trim()
    Msg "   Your IP: $myIp" White

    Msg "Adding firewall rule '$ruleName'..." Yellow
    az sql server firewall-rule create `
        --server $sqlServer `
        --resource-group $resourceGroup `
        --name $ruleName `
        --start-ip-address $myIp `
        --end-ip-address $myIp `
        --only-show-errors | Out-Null

    Msg ""
    Msg "Firewall open for $myIp" Green
    Msg ""
    Msg "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" DarkGray
    Msg "  SSMS / sqlcmd Connection Details" White
    Msg "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" DarkGray
    Msg "  Server            : $sqlServer.database.windows.net" Cyan
    Msg "  Database (main)   : OrderProcessingSystem_$envSufDb" Cyan
    Msg "  Database (TenantC): OrderProcessingSystem_TenantC_$envSufDb" Cyan
    Msg "  Auth              : SQL Server Authentication" Cyan
    Msg "  Login             : sqladmin" Cyan
    $kvName = "kv-orderprocessing-$envSuffix"
    $sqlPwd = az keyvault secret show --vault-name $kvName --name "sql-admin-password" --query value -o tsv 2>$null
    if (-not [string]::IsNullOrWhiteSpace($sqlPwd)) {
        Msg "  Password          : $sqlPwd" Cyan
    } else {
        Msg "  Password          : (run: az keyvault secret show --vault-name $kvName --name sql-admin-password --query value -o tsv)" Yellow
    }
    Msg "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" DarkGray
    Msg ""
    Msg "Remember to close the rule when done:" Yellow
    Msg "  .\Resources\Azure-Deployment\open-local-sql-firewall.ps1 -Environment $Environment -Close" Gray
    Msg ""
}
