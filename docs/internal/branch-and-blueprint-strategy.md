# Branch + Blueprint Strategy

> Operational runbook for snapshot management and reusable template packaging.
> Decision rationale: [ADR-018](../architecture/decisions/ADR-018-blueprint-and-snapshot-strategy.md).

## TL;DR

| Concern | Mechanism |
|---|---|
| Point-in-time backup | **Annotated tag + protected backup branch** at the same commit (Path C) |
| Backup naming | Tag `v-YYYYMMDD-phase<N>-<slug>` + branch `dev-backup-YYYYMMDD-<Scope>-Upto-Phase<N>` |
| Backup cadence | Major architectural seams (Phase 7, 8, 11, 13, 14) + before any irreversible architectural change |
| Reusable template (.NET solution) | `dotnet new` template via NuGet package `XYDataLabs.SaaS.Templates` (extracted at Phase 14) |
| Reusable template (workflows / Bicep / frontend / Docker / docs / AI) | GitHub template repository `xydatalabs-saas-blueprint` (extracted at Phase 14) |
| Side-project location | Separate GitHub repos, optionally under `pavanthakur-saas/` org |

---

## 1. Snapshot mechanism

### 1.1 Naming format

| Kind | Format | Example |
|---|---|---|
| Tag | `v-YYYYMMDD-phase<N>-<slug>` | `v-20260409-phase7-multitenant` |
| Backup branch | `dev-backup-YYYYMMDD-<Scope>-Upto-Phase<N>` | `dev-backup-20260409-Multitenant-Upto-Phase7` |
| Side-project branch (in target side-project repo, not this one) | `side-project/<name>` | `side-project/trading-analytics` |
| Pre-irreversible-change snapshot | `v-YYYYMMDD-pre-<change>` | `v-20260820-pre-microservices-split` |

### 1.2 Cut-a-snapshot procedure

When the closing commit of a phase is `<sha>`:

```powershell
# 1. Annotated tag with structured message (see §1.3 for message standard)
git tag -a v-YYYYMMDD-phase<N>-<slug> <sha> -m "<structured message>"

# 2. Backup branch from the same commit
git branch dev-backup-YYYYMMDD-<Scope>-Upto-Phase<N> <sha>

# 3. Push both
git push origin v-YYYYMMDD-phase<N>-<slug>
git push origin dev-backup-YYYYMMDD-<Scope>-Upto-Phase<N>
```

### 1.3 Tag message standard

```
v-YYYYMMDD-phase<N>-<slug>

Phase: <N> (<short description>)
Anchor commit: <sha> <subject>
Companion branch: dev-backup-YYYYMMDD-<Scope>-Upto-Phase<N>

ADRs ratified (in this phase or before): ADR-NNN..ADR-MMM
<Domain summary lines: multi-tenant, payments, frontend, etc.>
Automation matrix: <path to automation/reports/.../summary.md when relevant>
Docker matrix: <status>
Azure: <status>

Intentionally absent at this baseline:
- <feature deferred to a later phase>
- ...
```

### 1.4 When to cut a snapshot

| Trigger | Cut? |
|---|---|
| Major architectural seam closeout (Phase 7, 8, 11, 13, 14) | ✅ Yes |
| Before an irreversible architectural change (microservices split, PK strategy change, multi-region rollout) | ✅ Yes |
| Minor phase closeout (8.5, 8.7, 9.5) | ❌ Normal Day Complete only |
| Day Complete on a non-seam day | ❌ |
| Daily CI build | ❌ CI artifacts already exist |
| Pre-EF-migration | ❌ Migrations are themselves reversible |

### 1.5 Branch protection rule (one-time GitHub setup)

Apply once to the pattern `dev-backup-**` in **Settings → Branches → Branch protection rules → Add rule**:

| Setting | Value |
|---|---|
| Branch name pattern | `dev-backup-**` |
| Restrict pushes that create matching branches | ❌ (must allow creation by maintainers when cutting a snapshot) |
| Require a pull request before merging | ❌ (merges not expected) |
| Require status checks to pass before merging | ❌ |
| Require conversation resolution | ❌ |
| Require signed commits | Optional |
| Require linear history | ❌ |
| **Block force pushes** | ✅ **Required** |
| **Restrict deletions** | ✅ **Required** |
| Allow bypassing the above settings | ❌ |
| Restrict who can push to matching branches | ✅ (only repo admin) |

This makes pushed `dev-backup-*` branches effectively immutable, matching the immutability of
the companion tag.

### 1.5.1 Active branch protection baseline (`dev`, `staging`, `main`)

The delivery branches should be protected enough to prevent destructive history changes, but not so tightly that the current direct-push operating model is broken.

Apply this baseline to `dev`, `staging`, and `main`:

| Setting | Value |
|---|---|
| Require a pull request before merging | ❌ Not yet, because the current operating model still allows direct pushes |
| Require status checks to pass before merging | ❌ Not yet, until PR-only flow is adopted |
| Require conversation resolution | ❌ |
| Require signed commits | Optional |
| Require linear history | ❌ |
| **Block force pushes** | ✅ **Required** |
| **Restrict deletions** | ✅ **Required** |
| Allow bypassing the above settings | ✅ Admin only |

This baseline protects the branch from destructive rewrites immediately while preserving the current workflow. The `validate-template-package-governance.yml` workflow still provides automatic signal and packaged smoke validation for Layer 1 template changes on both pull requests and direct pushes.

When the repository later moves to PR-only delivery, upgrade this baseline to require pull requests plus required status checks.

### 1.6 Existing snapshots

| Date | Phase | Tag | Branch |
|------|-------|-----|--------|
| 2026-04-09 | 7 — Multi-tenant baseline | `v-20260409-phase7-multitenant` | `dev-backup-20260409-Multitenant-Upto-Phase7` |
| 2026-05-10 | 8 — Frontend SPA + OIDC deploy | `v-20260510-phase8-frontend-spa` | `dev-backup-20260510-FrontendSPA-Upto-Phase8` |
| 2026-05-10 | 8 — Template release seam hardening | `v-20260510-pre-template-release-1-0-0` | `dev-backup-20260510-TemplateRelease-Upto-Phase8` |
| 2026-05-10 | 8 — Template README patch release | `v-20260510-pre-template-readme-1-0-1` | `dev-backup-20260510-TemplateReadmePatch-Upto-Phase8` |

---

## 2. Reusable template (two layers)

### 2.1 Layer 1 — `dotnet new` template (NuGet)

| Aspect | Value |
|---|---|
| Package id | `XYDataLabs.SaaS.Templates` |
| Mechanism | `.template.config/template.json` (Julio Casal pattern) |
| Current release location | `templates/xy-saas/` source tree + `templates/XYDataLabs.SaaS.Templates/XYDataLabs.SaaS.Templates.csproj` pack project |
| Ships | API/Application/Domain/Infrastructure/SharedKernel/PaymentGateway + 5 test projects, EF Core scaffolding, multi-tenant primitives, hand-rolled CQRS skeleton, `Result<T>`, NetArchTest layer rules |
| Versioning | NuGet semver (`1.0.0`, `1.1.0`, ...); each version immutable |
| Bootstrap | `dotnet new install <local-or-nupkg-path>` then `dotnet new xy-saas -n <ProductName> --rootNamespace <Company.Product> --companySlug <companyslug> --productSlug <productslug>` |
| Publish trigger | Phase 14 closeout for the first formal NuGet/template release; version `1.0.0` is the first release-ready validated package line and is published through `.github/workflows/publish-template-package.yml` |

#### 2.1.1 Public release note draft — `1.0.0`

Use the text below as the baseline GitHub/NuGet release summary for the first formal Layer 1 package publication:

```text
XYDataLabs.SaaS.Templates 1.0.0

First formal release of the Layer 1 `dotnet new` template for the XYDataLabs multi-tenant SaaS backend skeleton.

Highlights
- Ships a complete .NET 8 Clean Architecture solution skeleton with API, Application, Domain, Infrastructure, SharedKernel, PaymentGateway, and five test projects.
- Replaces the template's internal provider lock-in with a provider-agnostic `PaymentGateway` seam and a default in-memory implementation that is safe for bootstrap and smoke validation.
- Preserves multi-tenant primitives, EF Core scaffolding, hand-rolled CQRS, `Result<T>`, and NetArchTest architecture guardrails.
- Removes the legacy OpenPayAdapter surface from generated solutions.

Validated for this release
- `dotnet pack templates/XYDataLabs.SaaS.Templates/XYDataLabs.SaaS.Templates.csproj -c Release --nologo`
- `dotnet new install <nupkg>` and `dotnet new xy-saas ...` packaged smoke flow
- Generated solution restore/build smoke pass with the new `PaymentGateway` project surface
- Documentation link validation and release-surface alignment across README, ADR-018, and the blueprint strategy runbook

Install
dotnet new install XYDataLabs.SaaS.Templates::1.0.0

Create a new solution
dotnet new xy-saas -n <ProductName> --rootNamespace <Company.Product> --companySlug <companyslug> --productSlug <productslug>
```

#### 2.1.2 Patch release note draft — `1.0.1`

Use the text below as the baseline GitHub/NuGet release summary for the README patch publication:

```text
XYDataLabs.SaaS.Templates 1.0.1

Patch release for the Layer 1 `dotnet new` template package.

Highlights
- Adds a packaged NuGet README so the package page carries install and bootstrap guidance directly from source control.
- Preserves the validated .NET 8 Clean Architecture template surface shipped in 1.0.0, including API, Application, Domain, Infrastructure, SharedKernel, PaymentGateway, and five test projects.
- Keeps the provider-agnostic `PaymentGateway` seam and default in-memory bootstrap implementation unchanged.

Validated for this release
- `dotnet pack templates/XYDataLabs.SaaS.Templates/XYDataLabs.SaaS.Templates.csproj -c Release --nologo`
- Packaged README present at the `.nupkg` root
- `dotnet new install <nupkg>` and `dotnet new xy-saas ...` packaged smoke flow
- Generated solution restore/build smoke pass

Install
dotnet new install XYDataLabs.SaaS.Templates::1.0.1

Create a new solution
dotnet new xy-saas -n <ProductName> --rootNamespace <Company.Product> --companySlug <companyslug> --productSlug <productslug>
```

#### 2.1.3 Ongoing template release governance

The Layer 1 template line is no longer a one-time manual activity.

Automatic enforcement now exists through `.github/workflows/validate-template-package-governance.yml`:
- Any pull request that changes `templates/xy-saas/` or `templates/XYDataLabs.SaaS.Templates/` must also bump `PackageVersion` in `templates/XYDataLabs.SaaS.Templates/XYDataLabs.SaaS.Templates.csproj`.
- Direct pushes to `dev`, `staging`, or `main` that touch the same Layer 1 template surface also run the packaged smoke path automatically, so the branch signals template drift immediately even before formal publication.
- The same workflow always packs the `.nupkg`, installs it, generates a smoke solution, and builds the generated output.

That means `dev` always carries the next intended NuGet template line when the generated template itself changes, even if public publication happens later from a tag.

Use this decision rule going forward:

| Change type | Action |
|---|---|
| Layer 1 generated backend skeleton changes under `templates/xy-saas/` | Bump `PackageVersion`; let the governance workflow validate; publish later via `publish-template-package.yml` when the tagged baseline is ready |
| Layer 1 package metadata or packaged README changes under `templates/XYDataLabs.SaaS.Templates/` | Bump `PackageVersion`; validate; publish later from tag |
| Layer 2 blueprint-only assets such as workflows, Bicep, frontend, Docker, docs, or AI assets outside Layer 1 | Do not bump the NuGet package; cut a new GitHub template repo/tag when that Layer 2 baseline is ready |
| Runtime repository code only | No template release action |

Consumer installation remains version-pinned through NuGet:

```powershell
dotnet new install XYDataLabs.SaaS.Templates::1.0.1
dotnet new update --check-only
dotnet new uninstall XYDataLabs.SaaS.Templates
```

### 2.2 Layer 2 — GitHub template repository

| Aspect | Value |
|---|---|
| Repo name | `xydatalabs-saas-blueprint` |
| Mechanism | GitHub "Template repository" feature (Settings → Template repository ✓) |
| Ships | `.github/workflows/`, `infra/` Bicep, `bicep/` resource-group variant, `Resources/Docker/`, `frontend/` workspace, `automation/` workspace shell, `docs/` governance scaffolding, ADR template, `.github/instructions/`, `.github/prompts/`, `.github/agents/`, `.github/skills/`, AI customization assets |
| Versioning | Annotated tags `blueprint-v1.0.0`, `blueprint-v1.1.0` on the template repo |
| Bootstrap | "Use this template" button on the GitHub repo page |
| Extraction trigger | Phase 14 closeout |

#### 2.2.1 Future Layer 2 governance after extraction

Layer 2 cannot be published through NuGet because it includes workflows, Bicep, frontend, Docker, docs, and AI customization assets. Its release mechanism is the GitHub template repository plus immutable `blueprint-v*` tags.

Use this rule once `xydatalabs-saas-blueprint` exists:

| Change type in blueprint repo | Action |
|---|---|
| Workflow, Bicep, frontend, Docker, docs, AI asset, or bootstrap-script change that should affect new side projects | Cut the next `blueprint-v*` tag and update the blueprint repo release notes |
| Template repo metadata only with no bootstrap impact | No blueprint version bump required |
| Side-project-specific customization in a consumer repo | No blueprint release action |

Expected automation after extraction:
- a blueprint governance workflow in the blueprint repo should watch the Layer 2 asset paths
- that workflow should require a version-decision update for the next `blueprint-v*` line
- the repo release process should then create the tag and GitHub release from the validated baseline

That gives both layers the same operating model: Layer 1 uses NuGet semver, Layer 2 uses GitHub template tags.

Recommended concrete implementation in the future blueprint repo:

| Concern | Recommended mechanism |
|---|---|
| Version-decision artifact | Root file `BLUEPRINT_VERSION` containing only the next intended immutable tag name, for example `blueprint-v1.1.0` |
| Governance workflow name | `Validate Blueprint Governance` |
| PR rule | If any Layer 2 asset path changes, `BLUEPRINT_VERSION` must also change |
| Push rule | On direct pushes, still run the blueprint validation matrix so drift is visible immediately |
| Release mechanism | Create annotated tag from `BLUEPRINT_VERSION`, then create the matching GitHub release |

Recommended watched paths in the future blueprint repo:
- `.github/workflows/**`
- `infra/**`
- `bicep/**`
- `Resources/Docker/**`
- `frontend/**`
- `automation/**`
- `docs/**`
- `.github/instructions/**`
- `.github/prompts/**`
- `.github/agents/**`
- `.github/skills/**`
- bootstrap scripts such as `scripts/setup-local.ps1` and `scripts/initialize-blueprint.ps1`

Recommended validation matrix in the future blueprint repo:
- docs link validation
- AI customization validation
- workflow YAML validation
- Bicep validation / what-if-safe static checks
- frontend install + build where applicable
- bootstrap script lint or smoke checks where practical

Recommended release flow after extraction:
1. Change Layer 2 assets.
2. Update `BLUEPRINT_VERSION` to the next intended `blueprint-v*` line.
3. Let `Validate Blueprint Governance` pass on the PR.
4. Merge the PR.
5. Cut the annotated tag named in `BLUEPRINT_VERSION`.
6. Create the matching GitHub release with the Layer 2 change summary.

This mirrors the current Layer 1 pattern exactly:
- Layer 1: `PackageVersion` in the template pack project, then NuGet publish.
- Layer 2: `BLUEPRINT_VERSION` in the blueprint repo, then GitHub template tag + release.

#### 2.2.2 Mandatory phase-closeout gate for blueprint releases

At the end of every phase closeout, run this rule before declaring the phase complete:

1. Review the phase changes against the future Layer 2 watched paths.
2. Ask one explicit question: did this phase change any bootstrap asset that every new side project should inherit?
3. If yes, plan the next `xydatalabs-saas-blueprint` line and advance `BLUEPRINT_VERSION` when the blueprint repo exists.
4. If the phase changed only Layer 1 generated backend template assets, advance the NuGet template `PackageVersion` instead.
5. If the phase changed neither Layer 1 nor Layer 2 bootstrap assets, record that no template release action is required.

Treat this as a mandatory closeout gate, not optional guidance. The trigger is not "every phase creates a blueprint release"; the trigger is "phase closeout plus Layer 2 bootstrap impact."

### 2.3 Why two layers and not one

| Mechanism | Can ship `src/` solution? | Can ship workflows / Bicep / frontend / Docker / docs? | Used by |
|---|---|---|---|
| `dotnet new` (NuGet) | ✅ Native (`sourceName`, symbol replace) | ❌ Not designed for this | Layer 1 |
| GitHub template repo | ✅ Yes but no symbol-driven rename | ✅ Native | Layer 2 |

Each layer covers what the other cannot. They are layered on bootstrap, not chosen between.

### 2.4 Bootstrapping a side project (post-Phase-14)

```powershell
# 1. Click "Use this template" on github.com/<org>/xydatalabs-saas-blueprint
#    -> creates github.com/<your-account>/<side-project-name>

# 2. Clone the new repo locally
git clone https://github.com/<your-account>/<side-project-name>.git
cd <side-project-name>

# 3. Install and run the .NET solution skeleton
dotnet new install XYDataLabs.SaaS.Templates::1.0.1
dotnet new xy-saas `
  -n TradingAnalytics `
  --rootNamespace Contoso.TradingAnalytics `
  --companySlug contoso `
  --productSlug tradinganalytics

# 4. Apply blueprint parameterization (resource prefix, tenants, namespaces)
.\scripts\initialize-blueprint.ps1 `
    -ResourcePrefix <prefix> `
    -InitialTenants @("DefaultTenant")

# 5. First commit
git add -A
git commit -m "chore: initialize from blueprint-v1.0.0 + dotnet template 1.0.1"

# 6. Local dev setup
.\scripts\setup-local.ps1

# 7. Azure setup (run once per side project)
gh workflow run azure-initial-setup.yml

# 8. Azure infrastructure + first deploy
gh workflow run azure-bootstrap.yml -f environment=dev

# 9. Pin blueprint + template versions in README.md
# BLUEPRINT_VERSION=blueprint-v1.0.0
# DOTNET_TEMPLATE_VERSION=XYDataLabs.SaaS.Templates@1.0.1
```

### 2.5 Bootstrapping a side project (pre-Phase-14)

If a side project (e.g. AI WhatsApp Automation MVP) is needed before Phase 14 closeout:

```powershell
# Fork from the most appropriate snapshot tag
gh repo create <side-project-name> --private
git clone https://github.com/<your-account>/<side-project-name>.git
cd <side-project-name>

# Pull the snapshot as initial commit
git remote add blueprint https://github.com/pavanthakur/XYDataLabs.OrderProcessingSystem.git
git fetch blueprint v-20260409-phase7-multitenant
git reset --hard FETCH_HEAD

# Strip product-specific code manually (Order/Payment entities, provider-specific payment integration)
# Rename namespaces manually (or via a one-time PowerShell script)

# First commit
git remote remove blueprint
git add -A
git commit -m "chore: initialize from snapshot v-20260409-phase7-multitenant"
git push -u origin main
```

Pre-Phase-14 forks are intentionally manual for the full two-layer bootstrap. The Layer 1
prototype already exists in-repo and has been validated locally via `dotnet pack`,
`dotnet new install <nupkg>`, and generated-solution restore/build smoke tests.

---

## 3. Side projects

### 3.1 Location and naming

Side projects live in **separate GitHub repositories**, ideally under a dedicated org
(`pavanthakur-saas/`) for clean portfolio branding. They do **not** live as long-lived
branches in this repository.

### 3.2 Prioritized side projects

| # | Side project | Bootstrap source | Realistic MVP |
|---|---|---|---|
| 1 | `trading-analytics` (flagship) | Blueprint v1.x + dotnet template | 6–8 weeks |
| 2 | `whatsapp-automation` | Blueprint + WhatsApp adapter | 4–6 weeks |
| 3 | `azure-cost-optimizer` | Blueprint + Cost Management API client | 6–8 weeks |
| 4 | `ai-recruitment` | Blueprint + Azure OpenAI + Elasticsearch | 8–10 weeks |
| 5 | (this repo) order-processing | — already exists | — |

### 3.3 Per-side-project conventions

- Pin `BLUEPRINT_VERSION` (Layer 2 tag) and `DOTNET_TEMPLATE_VERSION` (Layer 1 NuGet version)
  in the side project's `README.md`.
- Inherit `automation/reports/` per-run summary discipline from the blueprint.
- Inherit `docs/internal/` status surface pattern from the blueprint.
- Each side project maintains its own ADRs starting at ADR-000-template.

---

## 4. Divergences from Julio Casal's `dotnet-backend-blueprint`

The blueprint draws on Julio Casal's `dotnet-backend-blueprint` v10 skeleton template pattern
but diverges where this repo's existing investments produce stronger architect-level signal:

| Aspect | Julio's blueprint | This blueprint | Reason |
|---|---|---|---|
| Architecture style | Vertical Slice + minimal APIs | Clean Architecture + hand-rolled CQRS | Already invested; produces stronger domain isolation; senior architect signal |
| Auth | Keycloak | Azure AD + JWT primary; Keycloak as Phase 9.5 portability showcase (ADR-017) | Multi-tenant SaaS market expects Entra/AAD primary |
| Local orchestration | .NET Aspire | Docker Compose matrix + VS F5 profiles; Aspire optional in Phase 13+ | Already proven in this repo |
| Deploy target | `aspire deploy` to Azure Container Apps | OIDC GitHub Actions → App Service; ACA in Phase 11 | Already proven; ACA is a Phase 11 migration |
| RDBMS | PostgreSQL | SQL Server primary; PostgreSQL as Phase 11.5 portability showcase (ADR-017) | Already proven; ADR-017 sequences PG as polyglot showcase |
| Template mechanism | `dotnet new` only | `dotnet new` (Layer 1) + GitHub template repo (Layer 2) | Layer 1 alone cannot ship workflows / Bicep / frontend / Docker / docs |
| Frontend | None | React 18 + Vite + tenant-session bootstrap | Multi-product SaaS needs a UI shell |

What is adopted directly:

- `.template.config/template.json` schema and symbol-rename pattern
  (`sourceName`, `derived` symbols, `replaces`, `fileRename`)
- Postman collection shipped inside the template
- Tag-based versioning of the template itself

---

## 5. Operational integration

| Surface | Integration |
|---|---|
| `/XYDataLabs-day-complete` prompt | Adds tag + branch step when closing commit closes a major architectural seam or precedes an irreversible architectural change |
| `.github/copilot-instructions.md` § 10 | Links to ADR-018 + this strategy doc |
| `ARCHITECTURE-EVOLUTION.md` | Cross-links to this doc near the phase roadmap |

## 6. References

- [ADR-018: Blueprint and snapshot strategy](../architecture/decisions/ADR-018-blueprint-and-snapshot-strategy.md)
- [ADR-017: Phase plan extensions for cloud-portable enterprise patterns](../architecture/decisions/ADR-017-phase-plan-portability-extensions.md)
- [ARCHITECTURE-EVOLUTION.md](../../ARCHITECTURE-EVOLUTION.md)
- External: Julio Casal `dotnet-backend-blueprint` v10
