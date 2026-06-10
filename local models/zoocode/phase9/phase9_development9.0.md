# Phase 9 Development 9.0 - Integration And Regression Gate

Zoo role: Implementer.

Strict mode: implement only this validation and repair slice. Do not ask follow-up questions. Do not invent architecture. Finish with `DONE`.

Input:

- Current implementation after development slices 1.0 through 6.0
- Accepted output from `phase9_architect9.0.md`, if already produced
- Existing test projects

Task:

Run and repair the focused Phase 9 regression gate. Repair only defects caused by Phase 9 changes.

Required validation set:

```powershell
dotnet test tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests.csproj
dotnet test tests/XYDataLabs.OrderProcessingSystem.Application.Tests/XYDataLabs.OrderProcessingSystem.Application.Tests.csproj
dotnet test tests/XYDataLabs.OrderProcessingSystem.API.Tests/XYDataLabs.OrderProcessingSystem.API.Tests.csproj
dotnet test tests/XYDataLabs.OrderProcessingSystem.Gateway.Tests/XYDataLabs.OrderProcessingSystem.Gateway.Tests.csproj
```

Payment/tenant regression, when Payments or Tenants were touched:

```powershell
dotnet test tests/XYDataLabs.OrderProcessingSystem.Integration.Tests/XYDataLabs.OrderProcessingSystem.Integration.Tests.csproj --filter "Payment|Tenant|Webhook"
```

Allowed changes:

- Focused test repair.
- Focused production repair only when directly caused by Phase 9 slices.

Forbidden changes:

- No broad refactors.
- No architecture changes.
- No unrelated test fixes.

Required output:

- Validation commands run.
- Pass/fail summary.
- Remaining failures with ownership: Phase 9 defect, pre-existing, or environment.
