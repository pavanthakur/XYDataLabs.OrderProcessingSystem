# Publish Template Package Workflow

## Overview
Manual workflow that packs `XYDataLabs.SaaS.Templates`, validates the packaged `dotnet new` flow end to end, uploads the `.nupkg` as a workflow artifact, and optionally pushes the validated package to NuGet.org or GitHub Packages.

## Why this exists
- The template must be validated from the packaged `.nupkg`, not just from the source tree.
- A publish action should not bypass the smoke path that installs the package, generates a solution, and builds the generated output.
- Operators need a safe dry-run mode that produces the final package artifact without pushing it anywhere.

## Governance handoff
This workflow is the publication endpoint, not the first signal that a new NuGet template line is needed.

Automatic detection now lives in [README-VALIDATE-TEMPLATE-PACKAGE-GOVERNANCE.md](./README-VALIDATE-TEMPLATE-PACKAGE-GOVERNANCE.md):
- Pull requests that change `templates/xy-saas/` or `templates/XYDataLabs.SaaS.Templates/` must bump `PackageVersion`.
- Pushes to `dev`, `staging`, or `main` that touch the same Layer 1 template surface also run automatic packaged smoke validation.
- Those pull requests also run packaged smoke validation before merge.

That keeps template version drift from becoming a one-time manual habit.

## Trigger
Manual dispatch only.

### Run from GitHub UI
1. Open `Actions`.
2. Select `Publish Template Package`.
3. Choose the branch or tag to publish from.
4. Set `publish-package`:
   - `false` to pack, validate, and upload the `.nupkg` artifact only.
   - `true` to also push the validated package to the selected registry.
5. Select `package-source`:
   - `nuget.org`
   - `github-packages`

### Run from GitHub CLI
```bash
# Dry run: pack + smoke validate + upload artifact only
gh workflow run publish-template-package.yml \
  --ref dev \
  -f publish-package=false \
  -f package-source=nuget.org

# Publish validated package to NuGet.org
gh workflow run publish-template-package.yml \
  --ref dev \
  -f publish-package=true \
  -f package-source=nuget.org
```

## Workflow behavior

### Pack and validate
The first job always runs and performs the release-quality checks:
- `dotnet pack templates/XYDataLabs.SaaS.Templates/XYDataLabs.SaaS.Templates.csproj -c Release --nologo`
- `dotnet new uninstall XYDataLabs.SaaS.Templates` (best effort)
- `dotnet new install <packed-nupkg>`
- `dotnet new xy-saas ...`
- `dotnet build <generated-solution> --nologo`
- Uploads the final `.nupkg` as the `template-package` artifact

### Publish
The second job runs only when `publish-package=true`.

#### NuGet.org
Requires repository secret `NUGET_API_KEY`.

```powershell
dotnet nuget push <nupkg> \
  --api-key <NUGET_API_KEY> \
  --source https://api.nuget.org/v3/index.json \
  --skip-duplicate
```

#### GitHub Packages
Uses the built-in workflow `GITHUB_TOKEN` and writes to:

```text
https://nuget.pkg.github.com/<owner>/index.json
```

## Required secrets

### Always available
- `GITHUB_TOKEN` for artifact access and optional GitHub Packages publication

### Required only for NuGet.org publication
- `NUGET_API_KEY`

## Artifacts
- `template-package` — the packed `XYDataLabs.SaaS.Templates.<version>.nupkg`

## When to use it
- Formal template releases such as `1.0.0`, `1.1.0`, and later immutable package lines
- Dry-run validation before publishing to a public registry
- Repeatable regeneration of the final `.nupkg` from a tagged baseline

## How consumers install from NuGet.org

Install a specific version:

```powershell
dotnet new install XYDataLabs.SaaS.Templates::1.0.1
```

Check for template updates:

```powershell
dotnet new update --check-only
```

Remove the currently installed package:

```powershell
dotnet new uninstall XYDataLabs.SaaS.Templates
```

## Related documentation
- [Workflow index](./README.md)
- [Validate template package governance](./README-VALIDATE-TEMPLATE-PACKAGE-GOVERNANCE.md)
- [Branch + blueprint strategy](../../docs/internal/branch-and-blueprint-strategy.md)
- [ADR-018 blueprint and snapshot strategy](../../docs/architecture/decisions/ADR-018-blueprint-and-snapshot-strategy.md)