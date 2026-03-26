---
agent: agent
description: Completion quality gate — after finishing any feature, task, script, or workflow, verify it has been properly documented, guardrailed, tested, and automated
---

Run this after completing any feature, task, script, fix, or workflow change. Work through each category below systematically. For each item, check the actual codebase — do not assume.

## 1. Documentation

- [ ] Is the feature/change described in the relevant README, guide, or copilot-instructions.md?
- [ ] If a new script was added: does `scripts/README.md` (or the owning folder README) document it with usage, parameters, and purpose?
- [ ] If a new workflow was added: does `.github/workflows/README.md` reference it?
- [ ] If a new prompt was added: does `.github/prompts/README.md` document it, and is it listed in `copilot-instructions.md` §9?
- [ ] If a new architectural decision was made: is there an ADR in `docs/architecture/decisions/`?

## 2. Guardrails

- [ ] If a new domain rule or constraint exists: is it enforced in the Domain layer (not just a comment)?
- [ ] If inputs cross a system boundary (API, UI, script parameter): is there validation?
- [ ] If a secret or credential is involved: is it in Key Vault / `.env.local` / user-secrets — never hardcoded?
- [ ] If the change could affect another tenant: is tenant isolation preserved?
- [ ] If a script has destructive behaviour: does it require confirmation or a `-Force` / `-WhatIf` flag?

## 3. Unit Tests

- [ ] Does the new/changed domain entity have unit tests in `XYDataLabs.OrderProcessingSystem.Domain.Tests`?
- [ ] Does the new/changed CQRS handler have unit tests in `XYDataLabs.OrderProcessingSystem.Application.Tests`?
- [ ] Do existing tests still pass? Run: `dotnet test tests/XYDataLabs.OrderProcessingSystem.Domain.Tests` and `tests/XYDataLabs.OrderProcessingSystem.Application.Tests`

## 4. Integration / Architecture Tests

- [ ] Does the new/changed controller have tests in `XYDataLabs.OrderProcessingSystem.API.Tests`?
- [ ] If an EF Core migration was added: has it been verified against the local DB?
- [ ] If layer boundaries were changed: does `XYDataLabs.OrderProcessingSystem.Architecture.Tests` still pass?
- [ ] Run: `dotnet test tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests`

## 5. Automation / CI-CD

- [ ] If a new script automates a task: can it run unattended (no interactive prompts in CI mode)?
- [ ] If a new workflow was added: is there a corresponding path trigger in the right workflow file?
- [ ] If something was previously manual: is it now captured in a script or workflow so it doesn't need to be repeated manually?
- [ ] If a VS Code task or Copilot prompt would help discoverability: has one been created?

## 6. Copilot Context

- [ ] Is `copilot-instructions.md` still accurate? (Run `/XYDataLabs-context-audit` if unsure)
- [ ] Are relevant `/memories/repo/` files up to date with any new resource names or conventions?

---

For each unchecked item, either:
- **Fix it now** (preferred) — implement the missing piece, then mark it done
- **Record it** — add a TODO comment or open a tracking item with a clear owner and reason for deferral

Report a summary of what passed, what was fixed, and what (if anything) was deferred with justification.
