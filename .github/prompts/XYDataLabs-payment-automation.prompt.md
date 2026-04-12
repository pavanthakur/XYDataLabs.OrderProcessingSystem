---
agent: agent
description: "Interactive payment automation launcher for the separate automation workspace; supports local, Docker, and Azure single-target runs, local/Docker/Azure matrix runs, dry runs, tenant selection, headed mode, and optional keep-local-sessions for local targets"
---

Ask the user which payment automation mode they want, using this exact menu:

```text
  [1]   Local HTTP . Target run      — real browser run against local-http
  [2]   Local HTTPS . Target run     — real browser run against local-https
  [3]   Local matrix . Dry run       — validates local orchestration without browser execution or verification
  [4]   Local matrix . Full run      — runs both local-http and local-https with verification
  [5]   Docker Dev HTTP . Target run — real browser run against docker-dev-http
  [6]   Docker Dev HTTPS . Target run — real browser run against docker-dev-https
  [7]   Docker Stg HTTP . Target run — real browser run against docker-stg-http
  [8]   Docker Stg HTTPS . Target run — real browser run against docker-stg-https
  [9]   Docker Prod HTTP . Target run — real browser run against docker-prod-http
  [10]  Docker Prod HTTPS . Target run — real browser run against docker-prod-https
  [11]  Docker matrix . Dry run      — validates all six Docker targets without browser execution or verification
  [12]  Docker matrix . Full run     — runs dev, stg, and prod HTTP/HTTPS Docker targets with verification
  [13]  Azure Dev . Target run       — real browser run against azure-dev with App Insights verification
  [14]  Azure Stg . Target run       — real browser run against azure-stg with App Insights verification
  [15]  Azure Prod . Target run      — real browser run against azure-prod with App Insights verification
  [16]  Azure matrix . Dry run       — validates all three Azure targets without browser execution or verification
  [17]  Azure matrix . Full run      — runs dev, stg, and prod Azure targets with App Insights verification
```

Wait for the user's reply.

Accept either the number or a natural-language equivalent such as:
- `local http`
- `https target run`
- `matrix dry`
- `full matrix`
- `docker dev http`
- `docker prod https`
- `docker matrix`
- `azure dev`
- `azure prod`
- `azure matrix`

If the user does not specify a profile, default to the HTTPS path for simplicity:
- ambiguous `single target` or `single tenant` → option `2`
- ambiguous `multi-tenant` or `all tenants` → option `2`
- ambiguous `local payment automation` → option `4`
- ambiguous `docker payment automation` → option `6`
- ambiguous `azure payment automation` → option `13`
- explicit matrix requests remain `3`, `4`, `11`, `12`, `16`, or `17`

After the user chooses a mode, gather any missing inputs concisely:

- For options `1`, `2`, `5` through `10`, and `13` through `15`: ask whether they want all tenants or a specific set. Supported initial tenants are `TenantA`, `TenantB`, and `TenantC`. Default is all tenants if they do not care.
- For options `3`, `4`, `11`, `12`, `16`, and `17`: ask whether they want all tenants or a specific set. Supported initial tenants are `TenantA`, `TenantB`, and `TenantC`. Default is all tenants if they do not care.
- For options `1`, `2`, and `4`: ask whether they want to keep the local sessions running after the run. Default is `no`.
- For options `1`, `2`, `4`, `5` through `10`, `12`, `13` through `15`, and `17`: ask whether they want headed mode. Default is `no`.

Map the choice to the corresponding command:

- Option `1`
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
npm --prefix automation run run -- --target local-http <TENANT_ARGS> [--headed] [--keep-local-sessions]
```

- Option `2`
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
npm --prefix automation run run -- --target local-https <TENANT_ARGS> [--headed] [--keep-local-sessions]
```

- Option `3`
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
npm --prefix automation run run:local:matrix:dry <TENANT_ARGS>
```

- Option `4`
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
npm --prefix automation run run:local:matrix <TENANT_ARGS> [--headed] [--keep-local-sessions]
```

- Option `5`
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
npm --prefix automation run run -- --target docker-dev-http <TENANT_ARGS> [--headed]
```

- Option `6`
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
npm --prefix automation run run -- --target docker-dev-https <TENANT_ARGS> [--headed]
```

- Option `7`
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
npm --prefix automation run run -- --target docker-stg-http <TENANT_ARGS> [--headed]
```

- Option `8`
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
npm --prefix automation run run -- --target docker-stg-https <TENANT_ARGS> [--headed]
```

- Option `9`
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
npm --prefix automation run run -- --target docker-prod-http <TENANT_ARGS> [--headed]
```

- Option `10`
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
npm --prefix automation run run -- --target docker-prod-https <TENANT_ARGS> [--headed]
```

- Option `11`
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
npm --prefix automation run run:docker:matrix:dry <TENANT_ARGS>
```

- Option `12`
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
npm --prefix automation run run:docker:matrix <TENANT_ARGS> [--headed]
```

- Option `13`
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
npm --prefix automation run run -- --target azure-dev <TENANT_ARGS> [--headed]
```

- Option `14`
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
npm --prefix automation run run -- --target azure-stg <TENANT_ARGS> [--headed]
```

- Option `15`
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
npm --prefix automation run run -- --target azure-prod <TENANT_ARGS> [--headed]
```

- Option `16`
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
npm --prefix automation run run:azure:matrix:dry <TENANT_ARGS>
```

- Option `17`
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
npm --prefix automation run run:azure:matrix <TENANT_ARGS> [--headed]
```

Rules for argument expansion:

- Replace `<TENANT_ARGS>` with either nothing for all tenants or one or more repeated `--tenant <TENANT>` arguments.
- Only add `--headed` when the user explicitly wants a visible browser.
- Only add `--keep-local-sessions` when the user explicitly wants the API/UI sessions left running.

Run the chosen command in the terminal.

After it completes, summarise:
- which mode ran
- which target or targets were exercised
- which tenants were included
- whether it was dry-run or real execution
- whether local sessions were stopped automatically or intentionally kept running when a local mode was used
- that detailed artifacts live under `automation/reports/`

If the run fails and it is a real execution mode, tell the user the next repo-standard follow-up is:

```text
/XYDataLabs-verify-db-logs
```

Use that prompt when the user wants correlated evidence from API log, browser UI telemetry, and database state.