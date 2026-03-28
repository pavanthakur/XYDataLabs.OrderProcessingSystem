---
agent: agent
description: "Quality gate after any feature, task, script, or fix — automatically runs build (warnings-as-errors), all unit tests, and a secret/credential scan; then checks 6 categories: documented, guardrailed, unit tested, integration tested, automated in CI, and AI context current"
---

Run this after completing any feature, task, script, fix, or workflow change.

## Step 0 — Run automated checks first

Run all three blocks in the terminal before evaluating the checklist. Use the results to fill in categories 2, 3, and 4 below.

**Build (warnings as errors):**
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
dotnet build XYDataLabs.OrderProcessingSystem.sln --warnaserror /warnnotaserror:NU1701 "/consoleloggerparameters:NoSummary;ForceNoAlign"
```
> `NU1701` is suppressed — it is a known pre-existing warning from `Openpay 1.0.25` (a .NET Framework-only package); all other warnings are errors.

**All test projects:**
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
dotnet test tests/XYDataLabs.OrderProcessingSystem.Domain.Tests --no-build --logger "console;verbosity=minimal"
dotnet test tests/XYDataLabs.OrderProcessingSystem.Application.Tests --no-build --logger "console;verbosity=minimal"
dotnet test tests/XYDataLabs.OrderProcessingSystem.API.Tests --no-build --logger "console;verbosity=minimal"
dotnet test tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests --no-build --logger "console;verbosity=minimal"
```

**Secret / credential scan (no hardcoded values in source):**
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
$patterns = @('password\s*=\s*"[^<{]', 'Password\s*=\s*"[^<{]', 'secret\s*=\s*"', 'connectionstring.*password=(?!.*\$\{)', 'privatekey\s*=\s*"')
$extensions = '*.cs','*.json','*.yml','*.yaml','*.ps1','*.bicep'
$hits = Get-ChildItem -Recurse -Include $extensions -Exclude '*.example','*.template' |
    Select-String -Pattern ($patterns -join '|') -CaseSensitive:$false |
    Where-Object { $_.Path -notmatch '\\(obj|bin|publish|node_modules)\\' }
if ($hits) { $hits | Format-Table Path, LineNumber, Line -AutoSize; Write-Host "SECRET SCAN: $($hits.Count) potential hit(s) — review each" -ForegroundColor Red }
else { Write-Host 'SECRET SCAN: clean' -ForegroundColor Green }
```

---

## 1. Documentation

- [ ] Is the feature/change described in the relevant README, guide, or copilot-instructions.md?
- [ ] If a new script was added: does `scripts/README.md` (or the owning folder README) document it with usage, parameters, and purpose?
- [ ] If a new workflow was added: does `.github/workflows/README.md` reference it?
- [ ] If a new prompt was added: does `.github/prompts/README.md` document it, and is it listed in `copilot-instructions.md` §9?
- [ ] If a new architectural decision was made: is there an ADR in `docs/architecture/decisions/`?

## 2. Guardrails *(use secret scan results from Step 0)*

- [ ] Secret scan above: **0 hits** — no hardcoded passwords, keys, or connection strings
- [ ] If a new domain rule or constraint exists: is it enforced in the Domain layer (not just a comment)?
- [ ] If inputs cross a system boundary (API, UI, script parameter): is there validation?
- [ ] If the change could affect another tenant: is tenant isolation preserved?
- [ ] If a script has destructive behaviour: does it require confirmation or a `-Force` / `-WhatIf` flag?

## 3. Unit Tests *(use test results from Step 0)*

- [ ] Build: **0 errors, 0 warnings**
- [ ] Does the new/changed domain entity have unit tests in `Domain.Tests`?
- [ ] Does the new/changed CQRS handler have unit tests in `Application.Tests`?
- [ ] `Domain.Tests` passed (from Step 0 results)
- [ ] `Application.Tests` passed (from Step 0 results)

## 4. Integration / Architecture Tests *(use test results from Step 0)*

- [ ] Does the new/changed controller have tests in `API.Tests`?
- [ ] If an EF Core migration was added: has it been verified against the local DB?
- [ ] `API.Tests` passed (from Step 0 results)
- [ ] `Architecture.Tests` passed — layer boundaries still enforced (from Step 0 results)
- [ ] If this change touches `Program.cs` environment gates (`isDocker`, `isAzure`, `profileSuffix`, `runtimeSuffix`): gate logic is extracted to a testable helper and all 7 cells in the ADR-010 Runtime Context Matrix have been validated — either by unit test, `WebApplicationFactory` integration test, or physical log verification via `/XYDataLabs-verify-db-logs`. Reference: `docs/architecture/decisions/ADR-010-runtime-environment-detection.md`

## 5. Automation / CI-CD

- [ ] If a new script automates a task: can it run unattended (no interactive prompts in CI mode)?
- [ ] If a new workflow was added: is there a corresponding path trigger in the right workflow file?
- [ ] If something was previously manual: is it now captured in a script or workflow?
- [ ] If a VS Code task or Copilot prompt would help discoverability: has one been created?

## 6. Copilot Context

- [ ] Is `copilot-instructions.md` still accurate? (Run `/XYDataLabs-context-audit` if unsure)
- [ ] Are relevant `/memories/repo/` files up to date with any new resource names or conventions?

---

For each unchecked item, either:
- **Fix it now** (preferred) — implement the missing piece, then mark it done
- **Record it** — add a TODO comment with a clear owner and reason for deferral

## Summary

Report results in this table:

| Category | Result | Notes |
|---|---|---|
| Build | ✅ / ❌ | |
| Secret scan | ✅ clean / ❌ N hits | |
| Unit tests | ✅ / ❌ | |
| Integration/Arch tests | ✅ / ❌ | |
| Documentation | ✅ / ⚠️ gaps fixed / ❌ deferred | |
| Guardrails | ✅ / ⚠️ gaps fixed / ❌ deferred | |
| Automation | ✅ / ⚠️ gaps fixed / ❌ deferred | |
| Copilot context | ✅ / ⚠️ gaps fixed / ❌ deferred | |
