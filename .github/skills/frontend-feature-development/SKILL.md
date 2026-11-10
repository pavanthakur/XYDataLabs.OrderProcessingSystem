---
name: frontend-feature-development
description: "Use when implementing or reviewing React and TypeScript features in frontend/apps/web or shared frontend packages, especially tenant-aware API and payment UI changes."
---

# Frontend Feature Development

Use this skill for React and TypeScript work in the `frontend/` workspace. Combine it with the payment-provider skill when a browser flow changes payment behavior and with the CQRS backend skill when the API contract also changes.

## Scope

Use when the task involves:

- React pages, components, hooks, or browser flows
- `frontend/packages/api-sdk` or tenant-session contracts
- Tenant-aware runtime configuration and session behavior
- Payment pages, callbacks, customer/order selection, or payment status UI
- Frontend component tests, typechecks, builds, or browser verification

Do not use this skill for:

- Backend-only C# changes
- Azure or CI/CD changes without frontend behavior
- Provider adapter implementation without browser changes

## Required References

- `.github/instructions/frontend.instructions.md`
- `.github/instructions/multitenant-payment-schema.instructions.md` when tenant or payment behavior changes
- `.github/skills/payment-provider-development/SKILL.md` for provider or payment-flow changes
- `frontend/apps/web/package.json`
- `frontend/packages/api-sdk/` when API contracts change
- `frontend/packages/tenant-session/` when tenant context changes
- `.github/prompts/XYDataLabs-new-feature.prompt.md` when the work is a full-stack feature

## Operating Rules

1. Follow the existing package and component boundaries.
   - Reuse the API SDK and tenant-session package.
   - Keep shared contracts in the appropriate frontend package.
   - Do not duplicate API clients or embed backend URLs in components.
2. Preserve tenant safety.
   - Use API runtime configuration for the active tenant.
   - Do not let browser state choose the authoritative tenant or payment provider.
   - Do not expose internal tenant IDs in public UI contracts.
3. Preserve payment safety.
   - Never log or persist raw card data, CVV, credentials, or private keys.
   - Preserve sandbox/live indicators and callback outcome handling.
   - Treat payment status as server-owned state.
4. Keep API changes explicit.
   - Update the SDK contract and tests when the backend contract changes.
   - Coordinate backend DTO/controller changes through the full-stack feature workflow.
5. Prefer focused validation.
   - Add or update component tests for changed behavior.
   - Run the affected package tests, typecheck, and build before broader repository checks.
   - Browser verification is required when navigation, callbacks, or visible payment behavior changes; report it as NOT TESTED when unavailable.

## Review Checklist

- Does the change preserve tenant resolution and approved header behavior?
- Does it avoid provider routing or security decisions in the browser?
- Are loading, error, callback, and retry states covered?
- Are API contract and TypeScript types synchronized?
- Are secrets and sensitive payment identifiers excluded from UI, logs, and test fixtures?
- Are focused tests present and relevant browser checks reported accurately?

## Related Assets

- `frontend/apps/web/`
- `frontend/packages/api-sdk/`
- `frontend/packages/tenant-session/`
- `.github/instructions/frontend.instructions.md`
- `.github/skills/payment-provider-development/SKILL.md`
