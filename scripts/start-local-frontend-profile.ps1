param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('standalone', 'http', 'https')]
    [string]$Profile,

    [object]$OpenBrowser = $false,

    [ValidateRange(5, 300)]
    [int]$ApiStartupTimeoutSeconds = 90,

    [ValidateRange(100, 5000)]
    [int]$ApiPollIntervalMilliseconds = 1000
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$uiPort = if ($Profile -eq 'https') { 5174 } else { 5173 }
$keycloakAuthority = 'http://localhost:8081'
$keycloakRealm = 'xy-phase9'
$keycloakClientId = 'xy-order-processing-local-web'
$keycloakUsername = 'tenant-admin'
$keycloakPassword = $env:KEYCLOAK_TENANT_ADMIN_PASSWORD
if ([string]::IsNullOrWhiteSpace($keycloakPassword))
{
    $envFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local'
    if (Test-Path $envFile)
    {
        $keycloakPasswordLine = Get-Content $envFile | Where-Object { $_ -like 'KEYCLOAK_TENANT_ADMIN_PASSWORD=*' } | Select-Object -First 1
        if ($keycloakPasswordLine)
        {
            $keycloakPassword = $keycloakPasswordLine.Substring('KEYCLOAK_TENANT_ADMIN_PASSWORD='.Length)
        }
    }

    if ([string]::IsNullOrWhiteSpace($keycloakPassword))
    {
        throw "KEYCLOAK_TENANT_ADMIN_PASSWORD must be set for the local Keycloak bootstrap flow."
    }
}

$uiUrl = if ($Profile -eq 'https') { "https://localhost:$uiPort/" } else { "http://localhost:$uiPort/" }
$apiBaseUrl = if ($Profile -eq 'https') { 'https://localhost:5011' } else { 'http://localhost:5010' }
$apiUrl = "$apiBaseUrl/swagger"

function Wait-ForApiReadiness {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds,

        [Parameter(Mandatory = $true)]
        [int]$PollIntervalMilliseconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    Write-Host "Waiting for API readiness at $Url ..."

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
            if ($response.StatusCode -eq 200)
            {
                Write-Host "API is ready at $Url"
                return
            }
        }
        catch
        {
        }

        Start-Sleep -Milliseconds $PollIntervalMilliseconds
    }

    throw "Timed out waiting for API readiness at $Url after $TimeoutSeconds seconds."
}

function Start-BrowserLaunchMonitor {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [object]$ShouldOpenBrowser,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds,

        [Parameter(Mandatory = $true)]
        [int]$PollIntervalMilliseconds
    )

    $shouldOpen = $false
    if ($ShouldOpenBrowser -is [bool]) {
        $shouldOpen = $ShouldOpenBrowser
    }
    elseif ($ShouldOpenBrowser -is [string]) {
        $shouldOpen = $ShouldOpenBrowser.Trim().ToLowerInvariant() -in @('true', '$true', '1', 'yes', 'y')
    }
    elseif ($null -ne $ShouldOpenBrowser) {
        $shouldOpen = [bool]$ShouldOpenBrowser
    }

    if (-not $shouldOpen)
    {
        return
    }

    Start-Job -ScriptBlock {
        param(
            [string]$LaunchUrl,
            [int]$TimeoutSeconds,
            [int]$PollIntervalMilliseconds
        )

        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

        while ((Get-Date) -lt $deadline)
        {
            try
            {
                $invokeParams = @{
                    UseBasicParsing = $true
                    Uri = $LaunchUrl
                    TimeoutSec = 5
                }

                if ($PSVersionTable.PSVersion.Major -ge 7 -and $LaunchUrl -like 'https://*')
                {
                    $invokeParams.SkipCertificateCheck = $true
                }

                $response = Invoke-WebRequest @invokeParams
                if ($response.StatusCode -eq 200)
                {
                    Start-Process $LaunchUrl
                    return
                }
            }
            catch
            {
            }

            Start-Sleep -Milliseconds $PollIntervalMilliseconds
        }
    } -ArgumentList $Url, $TimeoutSeconds, $PollIntervalMilliseconds | Out-Null

    Write-Host "Browser will open when UI is ready: $Url"
}

if ($Profile -ne 'standalone')
{
    Wait-ForApiReadiness `
        -Url "$apiBaseUrl/health/ready" `
        -TimeoutSeconds $ApiStartupTimeoutSeconds `
        -PollIntervalMilliseconds $ApiPollIntervalMilliseconds
}

Write-Host ''
Write-Host 'You can use below'
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
$env:VITE_KEYCLOAK_AUTHORITY = $keycloakAuthority
$env:VITE_KEYCLOAK_REALM = $keycloakRealm
$env:VITE_KEYCLOAK_CLIENT_ID = $keycloakClientId
$env:VITE_KEYCLOAK_USERNAME = $keycloakUsername
$env:VITE_KEYCLOAK_PASSWORD = $keycloakPassword

Start-BrowserLaunchMonitor `
    -Url $uiUrl `
    -ShouldOpenBrowser $OpenBrowser `
    -TimeoutSeconds $ApiStartupTimeoutSeconds `
    -PollIntervalMilliseconds $ApiPollIntervalMilliseconds

$npmArguments = @(
    '--prefix'
    (Join-Path $workspaceRoot 'frontend')
    'run'
    'dev:web'
)

npm @npmArguments
