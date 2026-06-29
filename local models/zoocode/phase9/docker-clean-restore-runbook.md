# Phase 9 Docker Clean Restore Runbook

Use this when Docker Desktop has been restored to a blank or partially blank state and you want the
Phase 9 dev stack back in a deterministic way.

## Quick Checklist

1. Close Docker Desktop fully.
2. Open an elevated PowerShell window.
3. Repair `C:\Users\Pavan\.docker` permissions if needed.
4. Verify `docker version` and `docker info`.
5. Run the strict Docker profile start.
6. Run Playwright closeout or the full cold bootstrap.

## 1. Confirm Docker Desktop is running

Open Docker Desktop and wait until the engine is healthy.

Then verify in an elevated PowerShell window:

```powershell
docker version
docker info
```

Expected:
- `docker version` shows both client and server
- `docker info` succeeds and shows the Linux engine

## 2. Repair `C:\Users\Pavan\.docker` if needed

If Docker Desktop was restored from backup and `.docker` is missing, inaccessible, or has bad ACLs,
recreate it from scratch and grant your user full control.

Run these commands in an elevated PowerShell window:

```powershell
$dockerHome = 'C:\Users\Pavan\.docker'
$user = "$env:USERDOMAIN\$env:USERNAME"

if (Test-Path $dockerHome) {
    takeown /F $dockerHome /R /D Y
    icacls $dockerHome /grant:r "${user}:F" /T
    icacls $dockerHome /inheritance:e
} else {
    New-Item -ItemType Directory -Path $dockerHome | Out-Null
    icacls $dockerHome /grant:r "${user}:F"
}
```

Verify write access:

```powershell
New-Item -Path 'C:\Users\Pavan\.docker\_write_test.txt' -ItemType File -Force | Out-Null
Remove-Item 'C:\Users\Pavan\.docker\_write_test.txt' -Force
```

If Docker Desktop recreated some subfolders but access is still broken, repair the common
subdirectories explicitly:

```powershell
New-Item -ItemType Directory -Path 'C:\Users\Pavan\.docker\buildx' -Force | Out-Null
New-Item -ItemType Directory -Path 'C:\Users\Pavan\.docker\contexts' -Force | Out-Null
New-Item -ItemType Directory -Path 'C:\Users\Pavan\.docker\models' -Force | Out-Null
New-Item -ItemType Directory -Path 'C:\Users\Pavan\.docker\modules' -Force | Out-Null
New-Item -ItemType Directory -Path 'C:\Users\Pavan\.docker\scout' -Force | Out-Null

icacls 'C:\Users\Pavan\.docker' /grant:r "${user}:F" /T
```

## 3. Start a strict Docker dev profile

From the repo root:

```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9-docker-profile.ps1" -Environment dev -Profile http -Reset -Strict
```

This is the deterministic startup path for the dev HTTP stack.

## 4. Run Playwright closeout

After the Docker dev profile is healthy:

```powershell
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9-closeout-playwright.ps1" -Target docker-dev-http -StabilizationDelaySeconds 180
```

## 5. Full cold bootstrap path

If you want Docker startup plus Playwright in one command:

```powershell
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9-docker-bootstrap.ps1" -DockerStartupTimeoutSeconds 300 -StabilizationDelaySeconds 180
```

## 6. Environment/profile launcher

To start any Docker profile directly:

```powershell
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9-docker-profile.ps1" -Environment dev -Profile http
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9-docker-profile.ps1" -Environment dev -Profile https
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9-docker-profile.ps1" -Environment stg -Profile http
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9-docker-profile.ps1" -Environment stg -Profile https
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9-docker-profile.ps1" -Environment prod -Profile http
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9-docker-profile.ps1" -Environment prod -Profile https
```

## 7. VS Code task shortcuts

Use these when you want the task label instead of the script:

- `1 Run: 11 Docker Dev Http Profile`
- `1 Run: 12 Docker Dev Https Profile`
- `1 Run: 21 Docker Stg Http Profile`
- `1 Run: 22 Docker Stg Https Profile`
- `1 Run: 31 Docker Prod Http Profile`
- `1 Run: 32 Docker Prod Https Profile`

## 8. Logging

The full cold bootstrap writes a transcript to:

```text
Q:\GIT\TestAppXY_OrderProcessingSystem\.tmp\phase9-cold-bootstrap.log
```

Use that log first when triaging a failed restore.

## Copy-Paste Commands

Use this short sequence when you already know Docker Desktop is closed and you just want to restore and run:

```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\repair-docker-home.ps1"
docker version
docker info
```

Then continue with the strict profile and Playwright:

```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9-docker-profile.ps1" -Environment dev -Profile http -Reset -Strict
docker compose --env-file .env.local -f docker-compose.database.yml -f docker-compose.dev.yml --profile http up -d ui-dev-http
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9-closeout-playwright.ps1" -Target docker-dev-http -StabilizationDelaySeconds 180
```
