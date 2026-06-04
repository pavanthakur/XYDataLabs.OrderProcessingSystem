# Implementation Notes - Architecture Phase 8.5 (Days 57-59)

Purpose: Detailed execution evidence for the Phase 8.5 secondary payment provider closeout.
These notes supplement the checklist-level summaries in `../curriculum/1_MASTER_CURRICULUM.md`.

Created: 31/05/2026 | Covers: Days 58-59 (Architecture Phase 8.5)

---

## Scope

This note covers the Phase 8.5 multi-provider payment architecture closeout:

- provider-neutral `IPaymentProviderGateway` boundary with keyed DI for both OpenPay and Razorpay
- per-tenant runtime provider resolution via Application `StartupHelper` factory
- `PaymentProviderCustomerActionException` — cross-cutting typed exception for terminal declines
- provider-aware retry classification in `ProcessPaymentCommandHandler`
- `IsProduction` mode guard and key-prefix cross-validation on both adapters
- full unit test coverage for the Razorpay adapter boundary

Day 57 (Queue-Triggered Azure Functions) was treated as learning preparation only and did not produce production code changes.

---

## Day 58: Phase 8.5a — Provider-Neutral Routing And Keyed DI

**1. `XYDataLabs.RazorpayAdapter` project**

Full adapter project implemented with:
- `RazorpayAdapterService` wrapping `RazorpayClient` for order creation and payment retrieval
- `IRazorpayAdapterService` contract with `CreateOrderAsync` and `GetPaymentAsync`
- `RazorpayCreateOrderRequest` / `RazorpayOrderResult` / `RazorpayPaymentResult` record types
- `RazorpayConfig` with `MerchantId`, `PrivateKey`, `IsProduction` (default `false`)
- `RazorpayConfigValidator` implementing `IValidateOptions<RazorpayConfig>` with `ValidateOnStart()`
- Polly named resilience pipeline `"razorpay"` via `AddResiliencePipeline`

**2. Keyed DI registration**

Both gateways registered with keyed DI so Application resolves by `PaymentProviderTypes` string:

```csharp
services.AddKeyedScoped<IPaymentProviderGateway, OpenPayPaymentGateway>(PaymentProviderTypes.OpenPay);
services.AddKeyedScoped<IPaymentProviderGateway, RazorpayPaymentGateway>(PaymentProviderTypes.Razorpay);
```

The Application `StartupHelper` factory resolves the active gateway from `PaymentProvider.ProviderType` at runtime — switching a tenant's processor is a data change in `PaymentProvider`, not a code change or redeploy.

**3. `RazorpayPaymentGateway`**

Implements `IPaymentProviderGateway`. Maps:
- `CreateChargeAsync` → `IRazorpayAdapterService.CreateOrderAsync`
- `CreateCustomerAsync` → stub (Razorpay does not have a pre-create customer API; returns deterministic stub ID)
- `CreateCardTokenAsync` → stub (`razorpay-token-pending` placeholder)
- Classifies `Razorpay.Api.Errors.BadRequestError` as customer-action via `PaymentProviderCustomerActionException`

---

## Day 59: Phase 8.5b — Retry Classification, Mode Guard, And Test Coverage

**1. Provider-aware retry classification**

`ProcessPaymentCommandHandler` now differentiates:

```csharp
catch (PaymentProviderCustomerActionException)
{
    // Terminal — no retry, no reconciliation
    attempt.Status = PaymentAttemptStatus.Failed;
}
catch (Exception)
{
    // Transient or ambiguous — reconciliation worker recovers
    attempt.Status = PaymentAttemptStatus.UnknownNeedsReconciliation;
}
```

- `OpenPayPaymentGateway`: classifies `OpenpayException` with `ErrorCode` in 3000–3999 range (card-level terminal failures) as customer-action
- `RazorpayPaymentGateway`: classifies `BadRequestError` as customer-action

**2. `IsProduction` mode guard**

`IsProduction` added to both configs with default `false` in all environments (`dev`, `stg`, `prod`, `local`):

```json
"Razorpay": {
  "MerchantId": "rzp_test_...",
  "PrivateKey": "...",
  "IsProduction": false
}
```

Startup logging on both adapters:
```
Razorpay adapter initialised in TEST mode (rzp_test_AbCdEfGhIj)
OpenPay adapter initialised in TEST mode
```

**3. `RazorpayConfigValidator` key-prefix cross-check**

Prevents misconfigured live/test keys at startup — fail-fast before any payment call:

| Key prefix | `IsProduction` | Result |
|---|---|---|
| `rzp_test_*` | `false` | ✅ Valid |
| `rzp_live_*` | `true` | ✅ Valid |
| `rzp_live_*` | `false` | ❌ Fails — live key + test mode would silently charge real customers |
| `rzp_test_*` | `true` | ❌ Fails — test key in production mode is misconfiguration |
| non-prefixed | any | ✅ Pass — cross-check applies only to recognised `rzp_` prefix |

**4. Architecture boundary tests**

```csharp
Application_Should_Not_Depend_On_OpenPayAdapter()   // ✅
Application_Should_Not_Depend_On_RazorpayAdapter()  // ✅
```

**5. Unit test counts (final)**

| Test project | Tests |
|---|---|
| `API.Tests` | 80 ✅ |
| `Application.Tests` | passed |
| `Architecture.Tests` | passed |

Key test files added for Razorpay:
- `RazorpayOptionsValidationTests.cs` — required fields and placeholder values
- `RazorpayPaymentGatewayTests.cs` — gateway charge mapping, customer-action classification, stub operations
- `RazorpayConfigValidatorTests.cs` — key-prefix vs `IsProduction` cross-validation (9 tests, this session)

---

## Verification Commands

```powershell
dotnet build XYDataLabs.OrderProcessingSystem.sln --no-incremental
dotnet test tests\XYDataLabs.OrderProcessingSystem.API.Tests\XYDataLabs.OrderProcessingSystem.API.Tests.csproj
```

Observed result:
- Build: succeeded
- API.Tests: 80 passed, 0 failed

---

## What This Enables For Phase 8.7

Phase 8.7 (Provider Webhook Receiver) can now:
- Resolve the correct tenant gateway by `ProviderType` from the existing keyed DI registration
- Trust that all customer-action outcomes are already classified as terminal `Failed` — no reconciliation worker interference
- Use the `IsProduction` flag per tenant to route webhooks to the correct provider sandbox vs live endpoint
- Stamp `tenantId` in outgoing provider requests (foundation for webhook metadata restoration)
