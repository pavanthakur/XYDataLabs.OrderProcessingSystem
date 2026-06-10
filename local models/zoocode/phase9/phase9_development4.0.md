# Phase 9 Development 4.0 - Tenants Boundary Slice

Zoo role: Implementer.

Strict mode: implement only this slice. Do not ask follow-up questions. Do not invent architecture. Finish with `DONE`.

Input:

- Accepted output from `phase9_architect2.0.md`
- Existing tenant registry code
- `.github/instructions/multitenant-payment-schema.instructions.md`
- `.github/instructions/ef-migrations.instructions.md` if touching DbContext or migrations

Task:

Introduce the Tenants module boundary while preserving current tenant resolution and payment-provider routing behavior.

Hard constraints:

- `Tenant.PaymentProviderCode` remains the only payment-provider routing authority.
- `TenantRegistryDbContext` remains the tenant resolution source.
- Do not resolve tenants through the business DbContext.

Allowed changes:

- `ITenantsModuleApi` implementation/adapters.
- DTOs that expose only stable tenant/public routing data.
- Focused tenant tests.

Forbidden changes:

- No provider routing behavior changes.
- No tenant schema destructive changes.
- No PaymentProviders.IsActive routing resurrection.

Validation command:

```powershell
dotnet test tests/XYDataLabs.OrderProcessingSystem.Integration.Tests/XYDataLabs.OrderProcessingSystem.Integration.Tests.csproj --filter Tenant
```
