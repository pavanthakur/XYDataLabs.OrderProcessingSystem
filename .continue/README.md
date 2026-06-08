Continue config: local model picker

This note documents the verified local Continue setup for this workstation. The active config file is user-scoped:

```text
C:\Users\Pavan\.continue\config.yaml
```

Shared phase handoff guideline:

```text
.github\prompts\phase-handoffs\local-model-phase-handoff-guide.md
```

Verified Continue picker entries:

- `Nomic Embed Local [semantic]` -> `nomic-embed-text:latest`
- `Qwen 8B (Fast) Local [fast]` -> `qwen3-8b-32k:latest`
- `Qwen 8B (Long 64K) Local [longctx]` -> `qwen3-8b-64k:latest`
- `Qwen 14B (Better Coding) Local [coding]` -> `qwen3-14b-32k:latest`
- `Qwen3 14B 32k Local [coding]` -> `qwen3-14b-32k:latest`
- `DeepSeek 8B (Debugging) Local [debug]` -> `deepseek-r1-8b-32k:latest`
- `DeepSeek 8B (Long 64K) Local [longctx]` -> `deepseek-r1-8b-64k:latest`
- `DeepSeek 14B (Architecture) Local [architecture]` -> `deepseek-r1-14b-32k:latest`
- `DeepSeek R1 14B 32k Local [reasoning]` -> `deepseek-r1-14b-32k:latest`
- `Devstral 24B Local Optional [agent]` -> `devstral:24b`
- `Codestral 22B Local Optional [frontend]` -> `codestral:22b`
- `Qwen2.5 Coder 32B Local Optional [backend]` -> `qwen2.5-coder:32b`
- `Qwen3 Coder 30B Local [large-gen]` -> `qwen3-coder:30b`
- `DeepSeek Coder V2 Local Optional [refactor]` -> `deepseek-coder-v2:latest`

Installed but intentionally not configured unless extra fallback choices are needed:

- `deepseek-r1:14b`
- `deepseek-r1:8b`
- `qwen3:14b`
- `qwen3:8b`

Recommended usage:

- `[backend]` or `[large-gen]` for C# CQRS / EF Core / multi-file implementation.
- `[architecture]` or `[reasoning]` for ADRs, module boundaries, and trade-off analysis.
- `[agent]` for multi-step execution and Playwright-oriented work.
- `[frontend]` for React, Vite, UI wiring, and selector fixes.
- `[semantic]` for embeddings and indexing only, not chat.

Verified VS Code extensions:

- Continue -> `continue.continue`
- Cline -> `saoudrizwan.claude-dev`
- Playwright Test for VS Code -> `ms-playwright.playwright`
- GitLens -> `eamodio.gitlens`
- Docker -> `ms-azuretools.vscode-docker`
- PowerShell -> `ms-vscode.powershell`

Refresh steps after changing `config.yaml`:

1. Run `ollama list` to confirm the model tag exists locally.
2. Reload the VS Code window.
3. Open the Continue model picker and verify the bracketed purpose label appears.
4. If the picker is stale, disable and re-enable the Continue extension.
