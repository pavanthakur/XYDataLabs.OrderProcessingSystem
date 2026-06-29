param(
    [string]$DockerHome = 'C:\Users\Pavan\.docker'
)

$ErrorActionPreference = 'Stop'
$user = "$env:USERDOMAIN\$env:USERNAME"

Write-Host "Repairing Docker home: $DockerHome" -ForegroundColor Cyan

if (Test-Path $DockerHome) {
    takeown /F $DockerHome /R /D Y | Out-Host
    icacls $DockerHome /grant:r "${user}:F" /T | Out-Host
    icacls $DockerHome /inheritance:e | Out-Host
} else {
    New-Item -ItemType Directory -Path $DockerHome | Out-Null
    icacls $DockerHome /grant:r "${user}:F" | Out-Host
}

New-Item -ItemType Directory -Path (Join-Path $DockerHome 'buildx') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $DockerHome 'contexts') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $DockerHome 'models') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $DockerHome 'modules') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $DockerHome 'scout') -Force | Out-Null

$testFile = Join-Path $DockerHome '_write_test.txt'
New-Item -Path $testFile -ItemType File -Force | Out-Null
Remove-Item $testFile -Force

Write-Host "Docker home repair and write test completed successfully." -ForegroundColor Green
