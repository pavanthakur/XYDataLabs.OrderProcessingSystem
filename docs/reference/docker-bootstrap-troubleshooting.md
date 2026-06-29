# Docker Bootstrap Troubleshooting

Use this note when `Resources/Docker/start-docker.ps1` fails during local bootstrap.

## What usually breaks

1. Docker daemon is not running or the shell cannot reach it.
2. SQL Server takes longer to become healthy on reused volumes.
3. `NuGet.Config` points at Windows-only local folders, which breaks containerized restore.
4. A real compile error exists in the application layer and only shows up after restore succeeds.

## Fixes that should stay in place

- Keep `Resources/Docker/start-docker.ps1` using a longer health wait for SQL-backed profiles.
- Keep `scripts/verify-local-db-ready.ps1` on a longer timeout so SQL startup does not false-fail.
- Keep `NuGet.Config` portable for container builds. It should not depend on local Windows package folders.
- Treat Docker build failures after restore as real code issues, not timing issues.

## Current guardrails

- Default bootstrap timeout is `180` seconds.
- SQL volume reuse can delay health status.
- Docker dev profiles use compose-managed SQL Server and Redis.

## Recommended bootstrap command

```powershell
powershell -ExecutionPolicy Bypass -File "Resources\Docker\start-docker.ps1" -Environment dev -Profile http -Reset -Strict -HealthTimeoutSec 180
```

## Recovery checklist

1. Confirm Docker Desktop is running.
2. Confirm the shell can talk to the Docker daemon.
3. Check `NuGet.Config` for portable restore sources.
4. Check SQL container health before assuming the app is broken.
5. If restore succeeds but build fails, inspect the compile errors directly.
