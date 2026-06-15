# Local AI Performance Tuning

Target machine profile: Acer Predator Helios 300, i7-11800H, 32GB RAM, RTX 3050 Ti 4GB VRAM, Windows 11.

Use this guide when running Ollama through Zoo Code, Continue, or other VS Code AI extensions for Phase 9 and later work.

## Core Rule

Use smaller coding models daily. Escalate to heavier reasoning models only for bounded architecture decisions.

## Recommended Models

| Task | Default model | Context | Notes |
| --- | --- | --- | --- |
| Phase runner and normal architect routing | `qwen2.5-coder:7b` | 4096 | Default for Phase 9 on this laptop. |
| Developer implementation slices | `qwen2.5-coder:7b` | 4096 | Best daily balance for C#, CQRS, React, and refactoring. |
| Quick Ask/docs/small snippets | `qwen2.5-coder:3b` | 4096 | Use for short answers and lightweight tasks. |
| Architecture/review escalation | `deepseek-r1:8b` | 4096 | Use only when Qwen output is insufficient and a bounded reasoning pass is needed. |
| Embeddings/search | `nomic-embed-text` | N/A | Optional if a tool explicitly needs embeddings. |

## Avoid By Default

Do not run these as default settings:

```text
any model above 8B parameters
any context window above 4096 tokens for normal Zoo Code work
multiple AI assistants indexing the full repository at once
```

These settings create CPU and memory pressure on a 32GB laptop and can make Zoo Code appear stuck or incomplete.

## Zoo Code Settings

Architect mode:

```text
Provider: Ollama
Model: qwen2.5-coder:7b
Context: 4096
Mode: Architect / Ask / Chat
Auto-approve: Off
```

Developer mode:

```text
Provider: Ollama
Model: qwen2.5-coder:7b
Context: 4096
Mode: Code / Edit
Auto-approve: Off
```

Quick questions:

```text
Provider: Ollama
Model: qwen2.5-coder:3b
Context: 4096
Mode: Ask
```

DeepSeek escalation:

```text
Provider: Ollama
Model: deepseek-r1:8b
Context: 4096
Mode: Architect / Ask / Chat
Auto-approve: Off
```

## Phase 9 Usage

1. Start with `local models/zoocode/phase9/00-phase9-zoo-code-runner.md` using `qwen2.5-coder:7b`.
2. Run `phase9_architect1.0.md`, `phase9_architect1.1.md`, and `phase9_architect2.0.md` with Qwen first.
3. Escalate only the architecture review output to DeepSeek if Qwen misses important bounded-context, ADR, or module-isolation trade-offs.
4. Use Qwen for all developer prompts unless a single slice requires broader reasoning.
5. Keep `repomix-output.xml` mostly for architect prompts; avoid attaching it to developer prompts by default.

## Resource Hygiene

Before heavy architecture runs:

- Close or suspend browser tabs.
- Stop unused Docker containers and WSL workloads.
- Stop SQL Server if it is not needed.
- Avoid running Copilot Agent, Continue, Zoo Code, and another local agent all at once.
- Keep context small before changing models.

## Install Commands

```powershell
ollama pull qwen2.5-coder:7b
ollama pull qwen2.5-coder:3b
ollama pull nomic-embed-text
```

Keep DeepSeek installed only if you can tolerate slower architecture passes:

```powershell
ollama pull deepseek-r1:8b
```

## Expected Outcome

With Qwen 7B and 4096 context, Zoo Code should be more responsive, use less RAM, and avoid the high-context CPU-bound behavior seen with larger models.
