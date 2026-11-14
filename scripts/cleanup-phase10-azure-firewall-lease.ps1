[CmdletBinding()]
param(
    [string]$ManifestPath,
    [string]$ManifestDirectory,
    [string]$ExpectedRunId
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'phase10-azure-firewall-lease.ps1')

function Invoke-AzureCliForFirewallLease {
    param([string[]]$Arguments)
    & az @Arguments 2>&1
    $global:LASTEXITCODE = $LASTEXITCODE
}

if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) {
    $paths = @($ManifestPath)
}
elseif (-not [string]::IsNullOrWhiteSpace($ManifestDirectory) -and -not [string]::IsNullOrWhiteSpace($ExpectedRunId)) {
    $paths = @(Get-ChildItem -LiteralPath $ManifestDirectory -Filter "phase10-sql-firewall-lease-payment-$ExpectedRunId-*.json" -File -ErrorAction SilentlyContinue | ForEach-Object FullName)
}
else {
    throw 'Specify one exact manifest path or a directory and expected run ID.'
}

foreach ($path in $paths) {
    $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace([string]$manifest.subscriptionId)) { throw 'Manifest has no subscription binding; refusing Azure cleanup.' }
    $activeSubscription = az account show --query id -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$activeSubscription)) { throw 'Cannot verify the active Azure subscription; refusing firewall cleanup.' }
    if ([string]$activeSubscription -ne [string]$manifest.subscriptionId) { throw 'Active Azure subscription does not match the lease manifest; refusing firewall cleanup.' }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedRunId)) {
        if ([string]$manifest.runId -ne $ExpectedRunId) { throw 'Manifest run ID does not match the requested cleanup scope.' }
    }
    Remove-Phase10FirewallLease -ManifestPath $path -InvokeAz ${function:Invoke-AzureCliForFirewallLease}
}
Write-Output "Verified cleanup for $($paths.Count) owned firewall lease(s)."
