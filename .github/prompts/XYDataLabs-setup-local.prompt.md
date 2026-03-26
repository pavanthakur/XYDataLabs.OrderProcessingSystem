---
agent: agent
description: Bootstrap local development environment after a fresh git clone — creates .env.local, sets dotnet user-secrets, trusts HTTPS dev cert
---

Run the local bootstrap script. It will prompt you to choose SQL Server and HTTPS cert passwords on first run, then save them to `.env.local` for all future runs.

Run in terminal:
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
.\scripts\setup-local.ps1
```

After it completes, confirm the output shows all steps as `[ok]` or `[--] (already done)`.

Then summarise to the user:
- **VS F5**: select `http` or `https` profile (not `docker-*` profiles) → API at http://localhost:5010/swagger, UI at http://localhost:5012
- **Docker**: `.\Resources\Docker\start-docker.ps1 -Environment dev -Profile http`
- **If you need to change passwords later**: `.\scripts\setup-local.ps1 -Force`
- **Real OpenPay sandbox credentials**: edit `Resources\Docker\.env.local` directly, then re-run `dotnet user-secrets set` for the API project
