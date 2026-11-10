---
agent: agent
description: "Detects stale AI context by comparing canonical guidance, routing/discovery indexes and the concise handoff with relevant code/configuration and evidence; short entry files are not duplicate project inventories"
---

# Context Audit — Detect Stale AI Context

Perform the task-relevant read-only audit against actual code/configuration and evidence. Start with `AGENTS.md` and `docs/AI-OPERATING-MODEL.md`; do not load every document for a narrow issue. No edits, personal-memory access, Git writes, database/provider calls or runtime/cloud operations are authorized by this audit prompt. Report unavailable sources explicitly.

## Checks to Perform

### 1. Project Table Accuracy
- Read `XYDataLabs.OrderProcessingSystem.sln` to get the actual project list.
- Compare with maintained project inventories at their owning architecture/developer docs, if relevant. Short `AGENTS.md` and Copilot entry files intentionally contain routes, not full tables.
- Compare any project claims in existing repository-relative `memories/repo/dotnet-conventions.md` only if that file exists; do not create it or use a personal memory store.
- Flag: missing projects, removed projects still listed, wrong descriptions.

### 2. Package and Framework References
- Search all `.csproj` files for `PackageReference` entries.
- Check applicable owning guidance and existing repository memory for package claims (e.g. MediatR, AutoMapper); unavailable memory is not proof of missing functionality.
- Flag: packages referenced in memory but not in any `.csproj`, or packages in `.csproj` not reflected in memory.

### 3. Test Project Structure
- List `tests/` directory contents.
- Compare relevant maintained test inventories, when present; use live test projects as implementation evidence, not missing entry-file tables as a defect.
- Flag: new test projects not listed, removed projects still listed.

### 4. CQRS/Architecture Pattern Accuracy
- Search for `ICommand`, `IQuery`, `IDispatcher`, `IMediator`, `MediatR` in `.cs` files.
- Verify that memory and instructions correctly describe the CQRS pattern in use.
- Flag: any mention of MediatR if it's not actually used (or vice versa).

### 5. Directory Layout
- Compare relevant directory references at their owning docs with actual paths; entry files should route there rather than reproduce the full tree.
- Flag: directories that exist but aren't listed, or listed directories that no longer exist.

### 6. Prompt Discoverability
- Check each prompt/agent in its owning `.github/prompts/README.md` index and skills in `.github/skills/README.md`; verify shared/Copilot entry links reach these owners.
- Verify reusable prompts are mentioned consistently where operators are told how to run repository workflows.
- Flag: newly added prompts missing from quick tips, workflow READMEs, or prompt indexes.

### 7. Memory Freshness
- Read the concise repository-relative `memories/repo/active-work.md` and only other existing repo records material to this audit. Do not read/write personal memory or require a special memory tool.
- For each file, check if its key facts are still accurate against the codebase and current repo structure.
- Flag: any factual statements that contradict current codebase state.
- Historical evidence must retain environment/scope and revision or UNKNOWN; missing local artifacts are unavailable, not PASS. Verify the relevant plan's pause/approval state before proposing follow-up work.

### 8. Secret Hygiene
- Search AI-facing files (`.github/copilot-instructions.md`, `.github/instructions/*.md`, `.github/prompts/*.md`, `/memories/repo/*.md`) for literal passwords, secrets, or connection strings with embedded credentials.
- Search tracked config samples (`Resources/Configuration/*.json`, `Resources/Docker/*.yml`, `Resources/Docker/*.yaml`) for literal credentials that should be replaced with safer local-dev patterns or environment-variable overrides.
- Flag: any secret-like values stored in memory, instruction files, reusable prompts, or tracked config samples.
- Treat placeholders such as `$sqlPwd`, `${DB_PASSWORD}`, or Key Vault references as acceptable.

### 9. ADR Directory
- List `docs/architecture/decisions/` contents.
- Check that `architect-patterns.md` ADR references are consistent with actual ADR files.

### 10. Architecture Status Surface Consistency
- Read the active-status surfaces:
	- `ARCHITECTURE-EVOLUTION.md`
	- `docs/guides/development/phase10-tool-prerequisites.md`
	- `docs/internal/phase10-implementation-checklist.md`
	- `docs/learning/curriculum/1_MASTER_CURRICULUM.md`
	- `docs/learning/curriculum/README.md`
	- `docs/internal/AZURE-PROGRESS-EVALUATION.md`
	- `docs/learning/implementation-notes/implementation-notes-days-29-38.md` or the active implementation-notes file
	- `docs/DEVELOPER-OPERATING-MODEL.md`
	- `.github/instructions/curriculum.instructions.md`
	- `.github/copilot-instructions.md`
- Compare the current phase complete/next-phase snapshots across those files.
- Flag: any mismatch in completed phase count, active phase, next phase, or freeze/closeout wording that would mislead humans or Copilot.
- Verify the relevant approved plan/checkpoint and evidence rather than hardcoding a historical next slice. A paused Phase 10 or planned Phase 11 task must not be treated as authorization to resume or as completed work.

## Output Format

Present findings as a table:

| File | Issue | Current Value | Actual Value | Severity |
|------|-------|---------------|--------------|----------|

Severity levels:
- **HIGH** — Actively feeds wrong context into every session (e.g. wrong project name, removed package still referenced)
- **MEDIUM** — Missing information that could cause confusion (e.g. new project not listed)
- **LOW** — Minor drift, cosmetic (e.g. description wording slightly outdated)

After the table, list specific edits needed to fix each HIGH and MEDIUM issue.
