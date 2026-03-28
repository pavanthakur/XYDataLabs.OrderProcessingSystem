---
agent: agent
description: "After a fresh git clone: runs setup-local.ps1 to create .env.local, set dotnet user-secrets, and trust the HTTPS dev cert; then summarises VS F5 ports (API :5010, UI :5012), Docker launch commands, and how OpenPay sandbox credentials are sourced"
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
- **OpenPay sandbox credentials**: `setup-local.ps1` tries Azure Key Vault first, then prompts interactively. Stored in user-secrets (for `dotnet run`) and `.env.local` (for Docker). RedirectUrl is auto-resolved from `ApiSettings:UI` — no manual config needed.
