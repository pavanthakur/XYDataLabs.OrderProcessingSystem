---
agent: agent
description: "Before committing ADR or script changes: (1) frontmatter schema — filename, H1 title, **Status:** word; (2) markdownlint format; (3) VS solution sync — all files in tracked dirs (ADRs, workflows, scripts, Azure-Deployment) registered in .sln"
---

Run the three local validation checks before committing any ADR, script, workflow, or Azure-Deployment file.

| Step | What it checks |
|------|----------------|
| 1 | ADR frontmatter — filename pattern, H1 title, `**Status:**` word |
| 2 | Markdownlint — ADR markdown formatting rules |
| 3 | VS solution sync — every tracked file registered in `.sln` |

## Step 1 — Frontmatter schema check

Run in terminal:
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
pwsh scripts/validate-adr-frontmatter.ps1
```

This checks every `ADR-NNN-*.md` (excluding the template) for:
- Filename matches `ADR-NNN-kebab-case.md`
- First heading is `# ADR-NNN: Title` with number matching filename
- `**Status:**` line is present
- Status base word is one of: `Accepted`, `Proposed`, `Draft`, `Deprecated`, `Superseded`

## Step 2 — Markdownlint format check

If `markdownlint-cli2` has not been installed yet, run this once first:
```powershell
if (-not (Test-Path "$env:APPDATA\npm")) { mkdir "$env:APPDATA\npm" }
npm install -g markdownlint-cli2
```

Then run the check:
```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
npx markdownlint-cli2 "docs/architecture/decisions/ADR-*.md"
```

> If Node.js is not installed at all, skip this step — markdownlint runs automatically in CI on every push.

## Step 3 — VS solution sync check

Ensures every file in the four tracked directories is registered in the VS solution file.
Run only if you added or renamed files in `docs/architecture/decisions/`, `.github/workflows/`, `scripts/`, or `Resources/Azure-Deployment/`.

```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
pwsh scripts/sync-check-solution.ps1
```

The script ignores generated outputs (`.log`, `.tmp`, `.bak`). Any gap is printed with a fix hint.

## Interpret results

**All PASS + exit 0 on all three steps** — safe to commit.

**Any FAIL** — the script prints every violation with the filename and exact rule broken. Fix before committing.

## CI workflow toggle

The `Validate ADR Markdown` CI workflow is **opt-in** — it only runs when `ADR_VALIDATION_ENABLED` is explicitly set to `true`.

**To enable CI validation:**
1. Go to **GitHub → Settings → Secrets and variables → Actions → Variables tab → Repository variables**
2. Create `ADR_VALIDATION_ENABLED` with value `true`

**To disable:**
Delete the variable or set it to any value other than `true`. The job is skipped and marked neutral — it does not block PRs or push checks.
