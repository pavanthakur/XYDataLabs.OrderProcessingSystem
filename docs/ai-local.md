**Local AI Tooling — Quick Start & Governance**

Overview
- Local AI tooling is assistive only. Human review is mandatory for any changes suggested by AI.
- Heavy model runs are not part of CI. Local developers may run models with the provided helpers.

Bootstrapping
1. Ensure Ollama is installed and accessible on PATH.
2. Run the low-VRAM helper (one-time per user):
```powershell
.\scripts\set-ollama-lowvram.ps1
# Restart your terminal afterwards
```
3. Create and bootstrap the Aider virtual env:
```powershell
.\scripts\bootstrap-aider-env.ps1
.\scripts\install-git-hooks.ps1
```

Running the tools
- Fast coding mode (low VRAM): `run-ai-fast.cmd`
- Smart architecture mode: `run-ai-smart.cmd`
- Central runner: `ai-runtime\run.ps1 -Mode developer -PromptFile .github\prompts\phase-handoffs\phase-09-microservices-architecture.prompt.md`

Logging & audit
- Prompt runs are logged locally to `local models/prompt-runs/prompt_runs.jsonl` (JSONL). Entries include: `timestamp, model, prompt_file, prompt_hash, output_hash, duration_ms, exit_code, session_id`.

Pre-commit hooks
- Hooks are installed via `scripts\install-git-hooks.ps1` and enforced via `.githooks`.
- The pre-commit hook blocks committing `.env*`, key files, and very large files.

CI
- The repository includes a lightweight prompt validation workflow `.github/workflows/validate-prompts.yml` that checks prompt files for minimal content and obvious secret patterns. It does not execute models.

Governance
- No auto-commit. No automatic push. Logs are local only. Follow PR workflow for human review.
