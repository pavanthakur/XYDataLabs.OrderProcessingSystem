# Phase Handoff Prompts

This folder contains phase-specific AI handoff prompts for external or role-specialized models.

Use these prompts when a phase needs a two-step handoff:

1. An architect model produces the architecture decision, module strategy, risk register, and implementation blueprint.
2. A developer model uses that blueprint to implement one narrow, validated slice at a time.

These files are repo-shared AI assets, not canonical human-facing documentation. Canonical decisions still belong in `docs/architecture/decisions/`, and implementation truth still belongs in the code, tests, and owned docs.

## Model Utilization

- Prefer the phase's named 14B architect/developer models when they are stable and the prompt fits comfortably.
- Use 64k variants, such as Deepseek 64k or Qwen 64k, when long repository context must remain in one pass or a 14B run stalls.
- Treat 64k architect output as a draft requiring the same ADR-quality review, constraint checklist, and stakeholder-risk validation.
- Keep implementation prompts slice-sized even when using 64k context; long context is for better grounding, not broader change scope.

## Naming Convention

Use this pattern for future phases:

```text
phase-NN-topic-architecture.prompt.md
phase-NN-topic-implementation.prompt.md
```

Examples:

```text
phase-09-microservices-architecture.prompt.md
phase-09-microservices-implementation.prompt.md
phase-10-servicebus-architecture.prompt.md
phase-10-servicebus-implementation.prompt.md
```

## Current Prompts

| Phase | Architect Prompt | Developer Prompt | Status |
|---|---|---|---|
| Phase 9 - YARP Microservices Architecture | `phase-09-microservices-architecture.prompt.md` | `phase-09-microservices-implementation.prompt.md` | Active |

## Maintenance Rules

- Keep one architect prompt and one developer prompt per phase unless the phase genuinely needs more roles.
- Update `.github/prompts/README.md` and `.github/copilot-instructions.md` when adding or renaming a phase handoff prompt.
- Keep architecture decisions in ADR files, not only in these prompts.
- Keep prompts aligned with the current repository stack before handing them to another model.
- Run `pwsh scripts/validate-ai-customization.ps1` after changes.
