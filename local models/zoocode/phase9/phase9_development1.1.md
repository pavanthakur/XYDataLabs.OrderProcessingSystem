# Phase 9 Development 1.1 - PublicApi Contracts And Project Shells

Zoo role: Implementer.

Strict mode: implement only this slice. Do not ask follow-up questions. Do not invent architecture. Finish with `DONE`.

Input:

- Accepted output from `phase9_architect2.0.md`
- `.github/prompts/phase-handoffs/phase-09-microservices-implementation.prompt.md`
- `.github/instructions/clean-architecture.instructions.md`

Task:

Create initial module `.PublicApi` projects and stable cross-module contracts for Orders, Payments, and Tenants. Create project shells only if the accepted blueprint explicitly says to do so.

Allowed changes:

- New `.PublicApi` project files.
- Interface and DTO files in `.PublicApi` projects.
- Solution references for the new projects.
- Directory placeholders only where needed.

Forbidden changes:

- Do not move existing domain/application/infrastructure behavior.
- Do not expose EF entities, DbContext types, domain entities, provider SDKs, or controllers in PublicApi contracts.
- Do not change runtime DI or API behavior in this slice.
- Do not introduce MediatR.

Expected contracts:

- `IOrdersModuleApi`
- `IPaymentsModuleApi`
- `ITenantsModuleApi`

Validation command:

```powershell
dotnet build XYDataLabs.OrderProcessingSystem.sln
```
