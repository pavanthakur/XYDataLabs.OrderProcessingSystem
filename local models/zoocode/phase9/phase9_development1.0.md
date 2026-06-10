# Phase 9 Development 1.0 - Create ADR-021

Zoo role: Implementer.

Strict mode: implement only this slice. Do not ask follow-up questions. Do not invent architecture. Do not modify production code. Finish with `DONE`.

Input:

- Accepted output from `phase9_architect1.1.md`
- `docs/architecture/decisions/ADR-000-template.md`, if present
- `.github/instructions/architecture.instructions.md`

Task:

Create `docs/architecture/decisions/ADR-021-yarp-module-isolation-strategy.md`.

Allowed changes:

- ADR-021 only, plus a minimal docs index/reference update only if the repository already requires ADR discovery updates.

Forbidden changes:

- No C# code.
- No project files.
- No package changes.
- No YARP config changes.

ADR must state:

- Phase 9 begins as module isolation, not immediate service extraction.
- YARP routes host boundaries, not class-library modules.
- In-process modules communicate through `.PublicApi` contracts.
- Independently hosted module APIs may be introduced only after boundaries and tests are stable.
- Orders own amount/currency.
- Payments own payment attempts, provider references, webhook inbox behavior, and payment status transitions.
- Tenants own tenant registry and provider routing authority.
- Shared database schemas are temporary migration bridges only.

Validation command:

```powershell
pwsh scripts/validate-adr-frontmatter.ps1
```
