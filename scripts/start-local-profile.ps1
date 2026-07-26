param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('http', 'https')]
    [string]$Profile,

    [switch]$ReturnWhenReady
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$apiScriptPath = Join-Path $PSScriptRoot 'start-local-api-profile.ps1'
$frontendScriptPath = Join-Path $PSScriptRoot 'start-local-frontend-profile.ps1'
$keycloakScriptPath = Join-Path $PSScriptRoot 'start-local-keycloak.ps1'
$statusWriter = Join-Path $PSScriptRoot 'write-playwright-run-status.ps1'
$logRoot = Join-Path $workspaceRoot 'TestResults\Playwright\local-http'
$sequenceEnvironmentKey = 'local-http'
$apiReadyUrl = if ($Profile -eq 'https') { 'https://localhost:5011/health/ready' } else { 'http://localhost:5010/health/ready' }
$uiReadyUrl = if ($Profile -eq 'https') { 'https://localhost:5174/' } else { 'http://localhost:5173/' }

function Test-HttpReady {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    try {
        $invokeParams = @{
            Uri = $Url
            TimeoutSec = 5
            Method = 'Get'
            ErrorAction = 'Stop'
        }

        if ($PSVersionTable.PSVersion.Major -ge 7 -and $Url -like 'https://*') {
            $invokeParams.SkipCertificateCheck = $true
        }

        $response = Invoke-WebRequest @invokeParams
        return $response.StatusCode -ge 200 -and $response.StatusCode -lt 400
    }
    catch {
        return $false
    }
}

function Start-ChildProfileProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $true)]
        [string]$ProfileName
    )

    Write-Host "Starting $Name for '$ProfileName' profile..."
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $stdoutPath = Join-Path $logRoot ("start-local-profile-{0}-{1}-stdout.log" -f $ProfileName, $Name.ToLowerInvariant())
    $stderrPath = Join-Path $logRoot ("start-local-profile-{0}-{1}-stderr.log" -f $ProfileName, $Name.ToLowerInvariant())

    return Start-Process `
        -FilePath 'pwsh' `
        -ArgumentList @(
            '-NoProfile'
            '-ExecutionPolicy'
            'Bypass'
            '-File'
            $ScriptPath
            "-Profile"
            $ProfileName
        ) `
        -WorkingDirectory $workspaceRoot `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -WindowStyle Hidden `
        -PassThru
}

$profileBecameReady = $false
$startupDeadline = (Get-Date).AddSeconds(120)

try
{
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey $sequenceEnvironmentKey -TaskName 'local-http-env-ready' -Status started -Message $Profile
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $keycloakScriptPath
    if ($LASTEXITCODE -ne 0)
    {
        throw "Failed to start Keycloak for local '$Profile' profile."
    }
    Start-ChildProfileProcess -Name 'API' -ScriptPath $apiScriptPath -ProfileName $Profile | Out-Null
    Start-ChildProfileProcess -Name 'UI' -ScriptPath $frontendScriptPath -ProfileName $Profile | Out-Null

    Write-Host "Local '$Profile' profile bootstrap is running."
    Write-Host "Waiting for API readiness at $apiReadyUrl and UI readiness at $uiReadyUrl."

    while ($true)
    {
        if (-not $profileBecameReady)
        {
            if ((Test-HttpReady -Url $apiReadyUrl) -and (Test-HttpReady -Url $uiReadyUrl))
            {
                $profileBecameReady = $true
                Write-Host "Local '$Profile' profile is ready at $apiReadyUrl and $uiReadyUrl."
                & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey $sequenceEnvironmentKey -TaskName 'local-http-env-ready' -Status passed -Message $Profile
                if ($ReturnWhenReady) {
                    return
                }
                break
            }
            elseif ((Get-Date) -ge $startupDeadline)
            {
                & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey $sequenceEnvironmentKey -TaskName 'local-http-env-ready' -Status failed -Message $Profile
                throw "Timed out waiting for local '$Profile' profile readiness at $apiReadyUrl and $uiReadyUrl."
            }
        }
        elseif (-not ((Test-HttpReady -Url $apiReadyUrl) -and (Test-HttpReady -Url $uiReadyUrl)))
        {
            & pwsh -NoProfile -ExecutionPolicy Bypass -File $statusWriter -EnvironmentKey $sequenceEnvironmentKey -TaskName 'local-http-env-ready' -Status failed -Message $Profile
            throw "Local '$Profile' profile stopped responding at $apiReadyUrl or $uiReadyUrl."
        }

        Start-Sleep -Seconds 1
    }
}
finally
{
    if (-not $profileBecameReady)
    {
        try
        {
            & (Join-Path $PSScriptRoot 'stop-local-dev-sessions.ps1') -Profile $Profile | Out-Null
        }
        catch
        {
        }
    }
}
