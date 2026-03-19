# ADR-003: Subscription-Scope Bicep for Infrastructure Deployment

**Date:** 2025-02-01  
**Status:** Accepted  
**Deciders:** Project architect

---

## Context

Bicep templates can be deployed at different scopes:
- **Resource Group scope** — deploys resources into an existing resource group
- **Subscription scope** — can create resource groups AND deploy resources in one operation

The project needs to provision the entire environment from scratch (resource group + all resources) in a single workflow run, ideally idempotent.

## Decision

`infra/main.bicep` uses `targetScope = 'subscription'` and is deployed with:
```powershell
az deployment sub create \
  --location centralindia \
  --template-file infra/main.bicep \
  --parameters infra/parameters/dev.json
```

The resource group itself is created inside `main.bicep` as a resource:
```bicep
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: 'rg-orderprocessing-${environment}'
  location: location
}
```

## Rationale

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| Subscription scope | Single command provisions everything incl. RG; idempotent; enterprise standard | Needs Contributor at subscription level; `az deployment sub create` (easy to mistake for `group create`) | ✅ Selected |
| Resource Group scope | Simpler permissions | RG must be pre-created manually or in a separate step; two-phase bootstrap | ❌ Rejected |

## Consequences

**Positive:**
- Day-zero environment creation: one command, zero manual steps
- All environments (dev/staging/prod) follow identical provisioning path

**Negative / Trade-offs:**
- OIDC Service Principal needs Contributor at subscription level (broader than RG-level)
- **Common mistake**: developers use `az deployment group create` instead of `az deployment sub create` — this fails with a confusing scope error

**Critical rule:**
```powershell
# ✅ CORRECT
az deployment sub create --location centralindia ...

# ❌ WRONG — will fail for infra/main.bicep
az deployment group create --resource-group rg-... ...
```

**Future obligations:**
- `bicep/` folder uses resource-group scope — use `az deployment group create` for that folder only
- Document the scope distinction in any runbook that touches `infra/`

## Related
- ADR-002: OIDC auth (requires subscription-level Contributor role for this to work)
- `infra/main.bicep` — `targetScope = 'subscription'`
- `bicep/appservice-with-kv.bicep` — resource group scope (separate folder, separate command)
