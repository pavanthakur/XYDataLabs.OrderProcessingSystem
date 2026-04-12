param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('http', 'https')]
    [string]$Profile
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$apiScriptPath = Join-Path $PSScriptRoot 'start-local-api-profile.ps1'
$frontendScriptPath = Join-Path $PSScriptRoot 'start-local-frontend-profile.ps1'

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

$apiProcess = $null
$frontendProcess = $null

try
{
    $apiProcess = Start-ChildProfileProcess -Name 'API' -ScriptPath $apiScriptPath -ProfileName $Profile
    $frontendProcess = Start-ChildProfileProcess -Name 'UI' -ScriptPath $frontendScriptPath -ProfileName $Profile

    Write-Host "Local '$Profile' profile is running."
    Write-Host 'Press Ctrl+C to stop the launcher task, or use the stop task to terminate listening processes.'

    while ($true)
    {
        $apiProcess.Refresh()
        $frontendProcess.Refresh()

        if ($apiProcess.HasExited)
        {
            throw "API process exited unexpectedly with code $($apiProcess.ExitCode)."
        }

        if ($frontendProcess.HasExited)
        {
            throw "UI process exited unexpectedly with code $($frontendProcess.ExitCode)."
        }

        Start-Sleep -Seconds 1
    }
}
finally
{
    foreach ($process in @($apiProcess, $frontendProcess))
    {
        if ($null -ne $process)
        {
            try
            {
                $process.Refresh()
                if (-not $process.HasExited)
                {
                    Stop-Process -Id $process.Id -Force -ErrorAction Stop
                }
            }
            catch
            {
            }
        }
    }
}