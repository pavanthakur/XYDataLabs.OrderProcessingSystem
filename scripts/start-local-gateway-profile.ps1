param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('http', 'docker-dev-http', 'docker-stg-http', 'docker-prod-http')]
    [string]$Profile,

    [bool]$OpenBrowser = $true,

    [ValidateRange(5, 300)]
    [int]$ApiStartupTimeoutSeconds = 90,

    [ValidateRange(100, 5000)]
    [int]$ApiPollIntervalMilliseconds = 1000
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$gatewayProjectPath = Join-Path $workspaceRoot 'XYDataLabs.OrderProcessingSystem.Gateway'
$gatewayBaseUrl = 'http://localhost:5080'
$gatewayHealthUrl = "$gatewayBaseUrl/health/alive"
$gatewayLaunchUrl = "$gatewayBaseUrl/swagger/index.html"

$profileSettings = switch ($Profile)
{
    'http'
    {
        @{
            ApiReadinessUrl = 'http://localhost:5010/health/ready'
            UiReadinessUrl = 'http://localhost:5173/'
        }
    }
    'docker-dev-http'
    {
        @{
            ApiReadinessUrl = 'http://localhost:5020/health/ready'
            UiReadinessUrl = 'http://localhost:5022/'
        }
    }
    'docker-stg-http'
    {
        @{
            ApiReadinessUrl = 'http://localhost:5030/health/ready'
            UiReadinessUrl = 'http://localhost:5032/'
        }
    }
    'docker-prod-http'
    {
        @{
            ApiReadinessUrl = 'http://localhost:5040/health/ready'
            UiReadinessUrl = 'http://localhost:5042/'
        }
    }
}

$apiReadinessUrl = $profileSettings.ApiReadinessUrl
$uiReadinessUrl = $profileSettings.UiReadinessUrl

function Wait-ForEndpointReadiness {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds,

        [Parameter(Mandatory = $true)]
        [int]$PollIntervalMilliseconds,

        [Parameter(Mandatory = $true)]
        [string]$DisplayName
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    Write-Host "Waiting for $DisplayName readiness at $Url ..."

    while ((Get-Date) -lt $deadline)
    {
        try
        {
            $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 5
            if ($response.StatusCode -eq 200)
            {
                Write-Host "$DisplayName is ready at $Url"
                return
            }
        }
        catch
        {
        }

        Start-Sleep -Milliseconds $PollIntervalMilliseconds
    }

    throw "Timed out waiting for $DisplayName readiness at $Url after $TimeoutSeconds seconds."
}

function Start-BrowserLaunchMonitor {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReadinessUrl,

        [Parameter(Mandatory = $true)]
        [string]$LaunchUrl,

        [Parameter(Mandatory = $true)]
        [bool]$ShouldOpenBrowser,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds,

        [Parameter(Mandatory = $true)]
        [int]$PollIntervalMilliseconds
    )

    if (-not $ShouldOpenBrowser)
    {
        return
    }

    Start-Job -ScriptBlock {
        param(
            [string]$ReadyEndpoint,
            [string]$BrowserUrl,
            [int]$TimeoutSeconds,
            [int]$PollIntervalMilliseconds
        )

        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

        while ((Get-Date) -lt $deadline)
        {
            try
            {
                $response = Invoke-WebRequest -UseBasicParsing -Uri $ReadyEndpoint -TimeoutSec 5
                if ($response.StatusCode -eq 200)
                {
                    Start-Process $BrowserUrl
                    return
                }
            }
            catch
            {
            }

            Start-Sleep -Milliseconds $PollIntervalMilliseconds
        }
    } -ArgumentList $ReadinessUrl, $LaunchUrl, $TimeoutSeconds, $PollIntervalMilliseconds | Out-Null

    Write-Host "Browser will open when gateway is ready: $LaunchUrl"
}

Wait-ForEndpointReadiness `
    -Url $apiReadinessUrl `
    -TimeoutSeconds $ApiStartupTimeoutSeconds `
    -PollIntervalMilliseconds $ApiPollIntervalMilliseconds `
    -DisplayName 'API'

Wait-ForEndpointReadiness `
    -Url $uiReadinessUrl `
    -TimeoutSeconds $ApiStartupTimeoutSeconds `
    -PollIntervalMilliseconds $ApiPollIntervalMilliseconds `
    -DisplayName 'UI'

Write-Host ''
Write-Host 'Gateway:'
Write-Host $gatewayBaseUrl
Write-Host 'Gateway API path:'
Write-Host $gatewayLaunchUrl
Write-Host 'Gateway profile:'
Write-Host $Profile
Write-Host ''

Start-BrowserLaunchMonitor `
    -ReadinessUrl $gatewayHealthUrl `
    -LaunchUrl $gatewayLaunchUrl `
    -ShouldOpenBrowser $OpenBrowser `
    -TimeoutSeconds $ApiStartupTimeoutSeconds `
    -PollIntervalMilliseconds $ApiPollIntervalMilliseconds

Push-Location $gatewayProjectPath
try
{
    dotnet run --launch-profile $Profile
}
finally
{
    Pop-Location
}