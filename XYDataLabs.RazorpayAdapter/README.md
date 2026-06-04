# RazorpayAdapter

Razorpay payment provider integration. Implements `IPaymentProviderGateway` registered under the `"Razorpay"` DI key.

## Key types

| Type | Purpose |
|------|---------|
| `RazorpayPaymentGateway` | Implements `IPaymentProviderGateway` — entry point called by `ProcessPaymentCommandHandler` |
| `RazorpayAdapterService` / `IRazorpayAdapterService` | Razorpay SDK wrapper |
| `Configuration/RazorpayConfig` | `KeyId`, `KeySecret`, `IsProduction` — loaded via `IOptions<RazorpayConfig>` |
| `Configuration/RazorpayConfigValidator` | Startup validator — enforces key prefix (`rzp_test_*` vs `rzp_live_*`) matches `IsProduction` flag; fails startup on mismatch |
| `ServiceCollectionExtensions` | DI registration — `AddRazorpayAdapter(services, configuration)` |

## Integration modes (per-tenant, DB-owned)

| `Use3DSecure` | Mode | Flow |
|---------------|------|------|
| `false` | `provider_checkout` | Razorpay Checkout JS popup — 3DS handled inside Razorpay SDK (SAQ A, no PCI scope) |
| `true` | `direct_card_form` | Server-to-server direct charge — requires Razorpay account S2S activation (support ticket required) |

`Use3DSecure` per tenant is DB-owned (`PaymentProvider` table) — never read from config.

## Local test key

`rzp_test_Sw0mDv0bcs4oKO` — configured in `sharedsettings.local.json` under `Razorpay:KeyId`.

## Rules

- `RazorpayConfigValidator` runs at startup; mismatch between key prefix and `IsProduction` is a fatal error.
- Credentials (`RAZORPAY_MERCHANT_ID`, `RAZORPAY_PRIVATE_KEY`) set as GitHub environment secrets for dev/staging/prod — injected via Key Vault at runtime.
- `IsProduction = false` is the required default in all sharedsettings files.
