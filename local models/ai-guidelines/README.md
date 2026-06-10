# Local AI Guidelines (Developer Copy)

Purpose: a local, developer-oriented copy of the repository AI operating model and quick validation steps. This is for local experimentation only — canonical governance lives in `docs/AI-OPERATING-MODEL.md` and `.github/`.

Quick rules

- Keep repo-shared AI changes in `.github/` and `docs/`.
- Before committing any prompt/agent/instruction change, run:

```powershell
pwsh scripts/validate-ai-customization.ps1
```

- If you must defer a required update, add an entry to `docs/internal/DEFERRED-WORK-LOG.md` with owner and review date.

Local conventions

- Names for local artifacts: use `local models/ollama` for Ollama-specific config and `local models/ai-guidelines` for local guidance only.
- Do not move `zoocode/` or `docs/` content into these folders; keep `zoocode/` untouched as requested.

If you'd like, I can generate a checklist or small validation script that runs the same checks as the repo's `validate-ai-customization` workflow locally — say yes and I'll add `local models/ai-guidelines/validate-local-ai.ps1`.