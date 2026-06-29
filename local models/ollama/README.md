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

- Recommended installed models for local Phase 9 work:
	- Architecture: `qwen3-8b-64k:latest`, then `qwen3-8b-32k:latest`, then `qwen3:8b`.
	- Development: `qwen2.5-coder:7b`, then `qwen2.5-coder:7b-instruct-q4_K_M`, then `qwen3:8b`.
	- Quick/debugging: `qwen3:8b`, then `qwen2.5-coder:3b`.

Avoid routing Continue or Zoo Code to tags that are not present in `ollama list`; missing tags can stall on pull attempts or fail with a manifest error.

Notes

- Do not edit generated caches such as `ollama_models.json` used by other tools. If a tool requires a custom mapping, keep it under `local models/ollama` and document it here.
- Keep files here lightweight: full prompt bodies and governance remain in `.github/prompts/` and `docs/`.

Files in this folder

- `ollama_models.json` — local model index used by local tooling.
- `run-local-ollama.ps1` — helper script to check and pull models.

If you want me to add additional model tags or pull commands, tell me which model tags to include and I'll update `ollama_models.json` and the helper script.