# ADR-006: Passwordless Azure SQL via DefaultAzureCredential + Managed Identity

**Date:** 2026-03-20  
**Status:** Accepted  
**Deciders:** Project architect

---

## Context

ADR-004 established EF Core + Azure SQL with password authentication as a temporary measure. The following problems were identified:

1. **Hardcoded password in source control** — `Admin100@` was committed in `infra/parameters/*.json` and as a default in `provision-azure-sql.ps1`. This is a critical security vulnerability.
2. **No secret rotation** — A static password stored in Git and parameter files cannot be rotated without code changes and redeployments.
3. **Manual SQL setup after clean deploys** — The `/sql-mi-setup` prompt was required after every resource group teardown to recreate SQL contained users. This is error-prone and not automated.

## Decision

Replace all SQL password authentication with **Azure SQL Managed Identity** using the `Authentication=Active Directory Default` connection string property.

### SQL Admin Password (provisioning)

- **Bootstrap auto-generates** a cryptographically random password using `RandomNumberGenerator.GetBytes(32)` on first run
- Password is **stored exclusively in Azure Key Vault** (`sql-admin-password` secret) — no human ever sees it
- Subsequent bootstrap runs **retrieve the existing password** from KV (idempotent)
- `provision-azure-sql.ps1` retrieves the password from KV at runtime — no `-AdminPassword` default value in source
- `infra/parameters/*.json` use **ARM KV references** — ARM resolves the secret at deployment time without exposing it

### App Runtime Authentication (EF Core)

- Connection string uses `Authentication=Active Directory Default`
- **Not** `Authentication=Active Directory Managed Identity` — the `Default` variant uses the full `DefaultAzureCredential` chain, which covers both:
  - **Azure**: Managed Identity (system-assigned on App Service) picked up automatically
  - **Local dev**: `az login` → `AzureCliCredential` picked up automatically — no local password needed
- `Authentication=Active Directory Managed Identity` is rejected because it breaks local development

### SQL Contained User Setup (bootstrap-automated)

- `setup-sql-managed-identity.ps1` is invoked by `azure-bootstrap.yml` automatically on every bootstrap run
- No manual `/sql-mi-setup` prompt is required — the entire contained user lifecycle is automated

## Rationale

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| `Authentication=Active Directory Default` | Full `DefaultAzureCredential` chain — works locally + in Azure | Requires `az login` for local dev | ✅ Selected |
| `Authentication=Active Directory Managed Identity` | Explicit MI mode | Breaks local dev (no MI available on dev machine) | ❌ Rejected |
| GitHub Secret `SQL_ADMIN_PASSWORD` | Simple, no KV dependency | Secret stored outside KV, humans can read it, rotation requires workflow change | ❌ Rejected |
| KV reference in ARM parameters | Password in KV only, ARM resolves at deployment, nobody knows it | Requires bootstrap to run before infra-deploy | ✅ Selected (admin password path) |

## Consequences

**Positive:**
- No password for the SQL admin exists anywhere in source control, GitHub secrets, or config files
- Password rotation is trivial: delete KV secret, bootstrap regenerates on next run
- Local dev uses same codebase as production — `az login` provides credential chain coverage
- Bootstrap is fully idempotent: re-running does not change the SQL password if KV secret exists
- Eliminated manual `/sql-mi-setup` post-deploy step

**Negative / Trade-offs:**
- Local dev requires `az login` to an account that has access to Azure SQL (`aadAdminLogin`)
- First `infra-deploy.yml` run must happen AFTER bootstrap (KV must exist with the secret)
- ARM KV reference requires `enabledForTemplateDeployment: true` on the KV (already set in `infra/modules/keyvault.bicep`)
- OIDC SP needs `secrets: get, list` access policy on KV for ARM to resolve references (set by bootstrap via `-OidcSpObjectId`)

## Implementation Notes

- KV name formula (from `infra/modules/keyvault.bicep`): `kv-${take(baseName,15)}-${environment}` → `kv-orderprocessing-{dev|stg|prod}`
- `enabledForTemplateDeployment: true` is set in [infra/modules/keyvault.bicep](../../../infra/modules/keyvault.bicep)
- OIDC SP objectId is stored as `OIDC_SP_OBJECT_ID` repo-level GitHub secret (set by Phase 1b of `azure-initial-setup.yml`)
- `bootstrap-enterprise-infra.ps1` accepts `-OidcSpObjectId` parameter; passed from `azure-bootstrap.yml` via `${{ secrets.OIDC_SP_OBJECT_ID }}`

## Related

- ADR-004: EF Core 8 + Azure SQL — this ADR supersedes the "password auth → passwordless planned" note
- ADR-002: OIDC passwordless auth — same pattern applied to SQL
- [infra/modules/keyvault.bicep](../../../infra/modules/keyvault.bicep) — KV with `enabledForTemplateDeployment: true`
- [Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1](../../../Resources/Azure-Deployment/bootstrap-enterprise-infra.ps1) — password generation
- [Resources/Azure-Deployment/provision-azure-sql.ps1](../../../Resources/Azure-Deployment/provision-azure-sql.ps1) — KV retrieval
