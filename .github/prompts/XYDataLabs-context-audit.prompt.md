---
agent: agent
description: "Detects stale AI context — compares .sln project list, NuGet packages, test projects, CQRS patterns, workflows, ADRs, and instruction file applyTo globs against the live codebase; flags anything that has drifted in memory files or copilot-instructions.md"
---

# Context Audit — Detect Stale AI Context

Audit all AI context files against the actual codebase to detect drift. Do NOT ask for permission — run all checks and report findings.

## Checks to Perform

### 1. Project Table Accuracy
- Read `XYDataLabs.OrderProcessingSystem.sln` to get the actual project list.
- Compare against the project table in `.github/copilot-instructions.md` (§2).
- Compare against the project table in `/memories/repo/dotnet-conventions.md`.
- Flag: missing projects, removed projects still listed, wrong descriptions.

### 2. Package and Framework References
- Search all `.csproj` files for `PackageReference` entries.
- Check `/memories/repo/dotnet-conventions.md` for any package names mentioned (e.g. MediatR, AutoMapper).
- Flag: packages referenced in memory but not in any `.csproj`, or packages in `.csproj` not reflected in memory.

### 3. Test Project Structure
- List `tests/` directory contents.
- Compare against test project table in `.github/copilot-instructions.md`.
- Flag: new test projects not listed, removed projects still listed.

### 4. CQRS/Architecture Pattern Accuracy
- Search for `ICommand`, `IQuery`, `IDispatcher`, `IMediator`, `MediatR` in `.cs` files.
- Verify that memory and instructions correctly describe the CQRS pattern in use.
- Flag: any mention of MediatR if it's not actually used (or vice versa).

### 5. Directory Layout
- List root-level directories and compare against the directory tree in `.github/copilot-instructions.md` (§3).
- Flag: directories that exist but aren't listed, or listed directories that no longer exist.

### 6. Prompt Discoverability
- Search `.github/workflows/README-*.md`, `.github/prompts/README.md`, and `.github/copilot-instructions.md` for prompt references.
- Verify reusable prompts are mentioned consistently where operators are told how to run repository workflows.
- Flag: newly added prompts missing from quick tips, workflow READMEs, or prompt indexes.

### 7. Memory Freshness
- Read all files in `/memories/repo/` and relevant user memory files that define stable practices.
- For each file, check if its key facts are still accurate against the codebase and current repo structure.
- Flag: any factual statements that contradict current codebase state.

### 8. Secret Hygiene
- Search AI-facing files (`.github/copilot-instructions.md`, `.github/instructions/*.md`, `.github/prompts/*.md`, `/memories/repo/*.md`) for literal passwords, secrets, or connection strings with embedded credentials.
- Search tracked config samples (`Resources/Configuration/*.json`, `Resources/Docker/*.yml`, `Resources/Docker/*.yaml`) for literal credentials that should be replaced with safer local-dev patterns or environment-variable overrides.
- Flag: any secret-like values stored in memory, instruction files, reusable prompts, or tracked config samples.
- Treat placeholders such as `$sqlPwd`, `${DB_PASSWORD}`, or Key Vault references as acceptable.

### 9. ADR Directory
- List `docs/architecture/decisions/` contents.
- Check that `architect-patterns.md` ADR references are consistent with actual ADR files.

## Output Format

Present findings as a table:

| File | Issue | Current Value | Actual Value | Severity |
|------|-------|---------------|--------------|----------|

Severity levels:
- **HIGH** — Actively feeds wrong context into every session (e.g. wrong project name, removed package still referenced)
- **MEDIUM** — Missing information that could cause confusion (e.g. new project not listed)
- **LOW** — Minor drift, cosmetic (e.g. description wording slightly outdated)

After the table, list specific edits needed to fix each HIGH and MEDIUM issue.
