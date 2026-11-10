# OpenPay Mexico Reference

Use this reference for repository work involving `XYDataLabs.OpenPayAdapter` or the OpenPay payment automation path. It describes integration boundaries and review obligations; it is not a provider acceptance report.

## Repository Boundary

- Keep OpenPay SDK types and provider-specific mapping inside `XYDataLabs.OpenPayAdapter`.
- Use the shared payment gateway and adapter contracts for Application and feature code.
- Keep tenant routing in the authoritative tenant registry; do not select OpenPay from UI input or a provider-row convenience flag.
- Preserve the existing callback, payment-attempt, currency, and idempotency contracts.

## Safety Rules

- Treat merchant identifiers, private keys, device session values, and webhook secrets as secrets. Read them only from the approved local secret or deployment configuration path.
- Never add real credentials, card data, CVV, or provider payloads containing sensitive values to source, fixtures, logs, prompts, or documentation.
- Keep sandbox behavior and production behavior explicitly distinguishable.
- Do not infer a successful OpenPay journey from a mocked adapter result or an HTTP page alone.

## Change Checklist

- Confirm the affected tenant/provider routing and tenant tier.
- Preserve provider callback verification and duplicate-callback handling.
- Preserve currency and amount mapping rules.
- Map provider declines and transient failures to the existing shared payment outcomes.
- Add focused adapter, handler, callback, or automation tests for the changed behavior.
- For runtime verification, correlate application logs, browser evidence, and database state using the existing verification prompt and approved environment.
