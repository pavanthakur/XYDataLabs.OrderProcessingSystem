param(
    [ValidateSet('local-http', 'local-https', 'phase10-local-http', 'phase10-docker-http', 'docker-dev-http', 'docker-dev-http-tests', 'docker-dev-http-playwright', 'docker-dev-https', 'docker-stg-http', 'docker-stg-https', 'docker-prod-http', 'docker-prod-https', 'all-docker')]
    [string]$Target,

    [string]$Url,

    [switch]$InstallBrowser,

    [switch]$ListTargets,

    [ValidateRange(1000, 300000)]
    [int]$TimeoutMs = 60000,

    [string]$ExpectedTenant,

    [string]$StaleTenant,

    [ValidateRange(5, 300)]
    [int]$UrlReadyTimeoutSeconds = 120,

    [ValidateRange(100, 5000)]
    [int]$UrlReadyPollIntervalMilliseconds = 1000
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$frontendRoot = Join-Path $workspaceRoot 'frontend'
$webRoot = Join-Path $frontendRoot 'apps/web'
$statusWriter = Join-Path $workspaceRoot 'scripts\write-playwright-run-status.ps1'
$environmentKey = switch ($Target) {
    'phase10-local-http' { 'phase10-local-http' }
    'phase10-docker-http' { 'phase10-docker-http' }
    default {
        if ($Target -like 'docker-*') { 'docker-http' } elseif ($Target -eq 'local-https' -or $Url -like 'https://*') { 'local-https' } else { 'local-http' }
    }
}

function Resolve-PlaywrightArtifactRootName
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetName
    )

    switch ($TargetName)
    {
        'local-http' { return 'local-http' }
        'local-https' { return 'local-https' }
        'phase10-local-http' { return 'phase10-local-http' }
        'phase10-docker-http' { return 'phase10-docker-http' }
        'docker-dev-http' { return 'docker-dev-http' }
        'docker-dev-http-tests' { return 'docker-dev-http' }
        'docker-dev-http-playwright' { return 'docker-dev-http' }
        'docker-dev-https' { return 'docker-dev-https' }
        'docker-stg-http' { return 'docker-stg-http' }
        'docker-stg-https' { return 'docker-stg-https' }
        'docker-prod-http' { return 'docker-prod-http' }
        'docker-prod-https' { return 'docker-prod-https' }
        default { return 'local-http' }
    }
}

$knownTargets = [ordered]@{
    'local-http' = 'http://localhost:5173/customers'
    'local-https' = 'https://localhost:5174/customers'
    'phase10-local-http' = 'http://localhost:5173/customers'
    'phase10-docker-http' = 'http://localhost:5022/customers'
    'docker-dev-http' = 'http://localhost:5022/customers'
    'docker-dev-http-tests' = 'http://localhost:5022/customers'
    'docker-dev-http-playwright' = 'http://localhost:5022/customers'
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

function Resolve-PathForWorkspace
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [Parameter(Mandatory = $true)]
        [string]$PathValue
    )

    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $PathValue))
}

function Wait-ForUrlReadiness
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds,

        [Parameter(Mandatory = $true)]
        [int]$PollIntervalMilliseconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    Write-Host "Waiting for smoke target to respond: $Url"

    while ((Get-Date) -lt $deadline)
    {
        try
        {
            $invokeParams = @{
                UseBasicParsing = $true
                Uri = $Url
                TimeoutSec = 5
            }

            if ($PSVersionTable.PSVersion.Major -ge 7 -and $Url -like 'https://*')
            {
                $invokeParams.SkipCertificateCheck = $true
            }

            $response = Invoke-WebRequest @invokeParams
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500)
            {
                Write-Host "Smoke target is ready: $Url"
                return
            }
        }
        catch
        {
        }

        Start-Sleep -Milliseconds $PollIntervalMilliseconds
    }

    throw "Timed out waiting for smoke target readiness at $Url after $TimeoutSeconds seconds."
}

foreach ($targetUrl in $targetUrls)
{
    Write-Host "Running tenant bootstrap smoke test for $($targetUrl.Name): $($targetUrl.Url)" -ForegroundColor Cyan
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey $environmentKey -TaskName "${environmentKey}-smoke" -Status started -Message $targetUrl.Name
    Wait-ForUrlReadiness -Url $targetUrl.Url -TimeoutSeconds $UrlReadyTimeoutSeconds -PollIntervalMilliseconds $UrlReadyPollIntervalMilliseconds

    $playwrightRootPath = Resolve-PathForWorkspace -BasePath $workspaceRoot -PathValue 'TestResults\Playwright'
    $artifactRootName = Resolve-PlaywrightArtifactRootName -TargetName $targetUrl.Name
    $artifactRootPath = Resolve-PathForWorkspace -BasePath $workspaceRoot -PathValue ("TestResults\Playwright\{0}" -f $artifactRootName)
    $latestPointerPath = Resolve-PathForWorkspace -BasePath $workspaceRoot -PathValue ("TestResults\Playwright\{0}\latest-playwright-smoke.txt" -f $artifactRootName)
    $rootPointerPath = Resolve-PathForWorkspace -BasePath $workspaceRoot -PathValue 'TestResults\Playwright\latest-playwright-run.txt'
    New-Item -ItemType Directory -Path $playwrightRootPath -Force | Out-Null
    Set-Content -Path $rootPointerPath -Value $artifactRootPath -Encoding utf8

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
        '--artifact-root'
        $artifactRootPath
        '--latest-pointer-path'
        $latestPointerPath
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
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey $environmentKey -TaskName "${environmentKey}-smoke" -Status failed -Message $targetUrl.Name
        throw "Tenant bootstrap smoke test failed for $($targetUrl.Name)."
    }

    & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey $environmentKey -TaskName "${environmentKey}-smoke" -Status passed -Message $targetUrl.Name
}
