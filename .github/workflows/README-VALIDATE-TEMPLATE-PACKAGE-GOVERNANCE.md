# Validate Template Package Governance Workflow

## Overview
Automatic governance workflow for the Layer 1 `dotnet new` template package. It answers the recurring question, "did this PR change the generated template enough that the NuGet package line must move?" and then proves the answer by packing and smoke-validating the package.

## Why this exists
- Template changes must not rely on memory or end-of-phase cleanup.
- Any change under `templates/xy-saas/` or `templates/XYDataLabs.SaaS.Templates/` affects what future projects generate.
- The repository needs an automatic rule that forces a package-version decision before those changes merge.

## Trigger
- Automatic on pushes and pull requests targeting `dev`, `staging`, or `main` when the Layer 1 template surface changes
- Manual dispatch for on-demand dry-run validation

## What it enforces

### 1. Version-bump guard
For pull requests, if any Layer 1 template payload file changes, the workflow compares `PackageVersion` in `templates/XYDataLabs.SaaS.Templates/XYDataLabs.SaaS.Templates.csproj` between the PR branch and the target branch.

If the version did not change, the workflow fails and blocks the merge.

This means the repository always knows the next intended NuGet template line whenever the generated template changes.

On direct pushes to `dev`, `staging`, or `main`, the workflow still runs the packaged smoke path automatically so template-impacting commits are visible immediately even before branch protection is enabled.

### 2. Packaged smoke validation
The workflow then runs the same release-quality path used for publication:
- `dotnet pack templates/XYDataLabs.SaaS.Templates/XYDataLabs.SaaS.Templates.csproj -c Release --nologo`
- `dotnet new install <packed-nupkg>`
- `dotnet new xy-saas ...`
- `dotnet build <generated-solution> --nologo`

## What this workflow does not do
- It does **not** publish to NuGet.org automatically.
- It does **not** create tags or GitHub releases.

Publication remains an intentional operator step through [README-PUBLISH-TEMPLATE-PACKAGE.md](./README-PUBLISH-TEMPLATE-PACKAGE.md) after the branch state is ready and a release tag has been chosen.

## Decision matrix

| Change type | New NuGet template version required? | New GitHub template repo version required? |
|---|---|---|
| `templates/xy-saas/**` generated backend skeleton changes | Yes | Usually no |
| `templates/XYDataLabs.SaaS.Templates/**` package metadata or packaged README changes | Yes | No |
| Blueprint-only assets such as workflows, Bicep, frontend, Docker, docs, or AI assets outside Layer 1 | No | Yes, when the Layer 2 template repo is refreshed |
| Runtime application code in this repository only | No | No |

## Operator flow after the guard passes
1. Merge the PR with the bumped `PackageVersion`.
2. Choose the release baseline and create the tag.
3. Run `publish-template-package.yml` against that tag.
4. Create the matching GitHub release.

## Strong enforcement note
The workflow now runs on both pull requests and direct pushes, but pull-request blocking still depends on branch protection if you want to make this non-bypassable for protected branches.

## Consumer usage from NuGet.org

Install a specific template line:

```powershell
dotnet new install XYDataLabs.SaaS.Templates::1.0.1
```

Check whether newer template lines are available locally:

```powershell
dotnet new update --check-only
```

Uninstall the currently installed line:

```powershell
dotnet new uninstall XYDataLabs.SaaS.Templates
```

Generate a new solution:

```powershell
dotnet new xy-saas `
  -n TradingAnalytics `
  --rootNamespace Contoso.TradingAnalytics `
  --companySlug contoso `
  --productSlug tradinganalytics
```