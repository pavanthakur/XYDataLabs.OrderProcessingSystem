---
applyTo: "**/docs/architecture/**,**/*ADR*"
---
# Architecture Decision Records — XYDataLabs.OrderProcessingSystem

## ADR Location
All ADRs live in `docs/architecture/decisions/ADR-NNN-title.md`

## Current ADRs
| ADR | Decision | Status |
|-----|----------|--------|
| ADR-001 | Clean Architecture with DDD layers | ✅ Accepted |
| ADR-002 | OIDC passwordless auth for GitHub Actions → Azure | ✅ Accepted |
| ADR-003 | Subscription-scope Bicep (`az deployment sub create`) | ✅ Accepted |
| ADR-004 | EF Core 8 + Azure SQL (password auth → passwordless planned) | ✅ Accepted, evolving |
| ADR-005 | Serilog structured logging | ✅ Accepted, enrichers pending |
| ADR-006 | Passwordless SQL via DefaultAzureCredential + Managed Identity | ✅ Accepted 2026-03-20 |

## When to Write an ADR
Write one whenever you:
- Choose technology X over Y (and there's a non-obvious reason)
- Set a constraint that future developers must not accidentally break
- Make a decision that will be expensive to reverse
- Hit a gotcha that will trip up the next person

## ADR Format (use ADR-000-template.md)
Context → Decision → Rationale table → Consequences → Related

## Key Architectural Rules (never break these)
1. **Domain and Application layers have ZERO Azure SDK / EF Core imports** — Infrastructure only
2. **No credentials in code or config files** — Key Vault + OIDC + DefaultAzureCredential only
3. **`az deployment sub create` for `infra/`** — never `az deployment group create`
4. **Structured logging only** — `Log.Information("{Key}", value)` not `$"text {value}"`
5. **OIDC only for CI/CD** — never add `client-secret:` to any workflow
