# Razorpay Reference

Use this reference for repository work involving `XYDataLabs.RazorpayAdapter` or Razorpay payment automation. It describes integration boundaries and review obligations; it is not a provider acceptance report.

## Repository Boundary

- Keep Razorpay SDK types, key validation, signature handling, and provider mapping inside `XYDataLabs.RazorpayAdapter`.
- Use the shared payment gateway and adapter contracts for Application and feature code.
- Preserve the tenant registry as the routing authority and keep per-tenant payment flags in the business database.
- Preserve the existing hosted-checkout, callback, payment-attempt, and reconciliation contracts.

## Safety Rules

- Keep `IsProduction` and key-prefix validation aligned with the existing configuration validator.
- Treat key IDs, key secrets, webhook secrets, and provider payloads as sensitive; never place real values in source, fixtures, logs, prompts, or documentation.
- Never persist raw card data or CVV.
- Do not claim production or sandbox acceptance from a mocked gateway response.

## Change Checklist

- Confirm the tenant and active provider from the authoritative registry.
- Preserve signature verification, idempotency, duplicate callback handling, and amount/currency mapping.
- Preserve terminal decline versus reconciliation-required error mapping.
- Add focused tests for configuration validation, adapter mapping, callback behavior, and relevant automation.
- For runtime verification, correlate logs, browser evidence, and database state through the approved verification workflow.
