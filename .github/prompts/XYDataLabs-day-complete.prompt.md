---
agent: agent
description: "After a curriculum day or phase-freeze closeout: asks what you completed, then auto-routes — updates curriculum, roadmap/status surfaces, reference docs, memory, and implementation evidence"
---

# Day Completion Routing

The user has just completed or partially completed a curriculum day, or is closing out / freezing an architecture phase.

Ask the user: "What did you complete today? Describe what you built, ran, verified, or froze."

Then, based on their answer, apply the following routing rules automatically — do NOT ask for permission for each one, just do them all:

## Routing Rules

1. **Always: Mark curriculum checkboxes**
   - Open `docs/learning/curriculum/1_MASTER_CURRICULUM.md`
   - Mark completed items `[x]`, update the `**Completed:**` date line

2. **If any CLI commands were run** (az, dotnet ef, git, sqlcmd, docker, pwsh):
   - Add them to the matching section in `docs/reference/quick-command-reference.md`
   - Also add them to the appropriate canonical topic file under `docs/reference/`:

     | Topic | File |
     |-------|------|
   | Git, validation, daily workflow | `docs/reference/git-workflow.md` |
   | Azure CLI, Bicep, infra, OIDC | `docs/reference/azure-infra.md` |
   | Azure SQL, EF Core, sqlcmd, firewall | `docs/reference/azure-sql-ef.md` |
   | Local dev, dotnet run, Docker | `docs/reference/local-dev.md` |

   - Create a new section in both files if the topic doesn't exist yet

3. **If a technology/tool was chosen over an alternative:**
   - Create a new ADR in `docs/architecture/decisions/ADR-NNN-title.md`
   - Use ADR-000-template.md format: Status / Context / Decision / Consequences
   - Next ADR number = highest existing number + 1

4. **If a reusable pattern was learned (applies to future projects):**
   - Add a bullet to the relevant section in `/memories/architect-patterns.md`

5. **If a new Azure resource, FQDN, or credential was created:**
   - Update `/memories/repo/azure-resources.md`

6. **If a new .NET class, project, or convention was established:**
   - Update `/memories/repo/dotnet-conventions.md`

7. **If a workflow/deployment gotcha was discovered:**
   - Add to `/memories/repo/workflow-split.md`

8. **If a full week is now complete** (all days in the week have ✅ Completed dates):
   - Update the week heading in `1_MASTER_CURRICULUM.md` to add `— Complete` suffix:
     `### ✅ Weeks N-N: <Week Name> (Days X-Y) — Complete`
   - Update the **COMPLETED SO FAR** bullet at the top of the master file if it exists

9. **If the day's work closes or materially advances an architecture phase:**
    - Update `ARCHITECTURE-EVOLUTION.md` so the strategic roadmap matches repo truth
    - Sync all architecture status and navigation surfaces that summarize the active phase or current milestone, including:
       - `docs/learning/curriculum/1_MASTER_CURRICULUM.md`
       - `docs/learning/curriculum/README.md`
       - `docs/internal/AZURE-PROGRESS-EVALUATION.md`
       - `docs/learning/implementation-notes/implementation-notes-days-29-38.md` or the active implementation-notes file
       - `.github/instructions/curriculum.instructions.md`
       - `docs/DEVELOPER-OPERATING-MODEL.md` when the active phase/current focus changed
       - `.github/copilot-instructions.md` if it contains a current phase snapshot
    - Update all of the following in `ARCHITECTURE-EVOLUTION.md` when applicable:
       - top-level `Current Status`
       - roadmap table status column
       - the affected phase heading/status block
       - any repeated summary/status snapshot near the end of the file
    - Treat architecture-status drift across these files as a blocking inconsistency to fix before finishing
    - If the work is a phase freeze/closeout, do not stop at the checklist change; confirm the phase now reads consistently as complete/next across all status surfaces in the same session

10. **Always: Record unique implementation detail for the completed day**
   - Open `docs/learning/implementation-notes/implementation-notes-days-29-38.md`
   - Add a `## Day N: <Title>` section if the day had notable implementation nuance
   - Include:
     - What was built, configured, or verified — step by step
     - Important commands run with any notable output
     - Key gotchas or discoveries (especially environment/config differences)
     - What this enables for the next day
   - Use numbered sub-headings (e.g. `**1. Topic**`) when the day had multiple distinct activities
   - Include code blocks for any actual code added or console output confirmed
   - Skip this step if the day was purely checklist tasks with no unique detail worth preserving

11. **If any multi-environment file was modified** (Bicep modules, parameter files, sharedsettings, workflows):
    - Verify the change is applied to ALL three environments — dev + staging + prod:
      - `infra/parameters/dev.json` → `staging.json` → `prod.json`
      - `sharedsettings.dev.json` → `sharedsettings.stg.json` → `sharedsettings.prod.json`
    - Staging Azure resource names use suffix `stg` (not `staging`) — e.g. `rg-orderprocessing-stg`
    - If a Bicep module adds new params, add placeholder entries in all 3 parameter files
    - Flag any environment that was missed and apply the missing change before committing

## After Routing
- If the work is a phase freeze/closeout or changed roadmap/status surfaces, run `/XYDataLabs-completion-check` (or perform its equivalent quality gate) before suggesting a commit; fix any non-deferred gaps first
- If the work is a phase freeze/closeout or changed roadmap/status surfaces, run `/XYDataLabs-context-audit` (or perform its equivalent status-surface audit) before suggesting a commit; fix any HIGH or MEDIUM drift first
- For a phase freeze/closeout, do not ask "Ready to commit?" until both mandatory checks above are complete in the same session
- Summarise what was updated and where
- Suggest a commit message in the format: `Day <N>: <what was done>`
- Ask: "Ready to commit?"
