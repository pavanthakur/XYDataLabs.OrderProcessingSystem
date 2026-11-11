---
name: payment-provider-development
description: "Use when implementing or reviewing payment-provider adapters, tenant provider routing, callbacks, idempotency, payment automation, or provider-specific verification in this repository."
---

# Payment Provider Development

Use this skill for changes that cross provider adapters, tenant routing, payment state, callbacks, or payment automation. Combine it with the CQRS backend skill for C# application and persistence changes and the frontend skill for browser changes.

## Scope

Use when the task involves:

- OpenPay or Razorpay adapters and gateway contracts
- Tenant-specific provider selection or provider configuration
- Payment initiation, callback handling, reconciliation, or idempotency
- Payment status transitions, currency rules, or provider errors
- Payment browser automation, evidence reports, or provider verification
- Payment-related API, DTO, schema, or migration changes

Do not use this skill for:

- Generic backend features with no payment behavior
- Azure deployment work unrelated to payment runtime dependencies
- UI-only changes that do not alter payment behavior

## Required References

Open only the references relevant to the change:

- `.github/instructions/multitenant-payment-schema.instructions.md`
- `.github/instructions/clean-architecture.instructions.md`
- `.github/skills/cqrs-backend-implementation/SKILL.md` for backend code
- `.github/skills/frontend-feature-development/SKILL.md` for browser code
- `.github/skills/payment-provider-development/references/openpay-mexico.md` for OpenPay behavior
- `.github/skills/payment-provider-development/references/razorpay.md` for Razorpay behavior
- `.github/prompts/XYDataLabs-verify-db-logs.prompt.md` for evidence correlation
- `automation/config/runtime-targets.json` and the Azure skill when runtime targets change

## Operating Rules

1. Resolve provider routing from the authoritative tenant registry.
   - `Tenant.PaymentProviderCode` is the routing field.
   - Do not infer routing from a provider row's `IsActive` flag or from UI state.
   - Preserve shared-pool and dedicated-tenant behavior.
2. Preserve payment state and idempotency.
   - Use the existing payment identifiers and state model.
   - Treat duplicate callbacks and retries as expected cases.
   - Do not mark an operation successful before the provider and persistence outcomes are reconciled.
3. Keep provider-specific behavior behind the existing adapter and gateway abstractions.
   - Do not leak SDK types into Domain or Application contracts.
   - Keep provider mapping, signatures, and error translation at the integration boundary.
4. Protect payment and tenant data.
   - Never persist raw PAN or CVV.
   - Do not place credentials in source, prompts, fixtures, logs, or reports.
   - Do not expose internal tenant or payment trace identifiers in customer-facing contracts unless the existing contract explicitly permits it.
5. Separate structural and payment acceptance evidence.
   - A unit test or mocked provider result is not sandbox or production acceptance.
   - Provider transactions, database inspection, Docker resets, and Azure queries require explicit scoped approval.

## Recommended Flow

1. Identify the provider, tenant-routing path, payment state transition, and runtime target impact.
2. Read only the applicable provider, tenant, architecture, and automation references.
3. Trace the existing adapter/gateway, handler, persistence, callback, and evidence path before editing.
4. Make the smallest boundary-preserving change.
5. Add focused tests for routing, idempotency, state/error mapping, and tenant isolation.
6. Run safe targeted validation first; report unapproved provider or runtime checks as BLOCKED/NOT TESTED.
7. Run the completion governance path before handoff.

## Validation Path

- Focused backend and architecture tests for changed contracts.
- Focused frontend tests when browser payment behavior changes.
- Automation unit tests and dry runs when payment automation changes.
- `.github/prompts/XYDataLabs-verify-db-logs.prompt.md` only with the required environment and scoped access.
- `pwsh scripts/validate-ai-customization.ps1` when this skill or related shared guidance changes.
- `pwsh Resources/Azure-Deployment/validate-phase10-environment-contract.ps1` when payment changes add or rename Azure-visible runtime dependencies.

## Related Assets

- `XYDataLabs.OpenPayAdapter/`
- `XYDataLabs.RazorpayAdapter/`
- `XYDataLabs.OrderProcessingSystem.Payments.Features/`
- `automation/`
- `frontend/apps/web/src/payment-flow.ts`
- `tests/XYDataLabs.OrderProcessingSystem.Integration.Tests/`
