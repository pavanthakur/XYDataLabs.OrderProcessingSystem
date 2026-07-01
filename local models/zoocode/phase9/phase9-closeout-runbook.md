# Phase 9 Closeout Runbook

Phase 9 closeout is a strict gate sequence, not another slice-planning loop.
The goal is to finish the remaining closure work with one deterministic runner, one log trail, and one stop-on-first-blocker rule.

## What Phase 9 Closure Means

- Build is green.
- Architecture tests are green.
- Gateway tests are green.
- Integration tests are green.
- Playwright is green.
- Payment matrix evidence is captured.
- The closeout log clearly records pass/fail for every gate.

## What Is Kept

- `local models/zoocode/phase9/run-phase9-closeout-core.ps1`
- `local models/zoocode/phase9/run-phase9-closeout-playwright.ps1`
- `local models/zoocode/phase9/run-phase9-payment-e2e.ps1`
- `local models/zoocode/phase9/run-phase9-payment-matrix.ps1`
- `local models/zoocode/phase9/run-phase9-docker-bootstrap.ps1`
- `local models/zoocode/phase9/run-phase9-docker-profile.ps1`
- `local models/zoocode/phase9/start-ollama-controlled.ps1`
- `local models/zoocode/phase9/watch-phase9-logs.ps1`

## What Can Be Retired After Closure

- Per-slice launch wrappers that only duplicate the main runner:
  - `launch-phase9-9.2-e2e.ps1`
  - `launch-phase9-9.3-e2e.ps1`
  - `launch-phase9-9.4-e2e.ps1`
  - `launch-phase9-9.5-e2e.ps1`
  - `launch-phase9-9.6-e2e.ps1`
  - `launch-phase9-9.7-e2e.ps1`
  - `launch-phase9-9.8-e2e.ps1`
  - `launch-phase9-9.9-e2e.ps1`
  - `launch-phase9-9.10-e2e.ps1`
  - `launch-phase9-9.11-e2e.ps1`
  - `launch-phase9-9.12-e2e.ps1`
  - `launch-phase9-9.13-e2e.ps1`
  - `launch-phase9-9.14-e2e.ps1`
  - `launch-phase9-9.15-e2e.ps1`
  - `launch-phase9-9.16-e2e.ps1`
  - `launch-phase9-9.17-e2e.ps1`
- Old per-slice proof markdown that is only historical evidence:
  - `phase9_architect*.md`
  - `phase9_development*.md`
  - `phase9_review*.md`
  - `phase9_automation*.md`
- `_temp` history files after the final closeout evidence is captured.

## Strict Execution Order

1. Build
2. Architecture tests
3. Gateway tests
4. Integration tests
5. Playwright
6. Payment matrix
7. Closeout log and summary

## Stop / Fix / Rerun Rule

- Stop on the first real blocker.
- Fix only that blocker.
- Rerun the same gate.
- Do not skip ahead.
- Do not declare closure from a partial run.

## Recommended Closure Commands

### Full closeout runner

```powershell
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9-closeout-core.ps1" -NoRestore
```

### Playwright gate

```powershell
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9-closeout-playwright.ps1" -Target docker-dev-http -StabilizationDelaySeconds 180
```

### Payment matrix gate

```powershell
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9-payment-matrix.ps1"
```

## Log Evidence to Keep

- `local models/zoocode/phase9/_temp/phase9-e2e.log`
- `local models/zoocode/phase9/_temp/launch-9.3.log`
- `local models/zoocode/phase9/_temp/launch-9.4.log`
- `local models/zoocode/phase9/_temp/launch-9.5.log`
- `local models/zoocode/phase9/_temp/launch-9.6.log`
- `local models/zoocode/phase9/_temp/launch-9.7.log`
- `local models/zoocode/phase9/_temp/launch-9.8.log`
- `local models/zoocode/phase9/_temp/launch-9.9.log`
- final closeout summary log produced by the closeout runner

## Notes

- The slice runners are evidence generators, not the closure target.
- Ollama stays as the controlled model runtime for the scripts.
- If a gate fails, the log for that gate is the primary triage source.
- `SharedContracts` remains deferred unless a later phase explicitly needs it.
- After Phase 9 closeout, the next roadmap sequence is:
  - Phase 10: HTTP + Blob, Service Bus, SQL hardening, Key Vault
  - Phase 11: Durable Functions and database autonomy
  - Phase 12: Redis cache policy and App Configuration
  - Post-14 horizons: Azure AI Search and Azure OpenAI as optional expansions
