---
applyTo: "**/*CURRICULUM*,**/docs/learning/curriculum/**"
---
# Curriculum Conventions — XYDataLabs.OrderProcessingSystem

## Master Curriculum File
`docs/learning/curriculum/1_MASTER_CURRICULUM.md`

## Current Progress (as of April 2026)
- Days 1-43: ✅ Complete (implementation detail in `docs/learning/implementation-notes/implementation-notes-days-29-38.md`; verification freeze completed 2026-04-10 across local, Docker, and Azure)
- Architecture Phases 1-7: ✅ Complete
- Days 44+: 📅 Next (Phase 8 event foundation + payment recovery first; Phase 9 module extraction with Payments included second; Phase 10 Bicep-only Azure transport + DLQ operations third)

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
`docs/reference/quick-command-reference.md` — canonical index and routing hub.
All hands-on commands go to the appropriate canonical topic file in `docs/reference/`:
- `docs/reference/git-workflow.md` — git, validation, daily workflow
- `docs/reference/azure-infra.md` — Azure CLI, Bicep, OIDC, GitHub workflows
- `docs/reference/azure-sql-ef.md` — Azure SQL, EF Core, sqlcmd, firewall
- `docs/reference/local-dev.md` — local dev, dotnet run, Docker, SQL logging

## Daily Progress Convention
Completed weeks: mark all items `[x]` in the master, update the `**Completed:**` dates, and summarise any unique implementation detail in `docs/learning/implementation-notes/implementation-notes-days-29-38.md`.
Master file keeps the full checklist for all weeks; completed weeks have a `— Complete` or `— [Implementation Notes](../../../docs/learning/implementation-notes/implementation-notes-days-29-38.md)` suffix on the heading line.

---

## 📍 Routing Guide — Where Does New Learning Go?

When completing a curriculum day or implementing something new, use this decision matrix:

| What you learned / did | Update this document |
|------------------------|---------------------|
| Completed a checklist item | `1_MASTER_CURRICULUM.md` — mark `[x]`, update Completed date |
| Ran a new CLI command (az, dotnet ef, git, sqlcmd) | `docs/reference/<topic>.md` — git-workflow / azure-infra / azure-sql-ef / local-dev |
| Made a technology choice (why X over Y) | New `docs/architecture/decisions/ADR-NNN-title.md` |
| Discovered a reusable pattern for any future project | `/memories/architect-patterns.md` — add to relevant section |
| New Azure resource name / FQDN / credentials detail | `/memories/repo/azure-resources.md` |
| New .NET class / project / connection string convention | `/memories/repo/dotnet-conventions.md` |
| Workflow or deployment gotcha / fix | `/memories/repo/workflow-split.md` |
| New Copilot instruction rule (file-pattern specific) | `.github/instructions/<topic>.instructions.md` |
| A week/phase boundary is crossed (new phase complete or new phase starts) | Update ALL four navigation status locations (see rule below) |

## README / Navigation Sync Rule

**Standard practice:** Whenever a phase boundary is crossed or a significant batch of days completes,
update ALL four status locations together — never update one without checking the others:

| File | What to update |
|------|----------------|
| `1_MASTER_CURRICULUM.md` | `WHAT'S NEXT?` block — completed items, next 3 priorities |
| `docs/learning/curriculum/README.md` | `Current Learning Status` section + `Last Updated` / `Current Focus` footer |
| `docs/internal/AZURE-PROGRESS-EVALUATION.md` | Top-of-file progress block (the `🟢 Current State` section) |
| `curriculum.instructions.md` (this file) | `Current Progress` block at the top |

**Trigger:** Any of the following actions should trigger a sync of all four:
- Marking the final `[x]` on a day that completes a Phase
- Updating `**Completed:**` for Day 38, Day 43, Day 56, or any other phase-boundary day
- Starting a new phase (update "next" to show the active phase)

**Rule:** If you update one, update all four in the same commit/session. Stale nav files mislead
both humans reading the docs and AI reading context into the session.

### Quick decision questions
1. **Will a future developer need to understand WHY this was chosen?** → ADR
2. **Is it a command someone will need to run again?** → QUICK-COMMAND-REFERENCE.md
3. **Is it a pattern reusable in a DIFFERENT project?** → architect-patterns.md
4. **Is it a fact specific to THIS repo (resource names, class names)?** → /memories/repo/
5. **Does it change how Copilot should behave on a file type?** → .instructions.md file
