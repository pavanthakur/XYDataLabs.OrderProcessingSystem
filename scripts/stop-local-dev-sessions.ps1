param(
    [ValidateSet('all', 'http', 'https')]
    [string]$Profile = 'all',

    [int[]]$Ports = @(5010, 5011, 5173, 5174)
)

if ($PSBoundParameters.ContainsKey('Ports') -eq $false)
{
    $Ports = switch ($Profile)
    {
        'http'  { @(5010, 5173) }
        'https' { @(5011, 5174) }
        default { @(5010, 5011, 5173, 5174) }
    }
}

$listeningProcesses = foreach ($port in $Ports)
{
    Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
        Select-Object @{ Name = 'Port'; Expression = { $port } }, OwningProcess -Unique
}

if (-not $listeningProcesses)
{
    $scopeLabel = if ($Profile -eq 'all') { 'local dev sessions' } else { "local $Profile profile sessions" }
    Write-Host "No $scopeLabel found."
    exit 0
}

$processesById = $listeningProcesses |
    Group-Object -Property OwningProcess |
    Sort-Object -Property Name

$scopeLabel = if ($Profile -eq 'all') { 'local dev sessions' } else { "local $Profile profile sessions" }
Write-Host "Stopping ${scopeLabel}:"

foreach ($processGroup in $processesById)
{
    $processId = [int]$processGroup.Name
    $portsForProcess = $processGroup.Group.Port | Sort-Object -Unique
    $portsLabel = ($portsForProcess -join ', ')

    try
    {
        $process = Get-Process -Id $processId -ErrorAction Stop
        Stop-Process -Id $processId -Force -ErrorAction Stop
        Write-Host "  Stopped PID $processId ($($process.ProcessName)) on port(s): $portsLabel"
    }
    catch
    {
        Write-Warning "Failed to stop PID ${processId} on port(s) ${portsLabel}: $($_.Exception.Message)"
    }
}