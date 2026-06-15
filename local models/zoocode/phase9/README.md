# Phase 9 Zoo Code Execution Pack

Purpose: run Phase 9 through a gated architect → developer → reviewer → automation flow with one-line commands and minimal human loop.

Canonical references remain:

- `.github/prompts/phase-handoffs/phase-09-microservices-architecture.prompt.md`
- `.github/prompts/phase-handoffs/phase-09-microservices-implementation.prompt.md`
- `.github/prompts/phase-handoffs/local-model-phase-handoff-guide.md`
- `docs/Zoo-config.md`
- `repomix-output.xml`

## Quick Start

1. Generate a fresh context snapshot when the repo changed significantly:

```powershell
npx repomix
```

2. Run the step you want:

```powershell
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9.ps1" -Step architect
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9.ps1" -Step developer
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9.ps1" -Step review
powershell -ExecutionPolicy Bypass -File "local models\zoocode\phase9\run-phase9.ps1" -Step automation
```

## Phase 9 Rules

- Default model ceiling is 8B or smaller.
- Default context ceiling is 4096 tokens.
- Use Repomix for architecture and review context only when needed.
- Keep developer slices narrow and artifact-driven.
- Do not run a later step until the previous step’s output is accepted.

## Step Handoffs

- `architect` → `phase9_architect1.0.md`
- `developer` → `phase9_development1.0.md`
- `review` → `phase9_review1.0.md`
- `automation` → `phase9_automation1.0.md`

## One-Line Discipline

- Each step should be invokable as a single line.
- Each step should produce exactly one next handoff artifact.
- Each step should minimize the number of manual decisions required from the operator.
