# Phase 9 Development 2.1 - Module Registration Stubs

Zoo role: Implementer.

Strict mode: implement only this slice. Do not ask follow-up questions. Do not invent architecture. Finish with `DONE`.

Input:

- Accepted output from `phase9_architect2.0.md`
- Existing dependency-injection registration patterns in API/Application/Infrastructure
- `.github/instructions/clean-architecture.instructions.md`

Task:

Add low-risk module registration stubs for Orders, Payments, and Tenants without changing runtime behavior beyond registering empty/module-local services.

Expected registration names:

- `AddOrdersModule()`
- `AddPaymentsModule()`
- `AddTenantsModule()`

Allowed changes:

- Module registration extension files.
- Minimal service registrations required by PublicApi adapters if already created.
- API composition-root wiring only if it is no-op or explicitly accepted.

Forbidden changes:

- Do not move handlers/entities/DbContexts.
- Do not change payment provider routing.
- Do not change tenant resolution.
- Do not change YARP routes.

Validation command:

```powershell
dotnet build XYDataLabs.OrderProcessingSystem.sln
```
