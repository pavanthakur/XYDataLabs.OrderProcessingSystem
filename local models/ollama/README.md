# Local Ollama Models — Project Copy

Purpose: keep local Ollama configuration and small guidance for running local models used by Zoo Code and phase handoffs. These files are local development artifacts and are non-authoritative; do not move production governance docs from `docs/` or `.github/` into this folder.

Quick tasks

- Confirm Ollama daemon is running:

```powershell
ollama list
```

- Pull recommended model (example):

```powershell
ollama pull qwen2.5-coder:7b
```

- Recommended model for local Phase 9 work: `qwen2.5-coder:7b` (see `.vscode/ollama-model-config.json`).

Notes

- Do not edit generated caches such as `ollama_models.json` used by other tools. If a tool requires a custom mapping, keep it under `local models/ollama` and document it here.
- Keep files here lightweight: full prompt bodies and governance remain in `.github/prompts/` and `docs/`.

Files in this folder

- `ollama_models.json` — local model index used by local tooling.
- `run-local-ollama.ps1` — helper script to check and pull models.

If you want me to add additional model tags or pull commands, tell me which model tags to include and I'll update `ollama_models.json` and the helper script.