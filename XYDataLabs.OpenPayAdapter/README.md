# OpenPayAdapter

OpenPay payment provider integration. Implements `IPaymentProviderGateway` registered under the `"OpenPay"` DI key.

## Key types

| Type | Purpose |
|------|---------|
| `OpenPayPaymentGateway` | Implements `IPaymentProviderGateway` — entry point called by `ProcessPaymentCommandHandler` |
| `OpenPayAdapterService` / `IOpenPayAdapterService` | HTTP client wrapper for OpenPay REST API |
| `OpenPayException` | Provider-specific exception mapped to `PaymentProviderCustomerActionException` for terminal declines |
| `Configuration/` | `OpenPayOptions` — merchant ID, private key, base URL; loaded via `IOptions<OpenPayOptions>` |
| `ServiceCollectionExtensions` | DI registration — call `AddOpenPayAdapter(services, configuration)` from the composition root |

## Integration mode

`direct_3ds` — server-to-server card charge with 3D Secure redirect. Credentials (`OPENPAY_MERCHANT_ID`, `OPENPAY_PRIVATE_KEY`) are set as GitHub environment secrets and injected via Key Vault at runtime.

## Rules

- Credentials are never in source control or sharedsettings — Key Vault + `DefaultAzureCredential`.
- `IsProduction` flag in sharedsettings governs live vs test mode; adapter must respect it.
