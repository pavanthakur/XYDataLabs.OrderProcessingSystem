param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('http', 'https')]
    [string]$Profile
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$apiScriptPath = Join-Path $PSScriptRoot 'start-local-api-profile.ps1'
$frontendScriptPath = Join-Path $PSScriptRoot 'start-local-frontend-profile.ps1'
$expectedPorts = if ($Profile -eq 'https') { @(5011, 5174) } else { @(5010, 5173) }

function Get-ListeningPorts {
    param(
        [Parameter(Mandatory = $true)]
        [int[]]$Ports
    )

    return @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $Ports -contains $_.LocalPort } |
        Select-Object -ExpandProperty LocalPort -Unique |
        Sort-Object -Unique)
}

function Test-ExpectedPortsListening {
    param(
        [Parameter(Mandatory = $true)]
        [int[]]$Ports
    )

    $listeningPorts = Get-ListeningPorts -Ports $Ports
    return @($Ports | Where-Object { $listeningPorts -contains $_ }).Count -eq $Ports.Count
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

    return Start-Process `
        -FilePath 'pwsh' `
        -ArgumentList @(
            '-NoProfile'
            '-ExecutionPolicy'
            'Bypass'
            '-File'
            $ScriptPath
            '-Profile'
            $ProfileName
        ) `
        -WorkingDirectory $workspaceRoot `
        -NoNewWindow `
        -PassThru
}

$profileBecameReady = $false
$startupDeadline = (Get-Date).AddSeconds(120)

try
{
    Start-ChildProfileProcess -Name 'API' -ScriptPath $apiScriptPath -ProfileName $Profile | Out-Null
    Start-ChildProfileProcess -Name 'UI' -ScriptPath $frontendScriptPath -ProfileName $Profile | Out-Null

    Write-Host "Local '$Profile' profile is running."
    Write-Host 'Press Ctrl+C to stop the launcher task, or use the stop task to terminate listening processes.'

    while ($true)
    {
        if (-not $profileBecameReady)
        {
            if (Test-ExpectedPortsListening -Ports $expectedPorts)
            {
                $profileBecameReady = $true
                Write-Host "Local '$Profile' profile is ready on ports: $($expectedPorts -join ', ')."
            }
            elseif ((Get-Date) -ge $startupDeadline)
            {
                $listeningPorts = Get-ListeningPorts -Ports $expectedPorts
                $listeningPortsLabel = if ($listeningPorts.Count -gt 0) { $listeningPorts -join ', ' } else { 'none' }
                throw "Timed out waiting for local '$Profile' profile ports. Expected: $($expectedPorts -join ', '). Listening: $listeningPortsLabel."
            }
        }
        elseif (-not (Test-ExpectedPortsListening -Ports $expectedPorts))
        {
            $listeningPorts = Get-ListeningPorts -Ports $expectedPorts
            $listeningPortsLabel = if ($listeningPorts.Count -gt 0) { $listeningPorts -join ', ' } else { 'none' }
            throw "Local '$Profile' profile stopped listening on expected ports. Expected: $($expectedPorts -join ', '). Listening: $listeningPortsLabel."
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