---
applyTo: "**/*CURRICULUM*,**/05-Self-Learning/**"
---
# Curriculum Conventions — XYDataLabs.OrderProcessingSystem

## Master Curriculum File
`Documentation/05-Self-Learning/Azure-Curriculum/1_MASTER_CURRICULUM.md`

## Current Progress (as of March 2026)
- Days 1-33: ✅ Complete
- Day 34: 🔶 Partial — SQL logging ✅, portal test pending
- Day 35: ❌ Not started — Managed Identity for SQL
- Day 36: 🔶 Partial — Azure.Identity pkg ✅, SQL passwordless not done
- Days 37+: ❌ Not started

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

## Related Commands Document
`Documentation/QUICK-COMMAND-REFERENCE.md` — all hands-on commands executed each day should be added here under the relevant section.

---

## 📍 Routing Guide — Where Does New Learning Go?

When completing a curriculum day or implementing something new, use this decision matrix:

| What you learned / did | Update this document |
|------------------------|---------------------|
| Completed a checklist item | `1_MASTER_CURRICULUM.md` — mark `[x]`, update Completed date |
| Ran a new CLI command (az, dotnet ef, git, sqlcmd) | `Documentation/QUICK-COMMAND-REFERENCE.md` — add to relevant section |
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
