# ADR-002: OIDC Passwordless Authentication for GitHub Actions → Azure

**Date:** 2025-01-15  
**Status:** Accepted  
**Deciders:** Project architect

---

## Context

GitHub Actions workflows need to authenticate to Azure to deploy resources and applications. Options:
- Store a Service Principal client secret in GitHub Secrets (traditional approach)
- Use OIDC federated identity (no stored secret)

The stored secret approach has known risks: secrets expire, get leaked in logs, must be rotated manually, and create a persistent credential that can be stolen.

## Decision

Use OIDC federated identity credentials between GitHub Actions and Azure Entra ID. No passwords or service principal secrets stored anywhere.

```yaml
permissions:
  id-token: write     # request short-lived OIDC token
  contents: read
steps:
  - uses: azure/login@v2
    with:
      client-id: ${{ secrets.AZUREAPPSERVICE_CLIENTID }}
      tenant-id: ${{ secrets.AZUREAPPSERVICE_TENANTID }}
      subscription-id: ${{ secrets.AZUREAPPSERVICE_SUBSCRIPTIONID }}
```

The GitHub Actions OIDC token is valid for the duration of the job only. Azure validates the token against configured federated credentials (repo, branch, environment).

## Rationale

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| OIDC (no secret) | No expiry, no rotation, no leak risk, short-lived | Slightly more complex initial setup | ✅ Selected |
| Service Principal secret | Simple setup | Expires, rotation burden, leak risk, broad access window | ❌ Rejected |
| Managed Identity (Azure-hosted runner) | Zero config | Requires Azure-hosted runner ($$$) | ❌ Not applicable |

## Consequences

**Positive:**
- No stored credentials → zero credential rotation burden
- Token valid for job duration only → minimal blast radius if intercepted
- Azure Entra ID federated credentials are scoped to specific repo/branch/environment

**Negative / Trade-offs:**
- Initial setup requires running `azure-initial-setup.yml` once per repo
- Federated credentials must exist for each branch (`dev`, `staging`, `main`) AND each environment
- `AADSTS700213` error if environment credential is missing — run Initial Setup workflow with `environment=all` to fix

**Future obligations:**
- Any new branch or environment requires adding a new federated credential (via `fix-federated-credential.ps1`)
- Never add `client-secret:` to any workflow YAML — if you feel the need, re-run Initial Setup instead

## Related
- ADR-003: Choice to use subscription-scope Bicep (same OIDC identity needs Contributor at subscription level)
- `.github/workflows/azure-initial-setup.yml` — sets up federated credentials
- `Resources/Azure-Deployment/setup-github-oidc.ps1`
