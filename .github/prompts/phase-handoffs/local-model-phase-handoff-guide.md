# Local Model Phase Handoff Guide

Use this guide when running a phase through local Ollama models in Continue or Cline.

The standard practice is a gated handoff:

1. Architect model produces the decision, risks, constraints, and first implementation slice.
2. Copilot or the repository owner reviews the architecture output against repo constraints.
3. Developer model implements one accepted slice only.
4. Agent model may execute a narrow task only after the slice is precise.
5. Validation runs before the next slice starts.

Do not let a developer or agent model invent architecture. Do not let an architect model write production code.

Do not create a parallel `docs/ai/` playbook tree for this repository. AI operating rules live in `.github/prompts/`, `.github/instructions/`, `.github/agents/`, `.github/skills/`, and `docs/AI-OPERATING-MODEL.md`. Canonical product decisions still live in `docs/architecture/decisions/`.

## Model Routing

| Work type | Continue model | Use for | Avoid |
|---|---|---|---|
| Architecture / ADR | `DeepSeek 14B (Architecture) Local [architecture]` | ADRs, module boundaries, YARP strategy, risk register | Production code edits |
| Reasoning fallback | `DeepSeek R1 14B 32k Local [reasoning]` | Hard trade-offs, debugging a design, reviewing a plan | Broad implementation |
| Implementation planning | `Qwen3 Coder 30B Local [large-gen]` | Turning an accepted ADR into narrow slices | Architecture decisions |
| Backend implementation | `Qwen2.5 Coder 32B Local Optional [backend]` | C# CQRS, EF Core, tests, project skeletons | Broad repo rewrites |
| Agent execution | `Devstral 24B Local Optional [agent]` | Executing a very specific slice, Playwright-oriented tasks | Unreviewed architecture or large ambiguous tasks |
| Frontend work | `Codestral 22B Local Optional [frontend]` | React, Vite, UI wiring, selector fixes | Backend architecture |
| Embeddings | `Nomic Embed Local [semantic]` | Indexing and retrieval | Chat or code generation |

## Phase Workflow

## Phase Automation Contract

Every major phase should have the same repeatable AI-assisted SDLC shape:

| Stage | Owner | Required input | Required output | Gate before next stage |
|---|---|---|---|---|
| Phase start | Copilot / repo owner | `/memories/repo/active-work.md`, current roadmap, relevant ADRs | active constraints and candidate files | constraints are explicit |
| Architecture | DeepSeek architecture model | phase architecture prompt and repository constraints | ADR-ready decision, risk register, first implementation slice | Copilot/repo-owner review accepts or rejects |
| Implementation planning | Qwen large coding model | accepted architecture handoff | narrow file-level implementation plan | scope is one slice only |
| Coding | Qwen backend model or Copilot | accepted implementation slice | code/test/docs changes | focused validation passes |
| Agent execution | Devstral / Cline | precise accepted task | mechanical edits or test repair | no architecture changes introduced |
| Review | Copilot / reviewer model | diff, validation output, ADR | findings, missing tests, next slice | issues resolved or deferred with reason |
| Closeout | Copilot / repo owner | final diff and validation | active-work update, docs/ADR sync, completion summary | repo context remains current |

For each new phase:

1. Add or update one architecture prompt and one implementation prompt under `.github/prompts/phase-handoffs/`.
2. Add the phase to `.github/prompts/phase-handoffs/README.md` and `.github/prompts/README.md`.
3. Reuse this guide for model routing and gates.
4. Keep phase decisions in ADRs and implementation truth in code/tests.
5. Run `pwsh scripts/validate-ai-customization.ps1` after prompt changes.

Automation should increase repeatability, not autonomy without review. The review gate is mandatory between architecture and implementation.

### Step 1 - Start With Repository Context

Before handing work to a local model:

- Read `/memories/repo/active-work.md` through the memory tool.
- Identify the active phase and key constraints.
- Prefer the phase prompt under `.github/prompts/phase-handoffs/` when one exists.
- Keep canonical decisions in `docs/architecture/decisions/`, not only in model output.

### Step 2 - Architecture Handoff

Use the phase architecture prompt with the architecture model.

For Phase 9, use:

```text
.github/prompts/phase-handoffs/phase-09-microservices-architecture.prompt.md
```

The architecture model must return:

- Verdict on the proposed plan.
- ADR-ready decision summary.
- Module boundary table.
- YARP strategy for now, next, and later.
- Data ownership and schema migration strategy.
- Risks requiring stakeholder validation.
- First implementation slice for the developer model.

### Step 3 - Review Gate

Before implementation, review the architecture output for these gates:

- Clean Architecture boundaries remain intact.
- Current CQRS stays hand-rolled; no MediatR package is introduced.
- `Tenant.PaymentProviderCode` remains the only payment-provider routing authority.
- `TenantRegistryDbContext` remains the tenant resolution source.
- ADR-020 webhook inbox/idempotency behavior remains intact.
- YARP routes host boundaries, not class-library modules.
- Module isolation comes before service extraction.
- No RabbitMQ, Redis, MassTransit, or broad infrastructure changes are introduced without ADR approval.

If any gate fails, send the plan back to the architecture model for correction.

### Step 4 - Development Handoff

Use the implementation prompt only after the architecture handoff is accepted.

For Phase 9, use:

```text
.github/prompts/phase-handoffs/phase-09-microservices-implementation.prompt.md
```

The developer model must implement only the first accepted slice. It must state:

- Files it will touch.
- Local hypothesis.
- Narrow validation command.
- Expected behavior after the slice.

### Step 5 - Agent Execution

Use an agent model only for a precise task, for example:

```text
Implement the architecture test named in the accepted slice and run the focused test project. Do not create new projects or change runtime behavior.
```

Do not ask the agent model to design the architecture.

### Step 6 - Validation And Closeout

After each slice:

- Run the narrowest behavior-specific validation first.
- Run broader tests only after the slice is stable.
- Run `pwsh scripts/validate-ai-customization.ps1` when shared AI assets changed.
- Update ADRs or canonical docs when decisions changed.
- Keep `/memories/repo/active-work.md` current at session close.

## Ready Continue Lines

Use these one-line starters in Continue.

Architecture review line:

```text
Use .github/prompts/phase-handoffs/phase-09-microservices-architecture.prompt.md and review the Phase 9 plan below. Produce an ADR-021-ready correction and the first Qwen implementation slice only; do not write production code.
```

Generic architecture line for future phases:

```text
Use .github/prompts/phase-handoffs/local-model-phase-handoff-guide.md and the phase architecture prompt below. Produce an ADR-ready architecture handoff, risk register, validation strategy, and first implementation slice only. Do not write production code.
```

Implementation line:

```text
Use .github/prompts/phase-handoffs/phase-09-microservices-implementation.prompt.md and the accepted architecture handoff below. Implement only the first safe slice, state files, hypothesis, and validation command before editing.
```

Generic implementation line for future phases:

```text
Use .github/prompts/phase-handoffs/local-model-phase-handoff-guide.md and the phase implementation prompt below. Implement only the accepted first slice. Before editing, state files, local hypothesis, and narrow validation command.
```

Agent execution line:

```text
Execute only the accepted slice below. Do not change architecture, add infrastructure packages, alter YARP routes, or widen scope. Run the focused validation and report changed files.
```

Review correction line:

```text
Review the output below against the repo gates in .github/prompts/phase-handoffs/local-model-phase-handoff-guide.md. Return only corrections, blocked assumptions, and the smallest safe next action.
```

## Enterprise Guardrails

- Architecture output is advisory until reviewed and captured in an ADR.
- Implementation output is not accepted until focused validation passes.
- Local model convenience must not override repository constraints.
- Prefer fewer, better-scoped model handoffs over one large autonomous run.
- Keep every phase repeatable: architecture prompt, accepted handoff, implementation slice, validation result, closeout note.
- Do not add technology defaults such as MediatR, RabbitMQ, Redis, or Docker-first service extraction unless they are already part of the phase architecture or an accepted ADR.
- Prefer Azure-native, repository-established patterns over generic microservice templates.