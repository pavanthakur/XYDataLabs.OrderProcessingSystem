param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('http', 'https')]
    [string]$Profile,

    [switch]$DisableStartupDdl,

    [switch]$Phase10DockerBacking,

    [object]$OpenBrowser = $false,

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
$envFile = Join-Path $workspaceRoot 'Resources\Docker\.env.local'

function Get-EnvLocalValue {
    param([Parameter(Mandatory = $true)][string]$Name)

    $environmentValue = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if (-not [string]::IsNullOrWhiteSpace($environmentValue))
    {
        return $environmentValue.Trim()
    }

    if (-not (Test-Path -LiteralPath $envFile))
    {
        return $null
    }

    $line = Get-Content -LiteralPath $envFile |
        Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*=" } |
        Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($line))
    {
        return $null
    }

    $value = (($line -split '=', 2)[1]).Trim()
    if ($value.StartsWith('"') -and $value.EndsWith('"') -and $value.Length -ge 2)
    {
        $value = $value.Substring(1, $value.Length - 2)
    }

    if ($value.StartsWith("'") -and $value.EndsWith("'") -and $value.Length -ge 2)
    {
        $value = $value.Substring(1, $value.Length - 2)
    }

    return $value.Trim()
}

function Set-ProcessEnvironmentValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value)
    {
        Remove-Item "Env:$Name" -ErrorAction SilentlyContinue
        return
    }

    [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
}

function Set-Phase10DockerBackingEnvironment {
    $localSqlPassword = Get-EnvLocalValue -Name 'LOCAL_SQL_PASSWORD'
    if ([string]::IsNullOrWhiteSpace($localSqlPassword))
    {
        throw "LOCAL_SQL_PASSWORD must be present in Resources\\Docker\\.env.local for the Phase 10 Docker-backed local API profile."
    }

    $sharedConnectionString = "Server=localhost,1433;Database=OrderProcessingSystem_Dev;User Id=sa;Password=$localSqlPassword;Encrypt=False;TrustServerCertificate=True;MultipleActiveResultSets=true;"
    $dedicatedConnectionString = "Server=localhost,1433;Database=OrderProcessingSystem_TenantC_Dev;User Id=sa;Password=$localSqlPassword;Encrypt=False;TrustServerCertificate=True;MultipleActiveResultSets=true;"

    Set-ProcessEnvironmentValue -Name 'ConnectionStrings__OrderProcessingSystemDbConnection' -Value $sharedConnectionString
    Set-ProcessEnvironmentValue -Name 'ConnectionStrings__TenantRegistryDbConnection' -Value $sharedConnectionString
    Set-ProcessEnvironmentValue -Name 'DedicatedTenantConnectionStrings__TenantC' -Value $dedicatedConnectionString
    Set-ProcessEnvironmentValue -Name 'ConnectionStrings__Redis' -Value 'localhost:6379'
    Set-ProcessEnvironmentValue -Name 'AzureWebJobsStorage' -Value (Get-EnvLocalValue -Name 'LOCAL_AZURITE_HOST_CONNECTION_STRING')
    Set-ProcessEnvironmentValue -Name 'ServiceBus__Enabled' -Value (Get-EnvLocalValue -Name 'LOCAL_SERVICEBUS_ENABLED')
    Set-ProcessEnvironmentValue -Name 'ServiceBus__ConnectionString' -Value (Get-EnvLocalValue -Name 'LOCAL_SERVICEBUS_HOST_CONNECTION_STRING')
    Set-ProcessEnvironmentValue -Name 'ServiceBus__TopicName' -Value (Get-EnvLocalValue -Name 'LOCAL_SERVICEBUS_TOPIC_NAME')
    Set-ProcessEnvironmentValue -Name 'ServiceBus__SubscriptionName' -Value (Get-EnvLocalValue -Name 'LOCAL_SERVICEBUS_INVENTORY_SUBSCRIPTION_NAME')
    Set-ProcessEnvironmentValue -Name 'ServiceBus__DeadLetterTopicName' -Value (Get-EnvLocalValue -Name 'LOCAL_SERVICEBUS_DLQ_TOPIC_NAME')
    Set-ProcessEnvironmentValue -Name 'ServiceBus__DeadLetterSubscriptionName' -Value (Get-EnvLocalValue -Name 'LOCAL_SERVICEBUS_DLQ_SUBSCRIPTION_NAME')
    Set-ProcessEnvironmentValue -Name 'ServiceBus__ReplayRequestQueueName' -Value (Get-EnvLocalValue -Name 'LOCAL_SERVICEBUS_REPLAY_REQUEST_QUEUE_NAME')
    Set-ProcessEnvironmentValue -Name 'ServiceBus__ReplayEnabled' -Value (Get-EnvLocalValue -Name 'LOCAL_SERVICEBUS_REPLAY_ENABLED')
    Set-ProcessEnvironmentValue -Name 'IdentityProvider__Enabled' -Value 'true'
    Set-ProcessEnvironmentValue -Name 'IdentityProvider__ClientSecret' -Value (Get-EnvLocalValue -Name 'LOCAL_KEYCLOAK_BACKEND_CLIENT_SECRET')
    Set-ProcessEnvironmentValue -Name 'OpenPay__MerchantId' -Value (Get-EnvLocalValue -Name 'LOCAL_OPENPAY_MERCHANT_ID')
    Set-ProcessEnvironmentValue -Name 'OpenPay__PublicKey' -Value (Get-EnvLocalValue -Name 'LOCAL_OPENPAY_PUBLIC_KEY')
    Set-ProcessEnvironmentValue -Name 'OpenPay__PrivateKey' -Value (Get-EnvLocalValue -Name 'LOCAL_OPENPAY_PRIVATE_KEY')
    Set-ProcessEnvironmentValue -Name 'OpenPay__DeviceSessionId' -Value (Get-EnvLocalValue -Name 'LOCAL_OPENPAY_DEVICE_SESSION_ID')
    Set-ProcessEnvironmentValue -Name 'Razorpay__MerchantId' -Value (Get-EnvLocalValue -Name 'LOCAL_RAZORPAY_MERCHANT_ID')
    Set-ProcessEnvironmentValue -Name 'Razorpay__PrivateKey' -Value (Get-EnvLocalValue -Name 'LOCAL_RAZORPAY_PRIVATE_KEY')
    Set-ProcessEnvironmentValue -Name 'Webhooks__Razorpay__Secret' -Value (Get-EnvLocalValue -Name 'LOCAL_RAZORPAY_WEBHOOK_SECRET')
    Set-ProcessEnvironmentValue -Name 'Webhooks__OpenPay__Secret' -Value (Get-EnvLocalValue -Name 'LOCAL_OPENPAY_WEBHOOK_SECRET')
    Set-ProcessEnvironmentValue -Name 'PaymentProviders__UseDeterministicAdapters' -Value (Get-EnvLocalValue -Name 'LOCAL_DETERMINISTIC_PAYMENT_ADAPTERS')
    Set-ProcessEnvironmentValue -Name 'PaymentProviders__TenantA__OpenPay__PrivateKey' -Value (Get-EnvLocalValue -Name 'LOCAL_OPENPAY_PRIVATE_KEY')
    Set-ProcessEnvironmentValue -Name 'PaymentProviders__TenantB__OpenPay__PrivateKey' -Value (Get-EnvLocalValue -Name 'LOCAL_OPENPAY_PRIVATE_KEY')
    Set-ProcessEnvironmentValue -Name 'PaymentProviders__TenantC__OpenPay__PrivateKey' -Value (Get-EnvLocalValue -Name 'LOCAL_OPENPAY_PRIVATE_KEY')
    Set-ProcessEnvironmentValue -Name 'PaymentProviders__TenantA__Razorpay__PrivateKey' -Value (Get-EnvLocalValue -Name 'LOCAL_RAZORPAY_PRIVATE_KEY')
    Set-ProcessEnvironmentValue -Name 'PaymentProviders__TenantB__Razorpay__PrivateKey' -Value (Get-EnvLocalValue -Name 'LOCAL_RAZORPAY_PRIVATE_KEY')
    Set-ProcessEnvironmentValue -Name 'PaymentProviders__TenantC__Razorpay__PrivateKey' -Value (Get-EnvLocalValue -Name 'LOCAL_RAZORPAY_PRIVATE_KEY')
}

function Start-BrowserLaunchMonitor {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReadinessUrl,

        [Parameter(Mandatory = $true)]
        [string]$LaunchUrl,

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
    $previousDisableStartupDdl = [Environment]::GetEnvironmentVariable('Phase10__DisableStartupDdl', 'Process')
    if ($DisableStartupDdl)
    {
        [Environment]::SetEnvironmentVariable('Phase10__DisableStartupDdl', 'true', 'Process')
    }

    if ($Phase10DockerBacking)
    {
        Set-Phase10DockerBackingEnvironment
    }

    dotnet run --no-restore --no-build --launch-profile $Profile
}
finally
{
    if ($DisableStartupDdl)
    {
        if ($null -ne $previousDisableStartupDdl)
        {
            [Environment]::SetEnvironmentVariable('Phase10__DisableStartupDdl', $previousDisableStartupDdl, 'Process')
        }
        else
        {
            Remove-Item Env:Phase10__DisableStartupDdl -ErrorAction SilentlyContinue
        }
    }

    Pop-Location
}
