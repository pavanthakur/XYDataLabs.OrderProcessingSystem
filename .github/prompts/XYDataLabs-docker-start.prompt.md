---
agent: agent
description: Interactive Docker/dotnet launcher for the XY Order Processing System — ask which environment and profile to start, then run it
---

Ask the user which option they want, using this exact menu:

```
  [1]  Dev . HTTP    — Docker  — API: http://localhost:5020/swagger  (recommended for daily dev)
  [2]  Dev . HTTPS   — Docker  — API: https://localhost:5021/swagger
  [3]  Stg . HTTP    — Docker  — API: http://localhost:5030/swagger  (validate before Azure push)
  [4]  Stg . HTTPS   — Docker  — API: https://localhost:5031/swagger
  [5]  Prod . HTTP   — Docker  — API: http://localhost:5040/swagger  ⚠ prod config
  [6]  Prod . HTTPS  — Docker  — API: https://localhost:5041/swagger ⚠ prod config
  [7]  Local . HTTP  — dotnet run (no Docker) — API: http://localhost:5010/swagger
  [8]  Local . HTTPS — dotnet run (no Docker) — API: https://localhost:5011/swagger
  [0]  Stop a running Docker stack
```

Wait for the user's reply (a number 0-8, or words like "dev http" / "staging https").

Map their reply to the corresponding number (e.g. "dev http" → 1, "staging http" → 3, "local" → 7).

Then run in terminal:
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem\Resources\Docker
.\start-docker-menu.ps1 -Choice <N>
```

After the command completes, summarise:
- Which option was started
- The API and UI URLs to open
- For Docker options: note that the first build takes ~2 minutes; subsequent runs are faster
- For dotnet run options (7/8): remind the user that VS F5 with 'Http Profile' or 'Https Profile' gives full debugger support (breakpoints, hot reload)
