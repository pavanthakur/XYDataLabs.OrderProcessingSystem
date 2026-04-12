param(
    [ValidateSet('local-http', 'local-https', 'docker-dev-http', 'docker-dev-https', 'docker-stg-http', 'docker-stg-https', 'docker-prod-http', 'docker-prod-https', 'all-docker')]
    [string]$Target,

    [string]$Url,

    [switch]$InstallBrowser,

    [switch]$ListTargets,

    [ValidateRange(1000, 300000)]
    [int]$TimeoutMs = 60000,

    [string]$ExpectedTenant,

    [string]$StaleTenant
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$frontendRoot = Join-Path $workspaceRoot 'frontend'
$webRoot = Join-Path $frontendRoot 'apps/web'

$knownTargets = [ordered]@{
    'local-http' = 'http://localhost:5173/customers'
    'local-https' = 'https://localhost:5174/customers'
    'docker-dev-http' = 'http://localhost:5022/customers'
    'docker-dev-https' = 'https://localhost:5023/customers'
    'docker-stg-http' = 'http://localhost:5032/customers'
    'docker-stg-https' = 'https://localhost:5033/customers'
    'docker-prod-http' = 'http://localhost:5042/customers'
    'docker-prod-https' = 'https://localhost:5043/customers'
}

if ($ListTargets)
{
    Write-Host 'Available tenant bootstrap smoke targets:' -ForegroundColor Cyan
    foreach ($entry in $knownTargets.GetEnumerator())
    {
        Write-Host ("  {0,-18} {1}" -f $entry.Key, $entry.Value)
    }

    Write-Host '  all-docker          Runs every docker-* target in sequence'
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Url) -and [string]::IsNullOrWhiteSpace($Target))
{
    throw 'Specify either -Target or -Url.'
}

if ($InstallBrowser)
{
    Push-Location $webRoot
    try
    {
        npx playwright install chromium
        if ($LASTEXITCODE -ne 0)
        {
            throw 'Playwright browser installation failed.'
        }
    }
    finally
    {
        Pop-Location
    }
}

$targetUrls = @()

if (-not [string]::IsNullOrWhiteSpace($Url))
{
    $targetUrls += @{ Name = 'custom'; Url = $Url }
}
elseif ($Target -eq 'all-docker')
{
    foreach ($entry in $knownTargets.GetEnumerator() | Where-Object { $_.Key -like 'docker-*' })
    {
        $targetUrls += @{ Name = $entry.Key; Url = $entry.Value }
    }
}
else
{
    $targetUrls += @{ Name = $Target; Url = $knownTargets[$Target] }
}

foreach ($targetUrl in $targetUrls)
{
    Write-Host "Running tenant bootstrap smoke test for $($targetUrl.Name): $($targetUrl.Url)" -ForegroundColor Cyan

    $arguments = @(
        '--prefix'
        $frontendRoot
        'run'
        'smoke:web:tenant'
        '--'
        '--url'
        $targetUrl.Url
        '--timeout-ms'
        $TimeoutMs.ToString()
    )

    if (-not [string]::IsNullOrWhiteSpace($ExpectedTenant))
    {
        $arguments += @('--expected-tenant', $ExpectedTenant)
    }

    if (-not [string]::IsNullOrWhiteSpace($StaleTenant))
    {
        $arguments += @('--stale-tenant', $StaleTenant)
    }

    npm @arguments

    if ($LASTEXITCODE -ne 0)
    {
        throw "Tenant bootstrap smoke test failed for $($targetUrl.Name)."
    }
}