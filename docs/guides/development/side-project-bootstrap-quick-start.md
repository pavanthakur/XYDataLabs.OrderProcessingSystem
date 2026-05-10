# Side Project Bootstrap Quick Start

Use this guide when you want to start a real side project from the current repository baseline with the minimum practical setup effort.

Decision rationale and the full release/snapshot model live in [branch-and-blueprint-strategy.md](../../internal/branch-and-blueprint-strategy.md) and [ADR-018](../../architecture/decisions/ADR-018-blueprint-and-snapshot-strategy.md). This page is the short operator path.

## Rule First

- Side projects live in **separate repositories**, not long-lived branches in this repository.
- Before Phase 14, bootstrap from the best matching **snapshot tag**.
- After Phase 14, bootstrap from the two-layer model:
  - Layer 1: `XYDataLabs.SaaS.Templates` from NuGet
  - Layer 2: `xydatalabs-saas-blueprint` from GitHub template repo

## Current Recommended Baselines

| Product idea | Start from now | Why |
|---|---|---|
| `trading-analytics` | `v-20260510-phase8-frontend-spa` | Best current React + Azure + tenant-ready baseline |
| `whatsapp-automation` | `v-20260510-phase8-frontend-spa` | Best current React + API-ownership + automation-ready baseline |
| `azure-cost-optimizer` | `v-20260510-phase8-frontend-spa` | Best current Azure governance + React + workflow baseline |
| `ai-recruitment` | `v-20260510-phase8-frontend-spa` | Best current multi-tenant + React + event-ready baseline |
| B2B order/inventory SaaS variant | `XYDataLabs.SaaS.Templates::1.0.1` plus current runtime patterns | Closest fit to the live domain and already packaged as a reusable backend skeleton |

If a later phase creates a better seam for a product category, update the bootstrap matrix in [branch-and-blueprint-strategy.md](../../internal/branch-and-blueprint-strategy.md) instead of inventing an ad hoc branch strategy.

## Option A — Start Before Phase 14 (Snapshot Bootstrap)

Use this when the full `xydatalabs-saas-blueprint` repo does not exist yet.

```powershell
gh repo create <side-project-name> --private
git clone https://github.com/<your-account>/<side-project-name>.git
cd <side-project-name>

git remote add blueprint https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem.git
git fetch blueprint v-20260510-phase8-frontend-spa
git reset --hard FETCH_HEAD

git remote remove blueprint
git add -A
git commit -m "chore: initialize from snapshot v-20260510-phase8-frontend-spa"
git push -u origin main
```

Then strip or replace product-specific slices, rename namespaces, and document the chosen baseline in the new repo README.

## Option B — Start After Phase 14 (Two-Layer Bootstrap)

Use this when `xydatalabs-saas-blueprint` exists.

### Step 1: Create the repository from the GitHub template

Click **Use this template** on `xydatalabs-saas-blueprint`.

### Step 2: Install the Layer 1 .NET skeleton from NuGet

```powershell
dotnet new install XYDataLabs.SaaS.Templates::1.0.1
dotnet new xy-saas `
  -n TradingAnalytics `
  --rootNamespace Contoso.TradingAnalytics `
  --companySlug contoso `
  --productSlug tradinganalytics
```

### Step 3: Initialize blueprint-specific assets

```powershell
.\scripts\initialize-blueprint.ps1 `
  -ResourcePrefix <prefix> `
  -InitialTenants @("DefaultTenant")
```

### Step 4: Pin provenance in the new repository README

```text
BLUEPRINT_VERSION=blueprint-v1.0.0
DOTNET_TEMPLATE_VERSION=XYDataLabs.SaaS.Templates@1.0.1
```

## NuGet Commands For Consumers

Install a specific template line:

```powershell
dotnet new install XYDataLabs.SaaS.Templates::1.0.1
```

Check for newer template lines:

```powershell
dotnet new update --check-only
```

Remove the installed template package:

```powershell
dotnet new uninstall XYDataLabs.SaaS.Templates
```

## How The Versions Move

- If Layer 1 template files change, `PackageVersion` must move and the template governance workflow validates the packaged `.nupkg`.
- If future Layer 2 blueprint assets change, the phase-closeout gate decides whether the next `blueprint-v*` line is required.
- If neither Layer 1 nor Layer 2 bootstrap assets changed, do not create a new template release line.

## Related Docs

- [branch-and-blueprint-strategy.md](../../internal/branch-and-blueprint-strategy.md)
- [side-projects/README.md](./side-projects/README.md)
- [README-PUBLISH-TEMPLATE-PACKAGE.md](../../../.github/workflows/README-PUBLISH-TEMPLATE-PACKAGE.md)
- [README-VALIDATE-TEMPLATE-PACKAGE-GOVERNANCE.md](../../../.github/workflows/README-VALIDATE-TEMPLATE-PACKAGE-GOVERNANCE.md)
- [ADR-018](../../architecture/decisions/ADR-018-blueprint-and-snapshot-strategy.md)