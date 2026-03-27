# Validate ADR Markdown Workflow

**File:** `validate-adrs.yml`

Validates all Architecture Decision Record (ADR) files in `docs/architecture/decisions/` on every push or pull request that touches them.

---

## What it checks

| Step | Tool | Rules |
|------|------|-------|
| Lint ADR markdown | `markdownlint-cli2` + `.markdownlint.json` | All default rules except MD013 (line length) and MD036 (bold used as pseudo-heading) |
| Validate ADR frontmatter | `scripts/validate-adr-frontmatter.ps1` | Filename pattern, H1 heading matches number, `**Status:**` present, status base word is valid |

### Frontmatter rules enforced

Every `ADR-NNN-*.md` (excluding `ADR-000-template.md`) must satisfy:

1. **Filename**: `ADR-NNN-kebab-case.md` where NNN is a zero-padded three-digit number
2. **H1 heading**: First heading must be `# ADR-NNN: <Title>` with the number matching the filename
3. **Status line**: `**Status:**` must be present
4. **Status value**: The first word after `**Status:**` must be one of:
   `Accepted` | `Proposed` | `Draft` | `Deprecated` | `Superseded`

   Qualifiers after ` — ` or ` by ` are ignored: `Accepted — enrichers pending` and `Superseded by ADR-009` both pass.

---

## Triggers

| Event | Condition |
|-------|-----------|
| `push` | Branches `main`, `dev`, `staging` — when `docs/architecture/decisions/**`, `scripts/validate-adr-frontmatter.ps1`, or `.markdownlint.json` change |
| `pull_request` | Same paths |
| `workflow_dispatch` | Manual — run from Actions tab at any time |

> **Why script and config changes trigger it**: If the validation logic or lint rules change, re-running against all ADRs catches regressions in the validator itself, not just in the ADR content.

---

## Required files

| File | Purpose |
|------|---------|
| `.markdownlint.json` | Markdownlint rule configuration |
| `scripts/validate-adr-frontmatter.ps1` | Custom frontmatter schema checker |

---

## Running locally

```powershell
# Frontmatter validation
pwsh scripts/validate-adr-frontmatter.ps1

# Markdown lint (requires Node.js)
npx markdownlint-cli2 "docs/architecture/decisions/ADR-*.md"
```

---

## Repository variable — opt-in to enable

This workflow is **opt-in**. It only runs when `ADR_VALIDATION_ENABLED` is explicitly set to `true`. If the variable is absent the job is skipped — no noise on repositories where ADR validation has not been deliberately enabled.

| Value | Behaviour |
|-------|-----------|
| *(not set)* | Job is skipped — validation is **off by default** |
| `true` | Job runs normally |
| anything else (e.g. `false`) | Job is skipped |

**To enable:**

1. Go to **GitHub → Settings → Secrets and variables → Actions → Variables tab → Repository variables**
2. Click **New repository variable**
3. Name: `ADR_VALIDATION_ENABLED` — Value: `true` → click **Add variable**

**To disable again:**

Delete the variable or change its value to anything other than `true`.

> Keeping it opt-in means new forks and branches don't fail CI until the team deliberately turns it on.

---

## No Azure credentials required

This workflow has only `contents: read` permission and performs no deployments. It runs entirely on the GitHub Actions runner with no external service dependencies.
