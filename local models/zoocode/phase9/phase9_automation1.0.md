# Phase 9 Automation 1.0 - Validation Gate

Zoo role: QA.

Strict mode: validation only. Do not write production code. Do not emit patches. Finish with `DONE`.

Input:

- Accepted output from `phase9_review1.0.md`
- Current implementation diff
- Existing test projects

Task:

Run the narrow Phase 9 validation gate and summarize results.

Required validation set:

```powershell
dotnet test tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests.csproj
dotnet test tests/XYDataLabs.OrderProcessingSystem.Application.Tests/XYDataLabs.OrderProcessingSystem.Application.Tests.csproj
dotnet test tests/XYDataLabs.OrderProcessingSystem.API.Tests/XYDataLabs.OrderProcessingSystem.API.Tests.csproj
dotnet test tests/XYDataLabs.OrderProcessingSystem.Gateway.Tests/XYDataLabs.OrderProcessingSystem.Gateway.Tests.csproj
```

If the slice touched payments, tenants, or webhooks:

```powershell
dotnet test tests/XYDataLabs.OrderProcessingSystem.Integration.Tests/XYDataLabs.OrderProcessingSystem.Integration.Tests.csproj --filter "Payment|Tenant|Webhook"
```

Required output:

1. Validation commands run.
2. Pass/fail summary.
3. Remaining failures with ownership.
4. Whether the slice is ready for the next handoff.

Stop after the QA report.
