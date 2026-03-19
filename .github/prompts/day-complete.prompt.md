---
mode: agent
description: Run after completing a curriculum day. Asks what was done and automatically routes updates to the correct documents.
---

# Day Completion Routing

The user has just completed or partially completed a curriculum day.

Ask the user: "What did you complete today? Describe what you built, ran, or decided."

Then, based on their answer, apply the following routing rules automatically — do NOT ask for permission for each one, just do them all:

## Routing Rules

1. **Always: Mark curriculum checkboxes**
   - Open `Documentation/05-Self-Learning/Azure-Curriculum/1_MASTER_CURRICULUM.md`
   - Mark completed items `[x]`, update the `**Completed:**` date line

2. **If any CLI commands were run** (az, dotnet ef, git, sqlcmd, docker, pwsh):
   - Add them to the matching section in `Documentation/QUICK-COMMAND-REFERENCE.md`
   - Create a new section if the topic doesn't exist yet

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

## After Routing
- Summarise what was updated and where
- Suggest a commit message in the format: `Day <N>: <what was done>`
- Ask: "Ready to commit?"
