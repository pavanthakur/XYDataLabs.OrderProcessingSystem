---
applyTo: "**/*CURRICULUM*,**/05-Self-Learning/**"
---
# Curriculum Conventions — XYDataLabs.OrderProcessingSystem

## Master Curriculum File
`Documentation/05-Self-Learning/Azure-Curriculum/1_MASTER_CURRICULUM.md`

## Current Progress (as of March 2026)
- Days 1-34: ✅ Complete (detail in `02-Daily-Progress/week-01-02`, `week-03-04`, `week-05-08`)
- Days 35-38: ✅ Complete 2026-03-20 — Managed Identity for SQL, DefaultAzureCredential, passwordless conn string, EnableRetryOnFailure
- Days 39+: ❌ Not started

## Checkbox Marking Convention
- `[x]` = done
- `[ ]` = pending
- Completed day line: `**Completed:** ✅` with date if known
- Partial day note: append `(what done ✅, what pending ❌)` to Time/Completed line

## Day Completion Rules
When marking a day complete:
1. Change all `[ ]` to `[x]`
2. Update the `**Completed:**` line from `___/___/___` to `✅` or actual date
3. Update the `WHAT'S NEXT?` section summary at the top if milestone reached

## Commit Convention for Curriculum Changes
`Day <N>: <Short description of what was done>`
Example: `Day 34: Enable EF Core SQL logging in Development environment`

## Related Commands Documents
`Documentation/QUICK-COMMAND-REFERENCE.md` — index only (links to topic files below).
All hands-on commands go to the appropriate topic file in `Documentation/commands/`:
- `commands/git-workflow.md` — git, validation, daily workflow
- `commands/azure-infra.md` — Azure CLI, Bicep, OIDC, GitHub workflows
- `commands/azure-sql-ef.md` — Azure SQL, EF Core, sqlcmd, firewall
- `commands/local-dev.md` — local dev, dotnet run, Docker, SQL logging

## Daily Progress Convention
Completed weeks → `Documentation/05-Self-Learning/Azure-Curriculum/02-Daily-Progress/week-NN-name.md`
Master file keeps: current week + next 2 weeks + overview sections only.
Completed weeks are replaced with a single summary line + Daily Progress link.

---

## 📍 Routing Guide — Where Does New Learning Go?

When completing a curriculum day or implementing something new, use this decision matrix:

| What you learned / did | Update this document |
|------------------------|---------------------|
| Completed a checklist item | `1_MASTER_CURRICULUM.md` — mark `[x]`, update Completed date |
| Ran a new CLI command (az, dotnet ef, git, sqlcmd) | `Documentation/commands/<topic>.md` — git-workflow / azure-infra / azure-sql-ef / local-dev |
| Made a technology choice (why X over Y) | New `docs/architecture/decisions/ADR-NNN-title.md` |
| Discovered a reusable pattern for any future project | `/memories/architect-patterns.md` — add to relevant section |
| New Azure resource name / FQDN / credentials detail | `/memories/repo/azure-resources.md` |
| New .NET class / project / connection string convention | `/memories/repo/dotnet-conventions.md` |
| Workflow or deployment gotcha / fix | `/memories/repo/workflow-split.md` |
| New Copilot instruction rule (file-pattern specific) | `.github/instructions/<topic>.instructions.md` |

### Quick decision questions
1. **Will a future developer need to understand WHY this was chosen?** → ADR
2. **Is it a command someone will need to run again?** → QUICK-COMMAND-REFERENCE.md
3. **Is it a pattern reusable in a DIFFERENT project?** → architect-patterns.md
4. **Is it a fact specific to THIS repo (resource names, class names)?** → /memories/repo/
5. **Does it change how Copilot should behave on a file type?** → .instructions.md file
