#Requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('local-http', 'local-https', 'docker-http', 'docker-https', 'azure-https')]
    [string]$EnvironmentKey,

    [Parameter(Mandatory = $true)]
    [string]$TaskName,

    [Parameter(Mandatory = $true)]
    [ValidateSet('started', 'passed', 'failed', 'info')]
    [string]$Status,

    [string]$Message = ''
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$environmentRoot = Join-Path $workspaceRoot ("TestResults\Playwright\{0}" -f $EnvironmentKey)
$commonLogPath = Join-Path $environmentRoot 'sequence-summary.log'

New-Item -ItemType Directory -Path $environmentRoot -Force | Out-Null

function Get-IstTimestamp {
    $utcNow = [DateTimeOffset]::UtcNow
    $istZone = [System.TimeZoneInfo]::FindSystemTimeZoneById('India Standard Time')
    $istNow = [System.TimeZoneInfo]::ConvertTime($utcNow, $istZone)
    return $istNow.ToString('o')
}

$line = '[{0}] task={1} status={2}' -f (Get-IstTimestamp), $TaskName, $Status
if (-not [string]::IsNullOrWhiteSpace($Message)) {
    $line = "$line message=$Message"
}

Add-Content -Path $commonLogPath -Value $line
Write-Host $line
