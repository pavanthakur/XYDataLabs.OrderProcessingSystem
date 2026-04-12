param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('http', 'https')]
    [string]$Profile
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$apiProjectPath = Join-Path $workspaceRoot 'XYDataLabs.OrderProcessingSystem.API'

$uiUrl = if ($Profile -eq 'https') { 'https://localhost:5173/' } else { 'http://localhost:5173/' }
$apiUrl = if ($Profile -eq 'https') { 'https://localhost:5011/swagger' } else { 'http://localhost:5010/swagger' }

Write-Host ''
Write-Host 'UI:'
Write-Host $uiUrl
Write-Host 'API:'
Write-Host $apiUrl
Write-Host ''

Push-Location $apiProjectPath
try
{
    dotnet run --launch-profile $Profile
}
finally
{
    Pop-Location
}