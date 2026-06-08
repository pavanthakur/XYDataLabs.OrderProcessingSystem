Continue config: local model picker

This note documents the verified local Continue setup for this workstation. The active config file is user-scoped:

```text
C:\Users\Pavan\.continue\config.yaml
```

Shared phase handoff guideline:

```text
.github\prompts\phase-handoffs\local-model-phase-handoff-guide.md
```

Verified Continue picker entries use this display pattern:

```text
Family ModelSize Context [purpose]
```

- `Embed Nomic 274MB [semantic]` -> `nomic-embed-text:latest`
- `Qwen3 8B 32K [fast]` -> `qwen3-8b-32k:latest`
- `Qwen3 8B 64K [longctx]` -> `qwen3-8b-64k:latest`
- `Qwen3 14B 32K [coding]` -> `qwen3-14b-32k:latest`
- `Qwen3 14B 32K API [coding]` -> `qwen3-14b-32k:latest`
- `DeepSeek R1 8B 32K [debug]` -> `deepseek-r1-8b-32k:latest`
- `DeepSeek R1 8B 64K [longctx]` -> `deepseek-r1-8b-64k:latest`
- `DeepSeek R1 14B 32K [architecture]` -> `deepseek-r1-14b-32k:latest`
- `DeepSeek R1 14B 32K API [reasoning]` -> `deepseek-r1-14b-32k:latest`
- `Devstral 24B 32K [agent]` -> `devstral:24b`
- `Codestral 22B 32K [frontend]` -> `codestral:22b`
- `Qwen2.5 Coder 32B 32K [backend]` -> `qwen2.5-coder:32b`
- `Qwen3 Coder 30B 32K [large-gen]` -> `qwen3-coder:30b`
- `DeepSeek Coder V2 32K [refactor]` -> `deepseek-coder-v2:latest`

Installed but intentionally not configured unless extra fallback choices are needed:

- `deepseek-r1:14b`
- `deepseek-r1:8b`
- `qwen3:14b`
- `qwen3:8b`

Recommended usage:

- `[backend]` -> precise C# CQRS / EF Core / architecture-test implementation.
- `[large-gen]` -> larger implementation planning or generation, with strict scope.
- `[coding]` -> medium coding tasks when 30B/32B is too slow.
- `[fast]` -> quick answers and small snippets.
- `[longctx]` -> larger pasted context, not necessarily stronger reasoning.
- `[architecture]` or `[reasoning]` -> ADRs, module boundaries, and trade-off analysis.
- `[debug]` -> focused debugging and root-cause analysis.
- `[agent]` -> precise multi-step execution and Playwright-oriented work.
- `[frontend]` -> React, Vite, UI wiring, and selector fixes.
- `[semantic]` -> embeddings and indexing only, not chat.

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
