param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('http', 'https')]
    [string]$Profile,

    [bool]$OpenBrowser = $true,

    [ValidateRange(5, 300)]
    [int]$StartupTimeoutSeconds = 90,

    [ValidateRange(100, 5000)]
    [int]$PollIntervalMilliseconds = 1000
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$apiProjectPath = Join-Path $workspaceRoot 'XYDataLabs.OrderProcessingSystem.API'
$uiPort = if ($Profile -eq 'https') { 5174 } else { 5173 }

$uiUrl = if ($Profile -eq 'https') { "https://localhost:$uiPort/" } else { "http://localhost:$uiPort/" }
$apiBaseUrl = if ($Profile -eq 'https') { 'https://localhost:5011' } else { 'http://localhost:5010' }
$apiUrl = "$apiBaseUrl/swagger"

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
                $invokeParams = @{
                    UseBasicParsing = $true
                    Uri = $ReadyEndpoint
                    TimeoutSec = 5
                }

                if ($PSVersionTable.PSVersion.Major -ge 7 -and $ReadyEndpoint -like 'https://*')
                {
                    $invokeParams.SkipCertificateCheck = $true
                }

                $response = Invoke-WebRequest @invokeParams
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

    Write-Host "Browser will open when API is ready: $LaunchUrl"
}

Write-Host ''
Write-Host 'UI:'
Write-Host $uiUrl
Write-Host 'API:'
Write-Host $apiUrl
Write-Host ''

Start-BrowserLaunchMonitor `
    -ReadinessUrl "$apiBaseUrl/health/ready" `
    -LaunchUrl $apiUrl `
    -ShouldOpenBrowser $OpenBrowser `
    -TimeoutSeconds $StartupTimeoutSeconds `
    -PollIntervalMilliseconds $PollIntervalMilliseconds

Push-Location $apiProjectPath
try
{
    dotnet run --launch-profile $Profile
}
finally
{
    Pop-Location
}