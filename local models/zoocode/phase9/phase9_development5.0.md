# Phase 9 Development 5.0 - Payments Boundary And Webhook-Safe Slice

Zoo role: Implementer.

Strict mode: implement only this slice. Do not ask follow-up questions. Do not invent architecture. Finish with `DONE`.

Input:

- Accepted output from `phase9_architect2.0.md`
- ADR-020 webhook inbox/idempotency decision
- Existing payment commands, queries, webhook handlers, provider adapters, and tests
- `.github/instructions/multitenant-payment-schema.instructions.md`

Task:

Introduce the Payments module boundary around payment attempts, provider references, webhook inbox behavior, and payment status transitions without changing runtime semantics.

Hard constraints:

- Preserve ADR-020 webhook inbox/idempotency behavior.
- Preserve Razorpay `Use3DSecure=false` and OpenPay `Use3DSecure=true`.
- Preserve tenant-based provider routing through `Tenant.PaymentProviderCode`.
- Orders own order amount/currency in the target boundary; document any temporary bridge.

Allowed changes:

- `IPaymentsModuleApi` implementation/adapters.
- DTOs and mapping for stable payment public contracts.
- Focused tests for provider routing and webhook behavior.

Forbidden changes:

- Do not change webhook signature verification semantics.
- Do not change provider credential loading.
- Do not add new broker/cache infrastructure.

Validation command:

```powershell
dotnet test tests/XYDataLabs.OrderProcessingSystem.Integration.Tests/XYDataLabs.OrderProcessingSystem.Integration.Tests.csproj --filter Payment
```
