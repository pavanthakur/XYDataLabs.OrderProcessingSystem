# Phase 9 Development 2.0 - Architecture Boundary Tests

Zoo role: Implementer.

Strict mode: implement only this slice. Do not ask follow-up questions. Do not invent architecture. Finish with `DONE`.

Input:

- Accepted output from `phase9_architect2.0.md`
- Existing architecture test project under `tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests`
- `.github/instructions/clean-architecture.instructions.md`

Task:

Add architecture tests that enforce Phase 9 module boundaries.

Required test coverage:

- `.PublicApi` projects do not reference Infrastructure.
- Domain projects do not reference Application or Infrastructure.
- Application projects do not reference Infrastructure.
- Cross-module references go through `.PublicApi` projects only.
- API/controllers do not bypass module contracts in new code.

Allowed changes:

- Architecture test files.
- Test project references/packages only if required by the existing architecture-test style.

Forbidden changes:

- No production behavior changes.
- No broad refactors.

Validation command:

```powershell
dotnet test tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests.csproj
```
