# Phase 9 Zoo Code Execution Pack

Purpose: run Phase 9 through Zoo Code as a gated architect-to-developer workflow. Architecture files are read-only decision prompts. Development files are executable implementation commands for one accepted slice at a time.

Canonical references remain:

- `.github/prompts/phase-handoffs/phase-09-microservices-architecture.prompt.md`
- `.github/prompts/phase-handoffs/phase-09-microservices-implementation.prompt.md`
- `.github/prompts/phase-handoffs/local-model-phase-handoff-guide.md`
- `docs/Zoo-config.md`
- `repomix-output.xml`

Run order:

0. `00-phase9-zoo-code-runner.md` - open this first to route each Zoo Code step.
1. `phase9_architect1.0.md`
2. `phase9_architect1.1.md`
3. `phase9_architect2.0.md`
4. `phase9_development1.0.md`
5. `phase9_development1.1.md`
6. `phase9_development2.0.md`
7. `phase9_development2.1.md`
8. `phase9_development3.0.md`
9. `phase9_development4.0.md`
10. `phase9_development5.0.md`
11. `phase9_development6.0.md`
12. `phase9_development9.0.md`
13. `phase9_architect9.0.md`
14. `phase9_architect99.0.md`
15. `phase9_development99.0.md`

Gate rule: do not run any development file until the preceding architect output has been reviewed and accepted by Copilot or the repository owner.

## Operator Approval Boundary

Local model outputs from Ollama or Zoo Code are advisory until accepted by the repository owner.

Default Copilot action after an Ollama/Zoo Code architect or developer output is review and routing only:

- classify the output as accepted, accepted with corrections, needs revision, or rejected;
- list required corrections and acceptance criteria;
- produce the next Ollama command or Zoo Code prompt;
- identify files to attach and dropdown selections to use;
- recommend the narrow validation command.

Copilot must not implement code, edit source files, or run developer validation from local-model output unless the operator explicitly asks for implementation, for example: `apply it`, `implement it`, `make the changes`, `go ahead and edit`, or `run the developer slice yourself`.

## Local Model Process Notes

Use Zoo Code as the normal execution cockpit, especially for developer steps. If an architect step in Zoo Code fails with repeated `Model Response Incomplete` messages or prints tool-call JSON such as `read_file` instead of producing Markdown, run the architect step directly through Ollama and save the output under `local models/prompt-runs/`.

The direct Ollama architect pass works better for `architect1.0` because it:

- disables tool calls explicitly;
- removes broad `repomix-output.xml` noise unless it is deliberately needed;
- pins the topic to Phase 9 module isolation, YARP, ADR-021, Orders, Payments, Tenants, and `.PublicApi` contracts;
- writes the model output to a reviewable Markdown file.

Recommended `architect1.0` command:

```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem

$prompt = @"
Do not call tools. Do not summarize unrelated repo documents.
Respond in plain Markdown only.

Task: Produce Phase 9 architect1.0 output for XYDataLabs.OrderProcessingSystem.

This output MUST be about:
- Phase 9 module isolation
- YARP gateway strategy
- ADR-021: YARP Module Isolation Strategy for Microservices Architecture
- Orders, Payments, and Tenants module boundaries
- .PublicApi contracts
- First developer-ready slice

This output MUST NOT be about:
- blueprint snapshot strategy
- NuGet template packaging
- GitHub template repo
- Aspire/PostgreSQL migration unless directly relevant to Phase 9

Repository facts:
- .NET 8 Clean Architecture order-processing system.
- Existing projects include API, Application, Domain, Infrastructure, SharedKernel, Gateway, payment adapters, and tests.
- Gateway project exists and uses YARP.
- CQRS is hand-rolled with ICommand/IQuery/IDispatcher. Do not introduce MediatR.
- Tenants own tenant registry and Tenant.PaymentProviderCode routing authority.
- Payments own payment attempts, provider references, webhook inbox/idempotency, and payment status transitions.
- Orders must own order amount/currency before payment module extraction.
- Phase 9 starts with module isolation first, service extraction second.
- Domain and Application must not reference Infrastructure.

Required output:
1. Architecture assessment
2. ADR-021 draft
3. Qwen developer handoff
4. Risks requiring stakeholder validation
5. Repo-owner acceptance checklist
6. First developer-ready slice with scope, likely files, validation command, and stop condition

===== CONTROLLING PROMPT =====
$(Get-Content ".github\prompts\phase-handoffs\phase-09-microservices-architecture.prompt.md" -Raw)
"@

$prompt |
	& ollama run qwen2.5-coder:7b `
	> "local models\prompt-runs\phase9-architect1.0-output.md" `
	2> "local models\prompt-runs\phase9-architect1.0-ollama-error.log"

$LASTEXITCODE

code "local models\prompt-runs\phase9-architect1.0-output.md"
```

Acceptance rule for local model architect output: if the output is mostly correct but contains unsafe details, do not discard it. Record reviewer corrections, then use Zoo Code developer mode with the corrected slice and constraints.

For the current Phase 9 flow, the first acceptable developer slice is boundary enforcement, not business-logic movement: add architecture tests for module `.PublicApi`, Domain, Application, and Infrastructure reference rules, then run the architecture test project.
