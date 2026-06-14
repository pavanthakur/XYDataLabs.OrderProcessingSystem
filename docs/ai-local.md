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
- Prompt runs are logged locally to `ai-runtime/prompt-runs/prompt_runs.jsonl` (JSONL). Entries include: `timestamp, model, prompt_file, prompt_hash, output_hash, duration_ms, exit_code, session_id`.

Session correlation (traceability)
- Each run has a `session_id` that links engine execution and logger entries. `ai-runtime/run.ps1` accepts an optional `-SessionId` parameter; when not provided it generates a deterministic id of the form `YYYY-MM-DDTHH:MM:SSZ-xxxxxx`.
- To run and inspect a session end-to-end:
	1. Run the central entrypoint (optionally provide a session id):

```powershell
pwsh -NoProfile -File ai-runtime/run.ps1 -Mode developer -SessionId "2026-06-14T12:34:22Z-abc123"
```

	2. After completion, open `ai-runtime/prompt-runs/prompt_runs.jsonl` and search for the `session_id` value. The corresponding entry contains the prompt file, model used, runtime exit code, and output hash.

	3. If the engine fell back to Ollama, the `session_id` is still propagated so fallback traces are linked.

CI connection
- The repository CI runs `scripts/validate-prompts.ps1` (workflow: `.github/workflows/validate-prompts.yml`) on PRs and pushes that touch prompt files, `ai-runtime/`, or `scripts/`.
- The CI validator enforces the runtime contract (prompt locations, size limits, no obvious secret patterns) but does not execute models. Use the `session_id` to correlate CI failures with local runs when debugging.

Pre-commit hooks
- Hooks are installed via `scripts\install-git-hooks.ps1` and enforced via `.githooks`.
- The pre-commit hook blocks committing `.env*`, key files, and very large files.

CI
- The repository includes a lightweight prompt validation workflow `.github/workflows/validate-prompts.yml` that checks prompt files for minimal content and obvious secret patterns. It does not execute models.

Governance
- No auto-commit. No automatic push. Logs are local only. Follow PR workflow for human review.

Troubleshooting
- If a run produces no log entry: ensure `ai-runtime/prompt-runs/` is writable and `ai-runtime/config.ps1` is loading (the runner sources it automatically).
- If CI rejects a prompt: run `pwsh -NoProfile -File scripts/validate-prompts.ps1` locally to get the same validator output.
- To trace a fallback from Aider → Ollama: run with a known `-SessionId` and search for that id in `ai-runtime/prompt-runs/prompt_runs.jsonl`.
