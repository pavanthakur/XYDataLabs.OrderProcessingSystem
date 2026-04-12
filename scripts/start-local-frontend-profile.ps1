param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('standalone', 'http', 'https')]
    [string]$Profile
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$uiPort = if ($Profile -eq 'https') { 5174 } else { 5173 }

$uiUrl = if ($Profile -eq 'https') { "https://localhost:$uiPort/" } else { "http://localhost:$uiPort/" }
$apiBaseUrl = if ($Profile -eq 'https') { 'https://localhost:5011' } else { 'http://localhost:5010' }
$apiUrl = "$apiBaseUrl/swagger"

Write-Host ''
Write-Host 'UI:'
Write-Host $uiUrl
Write-Host 'API:'
Write-Host $apiUrl
Write-Host ''

if ($Profile -eq 'https')
{
    $envFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local'
    if (-not (Test-Path $envFile))
    {
        throw 'Missing Resources\Docker\.env.local. Run scripts/setup-local.ps1 first.'
    }

    $certPasswordLine = Get-Content $envFile | Where-Object { $_ -like 'LOCAL_CERT_PASSWORD=*' } | Select-Object -First 1
    if (-not $certPasswordLine)
    {
        throw 'LOCAL_CERT_PASSWORD not found in Resources\Docker\.env.local.'
    }

    $env:ORDERPROCESSING_DEV_SERVER_USE_HTTPS = 'true'
    $env:ORDERPROCESSING_DEV_SERVER_PFX_PATH = (Resolve-Path (Join-Path $workspaceRoot 'Resources\Certificates\aspnetapp.pfx')).Path
    $env:ORDERPROCESSING_DEV_SERVER_PFX_PASSWORD = $certPasswordLine.Substring('LOCAL_CERT_PASSWORD='.Length)
}
else
{
    $env:ORDERPROCESSING_DEV_SERVER_USE_HTTPS = 'false'
}

$env:ORDERPROCESSING_DEV_SERVER_PORT = "$uiPort"
$env:ORDERPROCESSING_API_BASE_URL = $apiBaseUrl
npm --prefix .\frontend run dev:web