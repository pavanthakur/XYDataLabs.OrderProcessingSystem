# ADR-018: Blueprint Packaging and Snapshot Strategy

**Status:** Accepted

## Context

This repository is being used as a portfolio-grade reference implementation that will seed
multiple side-project SaaS products (Trading Analytics, AI WhatsApp Automation,
Azure Cost Optimization, AI Recruitment, plus the current Multi-Tenant Order Processing SaaS).
Two related questions surfaced as the Phase 8 closeout completed and Phase 8.5 work began:

1. **Snapshot strategy.** How do we preserve point-in-time baselines (Phase 7 multi-tenant
   foundation, Phase 8 frontend SPA, future Phase 11 microservices split, etc.) so a side
   project can be forked from the architectural seam most appropriate for it — without polluting
   the active development branch list and without risk of accidental tampering?

2. **Reusable template packaging.** After Phase 14 closeout (or earlier at clean architectural
   seams), how do we package this repository so a new SaaS product can be bootstrapped with the
   same Clean Architecture, multi-tenant primitives, OIDC-based Azure deployment, Docker matrix,
   automation workspace, and AI governance — with minimum manual effort?

Three external influences shaped the decision:

- **Julio Casal's `dotnet-backend-blueprint` v10** (`C:\Users\Pavan\Downloads\dotnet-backend-blueprint-v-10`)
  demonstrates that the canonical .NET-native skeleton mechanism is a `dotnet new` template
  package via `.template.config/template.json` (uses `sourceName`, `derived` symbols,
  `replaces`/`fileRename`).
- **User-provided guidance tips** advocated branch-based backups
  (e.g. `dev-backup-20260409-Multitenant-Upto-Phase7`), date-prefixed naming, immutable template
  versioning, and per-snapshot evidence linking.
- **Native Git/GitHub primitives** (annotated tags, GitHub template repositories, branch
  protection rules) cover most of the requirements without inventing a parallel filesystem
  store.

A blanket choice between branches and tags is unsatisfactory: tags are immutable but invisible
in the GitHub branch picker; branches are discoverable but mutable. Similarly, neither a
`dotnet new` template alone (cannot ship workflows, Bicep, frontend, Docker, docs) nor a
GitHub template repo alone (no symbol-driven .NET solution rename) covers the full skeleton.

## Decision

Adopt a **two-pointer snapshot mechanism (Path C)** and a **two-layer template packaging**.

### Snapshot mechanism — annotated tag + protected backup branch

For each snapshot point, create both:

- An **annotated git tag** following the format `v-YYYYMMDD-phase<N>-<slug>`
  (e.g. `v-20260409-phase7-multitenant`, `v-20260510-phase8-frontend-spa`).
- A **backup branch** following the format
  `dev-backup-YYYYMMDD-<Scope>-Upto-Phase<N>`
  (e.g. `dev-backup-20260409-Multitenant-Upto-Phase7`,
  `dev-backup-20260510-FrontendSPA-Upto-Phase8`).

Both pointers reference the **same anchor commit**. The tag is the canonical immutable record;
the branch is the discoverable companion that surfaces in the GitHub branch picker and
IDE branch dropdowns.

A GitHub branch protection rule applied to the pattern `dev-backup-**` enforces:

- No direct pushes
- No deletions
- No force-pushes
- No merges expected (snapshots are read-only references)

This makes the backup branch effectively immutable while retaining its discoverability advantage.

### Snapshot cadence — major architectural seams only

Tags + backup branches are cut at:

- **Major architectural seams**: Phase 7 (multi-tenant baseline), Phase 8 (frontend SPA),
  Phase 11 (microservices split), Phase 13 (full observability), Phase 14 (final).
- **Before any irreversible architectural change**: e.g. before the microservices split,
  before a primary key strategy change, before a multi-region rollout.

Snapshots are **not** cut at minor phase closeouts (8.5, 8.7, 9.5), at every Day Complete run,
or on every CI build. Tag inflation defeats the purpose of a curated baseline set.

### Tag message standard — evidence linking, not filesystem mirror

Each annotated tag carries a structured message:

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

This replaces the user-suggested `/output/evidence/summary.txt` filesystem mirror — Git already
durably stores the snapshot; the tag message links to evidence already produced by the
existing `automation/reports/` pipeline.

### Template packaging — two layers, both adopted

**Layer 1 — `dotnet new` template via NuGet** (Julio Casal's pattern):

- Package id: `XYDataLabs.SaaS.Templates`
- Ships: `src/` projects (API, Application, Domain, Infrastructure, SharedKernel, provider-agnostic
  PaymentGateway scaffold), test projects, EF Core scaffolding, multi-tenant primitives, hand-rolled
  CQRS skeleton, `Result<T>`, NetArchTest layer rules.
- Uses `.template.config/template.json` with `sourceName` for solution rename, `derived`
  symbols for project name casing, `generated` symbols for `UserSecretsId`.
- Versioning: standard NuGet semver (`1.0.0`, `1.1.0`); each version is immutable.

**Layer 2 — GitHub template repository** (`xydatalabs-saas-blueprint`):

- Marked as a GitHub template repository (Settings → Template repository ✓).
- Ships: `.github/workflows/`, `infra/` Bicep modules, `bicep/` resource-group variant,
  `Resources/Docker/` matrix, `frontend/` workspace, `automation/` workspace shell, `docs/`
  governance scaffolding, ADR template, `.github/instructions/`, `.github/prompts/`,
  `.github/agents/`, `.github/skills/`, AI customization assets.
- Versioning: annotated tags `blueprint-v1.0.0`, `blueprint-v1.1.0` on the template repo.
- Side-project bootstrap: "Use this template" → new repo →
  `dotnet new install XYDataLabs.SaaS.Templates::1.x.x` →
  `dotnet new xy-saas -n <ProductName>` →
  `scripts/initialize-blueprint.ps1 -ResourcePrefix <prefix> -InitialTenants <list>`.

**Extraction trigger:** Layer 2 template repo is extracted **after Phase 14 closeout** when
the architecture is stable. Pre-Phase-14 side projects fork from a snapshot tag instead of
waiting for the template to mature.

### Side-project location — separate repos

Side projects live in **separate GitHub repositories**, optionally under a dedicated
`pavanthakur-saas/` GitHub organization for clean portfolio branding. They do **not** live as
long-lived branches in this repository.

Each side project pins both `BLUEPRINT_VERSION` (Layer 2 tag) and `DOTNET_TEMPLATE_VERSION`
(Layer 1 NuGet version) in its own `README.md` for reproducibility.

### Operational integration

- The `/XYDataLabs-day-complete` prompt instructs the agent to cut a tag + branch (per the
  formats above) when the closing commit closes a major architectural seam or precedes an
  irreversible architectural change.
- `docs/internal/branch-and-blueprint-strategy.md` is the operational runbook for the snapshot
  format, cadence triggers, and side-project bootstrap.

## Rationale

| Decision | Why this over the alternatives |
|---|---|
| Tag + branch (Path C) instead of tag-only or branch-only | Path C combines the immutability and Git-native semantics of tags with the discoverability of branches. Branch protection on `dev-backup-**` removes the only practical risk of branch-based backups (force-push or accidental commit). Cost is minimal — both pointers reference one commit. |
| Annotated tags with structured messages instead of `/output/snapshots` filesystem mirror | Git is already a durable point-in-time store; a parallel filesystem mirror duplicates state without adding traceability. Evidence already lives in `automation/reports/`; the tag message links to it. |
| Major-seam-only cadence instead of every-phase or daily-CI cadence | Minor closeouts (8.5, 8.7, 9.5) are not architectural baselines anyone would fork from. Tag inflation hides the meaningful baselines. |
| Two-layer template instead of `dotnet new` only or GitHub template only | `dotnet new` is the correct mechanism for the .NET solution skeleton (solution rename, project rename, namespace replace) but cannot ship workflows, Bicep, frontend, Docker, or docs. GitHub template repository ships everything `dotnet new` cannot. Layered together they cover the full bootstrap. |
| `dotnet new` NuGet template package instead of NuGet library `Company.Architecture.Template` | NuGet libraries distribute compiled binaries; NuGet `dotnet new` template packages distribute parameterized source skeletons. The latter is the right tool. |
| GitHub template repository instead of long-lived `template/*` branch | GitHub's "Use this template" button is purpose-built for skeleton bootstrap. A long-lived branch in this repo would mix template lifecycle with product lifecycle and create cross-pollination risk. |
| Side projects in separate repos (optionally an org) instead of monorepo branches | Each product needs its own CI surface, issue tracker, deployment cadence, and visibility. Monorepo branches would entangle releases. |
| Extract Layer 2 at Phase 14 instead of earlier | Earlier extraction means re-extracting on every architectural evolution. Phase 14 = stable. Pre-Phase-14 side projects fork from snapshot tags directly — the template is not a blocker. |

## Consequences

**Positive**

- Every side project can be bootstrapped from either a snapshot tag (pre-Phase-14) or the
  full two-layer template (post-Phase-14) with traceable provenance.
- Backup branches remain visible in the branch picker without losing immutability guarantees
  (via branch protection rule).
- Tag messages double as architectural milestone documentation, surfaced in `git show <tag>`
  and on the GitHub Releases page.
- Aligns with `.NET` ecosystem norms (Julio Casal blueprint pattern) for skeleton
  distribution.

**Negative / accepted trade-offs**

- Maintaining two pointers (tag + branch) at each snapshot is twice the bookkeeping. Mitigated
  by automating the action via `/XYDataLabs-day-complete`.
- Branch protection rule must be configured manually in GitHub Settings the first time the
  pattern `dev-backup-**` is used. Captured in the operational runbook.
- Layer 1 NuGet template requires a separate package publish pipeline (out of scope until
  Phase 14 closeout).

**Operational requirements**

- A new branch protection rule on `dev-backup-**` must be added in GitHub Settings → Branches
  (one-time, instructions in `docs/internal/branch-and-blueprint-strategy.md`).
- Day Complete prompt (`/XYDataLabs-day-complete`) must include the tag + branch step at
  major architectural seams.

## Related

- ADR-014: Azure service coverage rationale
- ADR-015: Deployment readiness probes
- ADR-016: Client-rendered React SPA
- ADR-017: Phase plan extensions for cloud-portable enterprise patterns
- `docs/internal/branch-and-blueprint-strategy.md` — operational runbook
- `ARCHITECTURE-EVOLUTION.md` — phase roadmap
- External: Julio Casal `dotnet-backend-blueprint` v10 (skeleton template pattern)
