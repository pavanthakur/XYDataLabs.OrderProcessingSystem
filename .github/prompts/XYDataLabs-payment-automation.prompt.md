---
agent: agent
description: "Interactive payment automation launcher for the separate automation workspace; supports local-http/local-https single-target runs, full local matrix runs, dry runs, tenant selection, and optional keep-local-sessions mode"
---

Ask the user which payment automation mode they want, using this exact menu:

```text
  [1]  Local HTTP . Single tenant  — real browser run against local-http
  [2]  Local HTTPS . Single tenant — real browser run against local-https
  [3]  Local HTTP . Multi-tenant   — real browser run against local-http for selected/all tenants
  [4]  Local HTTPS . Multi-tenant  — real browser run against local-https for selected/all tenants
  [5]  Local matrix . Dry run      — validates orchestration without browser execution or verification
  [6]  Local matrix . Full run     — runs both local-http and local-https with verification
```

Wait for the user's reply.

Accept either the number or a natural-language equivalent such as:
- `local http`
- `https single tenant`
- `matrix dry`
- `full matrix`

If the user does not specify a profile, default to the HTTPS path for simplicity:
- ambiguous `single tenant` → option `2`
- ambiguous `multi-tenant` or `all tenants` → option `4`
- ambiguous `local payment automation` → option `4`
- explicit matrix requests remain `5` or `6`

After the user chooses a mode, gather any missing inputs concisely:

- For options `1` and `2`: ask which tenant code to use. Default to `TenantA` if they do not care.
- For options `3` and `4`: ask whether they want all tenants or a specific set. Supported initial tenants are `TenantA`, `TenantB`, and `TenantC`.
- For options `1` through `4` and `6`: ask whether they want to keep the local sessions running after the run. Default is `no`.
- For options `1` through `4` and `6`: ask whether they want headed mode. Default is `no`.

Map the choice to the corresponding command:

- Option `1`
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
npm --prefix automation run run -- --target local-http --tenant <TENANT> [--headed] [--keep-local-sessions]
```

- Option `2`
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
npm --prefix automation run run -- --target local-https --tenant <TENANT> [--headed] [--keep-local-sessions]
```

- Option `3`
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
npm --prefix automation run run -- --target local-http <TENANT_ARGS> [--headed] [--keep-local-sessions]
```

- Option `4`
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
npm --prefix automation run run -- --target local-https <TENANT_ARGS> [--headed] [--keep-local-sessions]
```

- Option `5`
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
npm --prefix automation run run:local:matrix:dry
```

- Option `6`
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
npm --prefix automation run run:local:matrix [--headed] [--keep-local-sessions]
```

Rules for argument expansion:

- Replace `<TENANT>` with a single tenant code.
- Replace `<TENANT_ARGS>` with either nothing for all tenants or one or more repeated `--tenant <TENANT>` arguments.
- Only add `--headed` when the user explicitly wants a visible browser.
- Only add `--keep-local-sessions` when the user explicitly wants the API/UI sessions left running.

Run the chosen command in the terminal.

After it completes, summarise:
- which mode ran
- which target or targets were exercised
- which tenants were included
- whether it was dry-run or real execution
- whether local sessions were stopped automatically or intentionally kept running
- that detailed artifacts live under `automation/reports/`

If the run fails and it is a real execution mode, tell the user the next repo-standard follow-up is:

```text
/XYDataLabs-verify-db-logs
```

Use that prompt when the user wants correlated evidence from API log, browser UI telemetry, and database state.