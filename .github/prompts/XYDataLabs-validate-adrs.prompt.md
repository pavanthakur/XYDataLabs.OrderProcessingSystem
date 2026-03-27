---
agent: agent
description: Validate all ADR markdown files locally before committing — runs frontmatter schema check and markdownlint
---

Run ADR validation locally against all files in `docs/architecture/decisions/`.

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

## Interpret results

**All PASS + exit 0** — safe to commit. All ADRs conform to the schema.

**Any FAIL** — the script lists every violation with the filename and exact rule broken. Fix before committing.

## CI workflow toggle

The `Validate ADR Markdown` CI workflow is **opt-in** — it only runs when `ADR_VALIDATION_ENABLED` is explicitly set to `true`.

**To enable CI validation:**
1. Go to **GitHub → Settings → Secrets and variables → Actions → Variables tab → Repository variables**
2. Create `ADR_VALIDATION_ENABLED` with value `true`

**To disable:**
Delete the variable or set it to any value other than `true`. The job is skipped and marked neutral — it does not block PRs or push checks.
