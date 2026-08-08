param(
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'dev',

    [string]$ResourceGroupName,
    [string]$GatewayContainerAppName,
    [string]$UiContainerAppName,
    [string]$GatewayFqdn,
    [string]$UiFqdn,
    [string]$SummaryPath,
    [int]$Attempts = 18,
    [int]$DelaySeconds = 10
)

$ErrorActionPreference = 'Stop'

$envSuffix = if ($Environment -eq 'staging') { 'stg' } else { $Environment }
$resourceGroup = if ([string]::IsNullOrWhiteSpace($ResourceGroupName)) { "rg-orderprocessing-$envSuffix" } else { $ResourceGroupName }
$gatewayApp = if ([string]::IsNullOrWhiteSpace($GatewayContainerAppName)) { "orderprocessing-gate-$envSuffix" } else { $GatewayContainerAppName }
$uiApp = if ([string]::IsNullOrWhiteSpace($UiContainerAppName)) { "orderprocessing-ui-$envSuffix" } else { $UiContainerAppName }

function Resolve-ContainerAppFqdn {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $fqdn = az containerapp show `
        --resource-group $resourceGroup `
        --name $Name `
        --query 'properties.configuration.ingress.fqdn' `
        -o tsv 2>$null

    if ([string]::IsNullOrWhiteSpace($fqdn)) {
        throw "Could not resolve ingress FQDN for Container App '$Name' in resource group '$resourceGroup'."
    }

    return $fqdn.Trim()
}

function Invoke-SmokeHttp {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter(Mandatory)]
        [scriptblock]$Validate
    )

    $lastStatus = ''
    $lastPreview = ''

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri $Url -Method Get -MaximumRedirection 5 -TimeoutSec 30 -UseBasicParsing
            $lastStatus = [string][int]$response.StatusCode
            $body = [string]$response.Content
            $lastPreview = if ($body.Length -gt 1000) { $body.Substring(0, 1000) } else { $body }

            $validation = & $Validate $response $body
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400 -and $validation.Success) {
                return [pscustomobject]@{
                    Name = $Name
                    Passed = $true
                    Status = $lastStatus
                    Detail = $validation.Detail
                    Url = $Url
                }
            }

            Write-Host "Attempt $attempt/$Attempts did not pass for $Name. Status=$lastStatus. Detail=$($validation.Detail)"
        }
        catch {
            $lastStatus = 'exception'
            $lastPreview = $_.Exception.Message
            Write-Host "Attempt $attempt/$Attempts failed for $Name. $lastPreview"
        }

        if ($attempt -lt $Attempts) {
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    return [pscustomobject]@{
        Name = $Name
        Passed = $false
        Status = $lastStatus
        Detail = "Did not pass after $Attempts attempt(s). Last response preview: $lastPreview"
        Url = $Url
    }
}

function Test-JsonField {
    param(
        [string]$Body,
        [string[]]$RequiredFields
    )

    try {
        $json = $Body | ConvertFrom-Json -ErrorAction Stop
        foreach ($field in $RequiredFields) {
            if (-not ($json.PSObject.Properties.Name -contains $field)) {
                return [pscustomobject]@{
                    Success = $false
                    Detail = "Missing JSON field '$field'."
                }
            }
        }

        return [pscustomobject]@{
            Success = $true
            Detail = "JSON contains required fields: $($RequiredFields -join ', ')."
        }
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Detail = "Response was not valid JSON: $($_.Exception.Message)"
        }
    }
}

function Test-GatewayBackendRoutes {
    param(
        [string]$Body,
        [string]$CurrentEnvironmentSuffix
    )

    try {
        $json = $Body | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Detail = "Response was not valid JSON: $($_.Exception.Message)"
        }
    }

    $routes = @($json.routes)
    if ($routes.Count -eq 0) {
        return [pscustomobject]@{
            Success = $false
            Detail = 'Gateway health payload did not include any route summaries.'
        }
    }

    $localhostRoute = $routes | Where-Object { $_ -match 'localhost' } | Select-Object -First 1
    if ($null -ne $localhostRoute) {
        return [pscustomobject]@{
            Success = $false
            Detail = "Gateway backend route contract failed: route '$localhostRoute' still points at localhost."
        }
    }

    $shortNameRoute = $routes | Where-Object {
        $_ -match "-> http://orderprocessing-(ord|inv|notif|ui)-$CurrentEnvironmentSuffix$"
    } | Select-Object -First 1

    if ($null -ne $shortNameRoute) {
        return [pscustomobject]@{
            Success = $false
            Detail = "Gateway backend route contract failed: route '$shortNameRoute' still uses a bare short name."
        }
    }

    $requiredClusters = @(
        'orders-cluster/orders-primary',
        'inventory-cluster/inventory-primary',
        'notifications-cluster/notifications-primary',
        'ui-cluster/ui-primary'
    )

    foreach ($requiredCluster in $requiredClusters) {
        $matchingRoute = $routes | Where-Object { $_ -like "$requiredCluster*" } | Select-Object -First 1
        if ($null -eq $matchingRoute) {
            return [pscustomobject]@{
                Success = $false
                Detail = "Gateway backend route contract failed: missing route summary for '$requiredCluster'."
            }
        }

        if ($matchingRoute -notmatch '-> https://.*\.azurecontainerapps\.io') {
            return [pscustomobject]@{
                Success = $false
                Detail = "Gateway backend route contract failed: route '$matchingRoute' is not using an ACA HTTPS FQDN target."
            }
        }
    }

    return [pscustomobject]@{
        Success = $true
        Detail = 'Gateway backend route contract passed with ACA HTTPS FQDN targets.'
    }
}

if ([string]::IsNullOrWhiteSpace($GatewayFqdn)) {
    $GatewayFqdn = Resolve-ContainerAppFqdn -Name $gatewayApp
}

if ([string]::IsNullOrWhiteSpace($UiFqdn)) {
    $UiFqdn = Resolve-ContainerAppFqdn -Name $uiApp
}

$gatewayHealthUrl = "https://$GatewayFqdn/"
$gatewayApiUrl = "https://$GatewayFqdn/api/v1/Info/runtime-configuration"
$uiUrl = "https://$UiFqdn/customers"
$uiProxyApiUrl = "https://$UiFqdn/api/v1/Info/runtime-configuration"
$startedUtc = [DateTimeOffset]::UtcNow

Write-Host "Running Phase 10 Azure runtime smoke for '$Environment'..."
Write-Host "Gateway: $gatewayHealthUrl"
Write-Host "Orders API through gateway: $gatewayApiUrl"
Write-Host "UI: $uiUrl"
Write-Host "UI API proxy: $uiProxyApiUrl"

$checks = @()
$checks += Invoke-SmokeHttp -Name 'Gateway health' -Url $gatewayHealthUrl -Validate {
    param($response, $body)
    $jsonCheck = Test-JsonField -Body $body -RequiredFields @('service', 'status', 'acceptedHost')
    if (-not $jsonCheck.Success) { return $jsonCheck }
    if ($body -notmatch '"status"\s*:\s*"healthy"') {
        return [pscustomobject]@{ Success = $false; Detail = "Gateway response did not report healthy status." }
    }
    [pscustomobject]@{ Success = $true; Detail = "Gateway accepted the Azure host and reported healthy." }
}

$checks += Invoke-SmokeHttp -Name 'Gateway backend route contract' -Url $gatewayHealthUrl -Validate {
    param($response, $body)
    Test-GatewayBackendRoutes -Body $body -CurrentEnvironmentSuffix $envSuffix
}

$checks += Invoke-SmokeHttp -Name 'Gateway routed API runtime configuration' -Url $gatewayApiUrl -Validate {
    param($response, $body)
    Test-JsonField -Body $body -RequiredFields @('activeTenantCode', 'tenantHeaderName', 'availableTenants')
}

$checks += Invoke-SmokeHttp -Name 'UI static route' -Url $uiUrl -Validate {
    param($response, $body)
    if ($body -match '<!doctype html' -or $body -match '<div id="root"') {
        return [pscustomobject]@{ Success = $true; Detail = "UI served the React shell." }
    }
    [pscustomobject]@{ Success = $false; Detail = "UI response did not look like the React shell." }
}

$checks += Invoke-SmokeHttp -Name 'UI API proxy runtime configuration' -Url $uiProxyApiUrl -Validate {
    param($response, $body)
    Test-JsonField -Body $body -RequiredFields @('activeTenantCode', 'tenantHeaderName', 'availableTenants')
}

$completedUtc = [DateTimeOffset]::UtcNow
$failed = @($checks | Where-Object { -not $_.Passed })
$status = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }

$summary = @()
$summary += '## Phase 10 Azure Runtime Smoke'
$summary += ''
$summary += "**Status:** $status"
$summary += ('**Environment:** `{0}`' -f $Environment)
$summary += ('**Azure Resource Suffix:** `{0}`' -f $envSuffix)
$summary += ('**Resource Group:** `{0}`' -f $resourceGroup)
$summary += ('**Started UTC:** `{0}`' -f $startedUtc.ToString('O'))
$summary += ('**Completed UTC:** `{0}`' -f $completedUtc.ToString('O'))
$summary += ''
$summary += '### Endpoints'
$summary += ''
$summary += '| Endpoint | URL |'
$summary += '|---|---|'
$summary += "| Gateway Health | $gatewayHealthUrl |"
$summary += "| Gateway Routed API | $gatewayApiUrl |"
$summary += "| UI Static Route | $uiUrl |"
$summary += "| UI API Proxy | $uiProxyApiUrl |"
$summary += ''
$summary += '### Checks'
$summary += ''
$summary += '| Check | Result | HTTP Status | Detail |'
$summary += '|---|---|---|---|'
foreach ($check in $checks) {
    $result = if ($check.Passed) { 'PASS' } else { 'FAIL' }
    $detail = ([string]$check.Detail).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
    $summary += "| $($check.Name) | $result | $($check.Status) | $detail |"
}
$summary += ''
$summary += '### Next Operator Action'
$summary += ''
$summary += if ($failed.Count -eq 0) {
    'Gateway health, gateway-routed API, UI static route, and UI API proxy bootstrap are verified.'
}
else {
    'Inspect the failed endpoint detail, then check Container App revision status and application logs before rerunning.'
}

$summaryText = $summary -join [Environment]::NewLine
Write-Output $summaryText

if (-not [string]::IsNullOrWhiteSpace($SummaryPath)) {
    $summaryDirectory = Split-Path -Parent $SummaryPath
    if (-not [string]::IsNullOrWhiteSpace($summaryDirectory)) {
        New-Item -ItemType Directory -Path $summaryDirectory -Force | Out-Null
    }

    $summaryText | Set-Content -LiteralPath $SummaryPath -Encoding UTF8
}

if ($failed.Count -gt 0) {
    exit 1
}

exit 0
