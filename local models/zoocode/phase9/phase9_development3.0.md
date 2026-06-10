# Phase 9 Development 3.0 - Orders Adapter Slice

Zoo role: Implementer.

Strict mode: implement only this slice. Do not ask follow-up questions. Do not invent architecture. Finish with `DONE`.

Input:

- Accepted output from `phase9_architect2.0.md`
- Existing order commands, queries, controllers, DTOs, and tests
- `.github/instructions/clean-architecture.instructions.md`

Task:

Implement the first Orders module adapter slice by wiring `IOrdersModuleApi` to existing order CQRS behavior. Preserve existing public API behavior.

Allowed changes:

- Orders PublicApi DTO mapping.
- Adapter implementation that calls existing application services/dispatcher.
- Focused tests for adapter behavior.
- DI registration for the adapter.

Forbidden changes:

- Do not move order entities or DbContext in this slice.
- Do not create a separate OrderService host.
- Do not change controller routes unless explicitly accepted.
- Do not introduce MediatR.

Validation command:

```powershell
dotnet test tests/XYDataLabs.OrderProcessingSystem.Application.Tests/XYDataLabs.OrderProcessingSystem.Application.Tests.csproj
```
