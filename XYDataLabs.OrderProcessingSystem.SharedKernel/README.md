# SharedKernel

Cross-cutting primitives shared by Domain, Application, and Infrastructure. No layer-specific dependencies.

## Namespaces

| Namespace | Contents |
|-----------|---------|
| `Results/` | `Result<T>`, `Error`, `ApiResponse` — unified success/failure return type used across all handlers and controllers |
| `Payments/` | `IPaymentProviderGateway`, `IPaymentProviderAdapter`, `ITenantPaymentProviderConfigurationResolver`, `PaymentProviderTypes` (string constants: `"OpenPay"`, `"Razorpay"`), `PaymentProviderCustomerActionException`, `PaymentGatewayRequestDefaults` |
| `Multitenancy/` | `ITenantProvider`, `ITenantResolver`, `TenantMiddleware`, `TenantContext`, `ScopedTenantContextAccessor`, `TenantTierConstants`, `HeaderTenantProvider` |
| `Configuration/` | `TenantConfigurationOptions`, `ObservabilityOptions`, `ApplicationInsightsOptions` — strongly typed settings; validated on startup |
| `Observability/` | `IPaymentTelemetryTracker`, `PaymentTelemetryEvent`, `BusinessMetrics`, `CorrelationMiddleware`, `ObservabilityExtensions` |

## Key conventions

- `PaymentProviderCustomerActionException` = terminal decline — handler maps to `PaymentAttemptStatus.Failed`, no retry.
- `TenantTierConstants` defines the tier values used in `Tenant.Tier`.
- `PaymentProviderTypes` constants are the keyed DI registration keys for `IPaymentProviderGateway`.
- `Result<T>` is the mandatory return type for all command/query handlers — never throw from business logic paths.
