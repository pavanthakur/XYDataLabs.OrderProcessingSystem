---
agent: agent
description: "After a curriculum day: asks what you completed, then auto-routes — marks 1_MASTER_CURRICULUM.md checkboxes, logs CLI commands to QUICK-COMMAND-REFERENCE.md and the matching commands/ topic file, updates DAILY_PROGRESS_TRACKER.md, and appends to ACHIEVEMENT_LOG.md"
---

# Day Completion Routing

The user has just completed or partially completed a curriculum day.

Ask the user: "What did you complete today? Describe what you built, ran, or decided."

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

9. **Always: Record unique implementation detail for the completed day**
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

10. **If any multi-environment file was modified** (Bicep modules, parameter files, sharedsettings, workflows):
    - Verify the change is applied to ALL three environments — dev + staging + prod:
      - `infra/parameters/dev.json` → `staging.json` → `prod.json`
      - `sharedsettings.dev.json` → `sharedsettings.stg.json` → `sharedsettings.prod.json`
    - Staging Azure resource names use suffix `stg` (not `staging`) — e.g. `rg-orderprocessing-stg`
    - If a Bicep module adds new params, add placeholder entries in all 3 parameter files
    - Flag any environment that was missed and apply the missing change before committing

## After Routing
- Summarise what was updated and where
- Suggest a commit message in the format: `Day <N>: <what was done>`
- Ask: "Ready to commit?"
