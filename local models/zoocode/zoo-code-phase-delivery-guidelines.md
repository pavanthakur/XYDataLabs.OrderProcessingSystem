# Zoo Code Phase Delivery Guidelines

Purpose: give every developer a repeatable way to use Zoo Code, Repomix, local models, and phase prompt files without turning architecture work into uncontrolled code generation.

Audience: new joiners and junior developers working on this repository under senior architecture review.

## Core Principle

Zoo Code is useful when it is given a small role, a clear context package, and a validation gate. Do not use one model/profile to think, design, edit, run commands, and approve its own work.

The standard flow is:

```text
Repomix context -> architect prompt -> review gate -> developer prompt -> validation -> next slice
```

Architecture decides the direction. Development implements one accepted slice. Validation decides whether the slice is allowed to stand.

## Repository Root

Run all phase commands from the repository root:

```powershell
cd Q:\GIT\TestAppXY_OrderProcessingSystem
```

This is the folder that contains:

```text
XYDataLabs.OrderProcessingSystem.sln
ARCHITECTURE.md
docs/
.github/
zoocode/
```

## Step 1 - Refresh Repomix Context

Before architecture planning, regenerate the repository map:

```powershell
npx repomix
```

Expected output:

```text
repomix-output.xml
```

Use `repomix-output.xml` for architecture and review work. Do not attach it to every implementation prompt by default.

Use Repomix for:

- phase architecture intake
- module boundary analysis
- risk discovery
- final architecture review
- broad cross-repository questions

Avoid Repomix for:

- small file edits
- single test repairs
- markdown table updates
- focused DTO/interface additions when the accepted plan already names the files

## Step 2 - Create Phase Prompt Files

Every major phase should have a Zoo Code prompt pack under:

```text
zoocode/phase N/
```

For Phase 9, the folder is:

```text
zoocode/phase 9/
```

Use this naming pattern:

```text
phaseN_architect1.0.md     initial architecture intake
phaseN_architect1.1.md     architecture correction and review gate
phaseN_architect2.0.md     implementation blueprint
phaseN_development1.0.md   first accepted development slice
phaseN_development1.1.md   second development slice
phaseN_development2.0.md   tests or guardrails slice
phaseN_development9.0.md   integration/regression slice
phaseN_architect9.0.md     remaining roadmap review
phaseN_architect99.0.md    final architecture acceptance
phaseN_development99.0.md  closeout and context sync
```

Do not skip the architect review gate. A developer model must not invent architecture while editing.

## Step 2.1 - Standard Phase Closure

Every phase and sub-phase must close using the same end-to-end gates and runbook structure:

1. Build cleanly with the phase-appropriate build command.
2. Run architecture or contract tests.
3. Run gateway or API contract tests.
4. Run integration tests.
5. Run Playwright or equivalent end-to-end automation.
6. Capture the testcase matrix and pass/fail summary in the transcript log.
7. Log warnings separately from blocking failures.
8. Clean up orphan containers and other disposable runtime resources.
9. Close the phase only when the full verification chain is green.

Each completed phase should also have a short closeout document in the phase folder that records:

- what was verified
- key automation files
- restart commands
- log file locations
- known non-blocking warnings
- final sign-off status

Use the shared standard in `local models/zoocode/phase-closure-standard.md` as the canonical closeout policy and `local models/zoocode/phase-closure-template.md` as the canonical fill-in template for each phase folder.

## Step 3 - Zoo Code Provider Profiles

Create separate Zoo Code provider profiles. Do not use the same profile for every task.

### Architect Profile

Use for architecture files:

```text
phaseN_architect*.md
```

Recommended settings:

```text
Configuration Profile: phaseN-architect
API Provider: Ollama
Base URL: http://localhost:11434
Model: qwen2.5-coder:7b
Context Window Size: 8192
Mode: Ask / Chat
Auto-Approve: Off
```

Use `deepseek-r1-14b-32k:latest` only as an architecture escalation model when Qwen output is insufficient. Start DeepSeek at 8192 context and increase only deliberately; do not use 32768 or 65536 as defaults on the Acer Predator Helios 300 profile.

Attach:

```text
repomix-output.xml
ARCHITECTURE.md
relevant ADRs
phase handoff prompts
active-work summary, if needed
```

Architect output must be read-only. It may produce decisions, risks, ADR outlines, and implementation slices. It must not edit files.

### Developer Profile

Use for implementation files:

```text
phaseN_development*.md
```

Recommended settings:

```text
Configuration Profile: phaseN-developer
API Provider: Ollama
Base URL: http://localhost:11434
Model: qwen-fast or qwen2.5-coder:7b
Context Window Size: 4096 or 8192
Mode: Edit
Auto-Approve: Off
```

Attach only focused context:

```text
accepted architect output
the current development prompt
specific files allowed to change
relevant instruction file
```

Do not attach `repomix-output.xml` by default for development. Use it only if the developer model is missing important context.

### Review Profile

Use after architecture output and after implementation output.

Recommended settings:

```text
Configuration Profile: phaseN-review
API Provider: Ollama
Base URL: http://localhost:11434
Model: qwen2.5-coder:7b
Context Window Size: 8192
Mode: Ask / Chat
Auto-Approve: Off
```

Escalate review to `deepseek-r1-14b-32k:latest` only when the review requires deeper architecture reasoning than Qwen provides.

Review against repository rules:

```text
Clean Architecture boundaries remain intact
No MediatR package is introduced
Tenant.PaymentProviderCode remains the only payment-provider routing authority
TenantRegistryDbContext remains the tenant resolution source
ADR-020 webhook inbox/idempotency remains intact
YARP routes host boundaries, not class-library modules
No RabbitMQ, Redis, or MassTransit unless explicitly approved by ADR
Validation command was run and result is known
```

### Safe Agent Profile

Use only for mechanical work after a senior reviewer has already decided what must change.

Recommended settings:

```text
Configuration Profile: phaseN-safe-agent
API Provider: Ollama
Base URL: http://localhost:11434
Model: qwen-fast
Context Window Size: 4096
Mode: Edit or Agent
Auto-Approve: Off or limited reads only
```

Good safe-agent tasks:

- rename one symbol exactly as requested
- update one markdown table
- add one test method from an accepted plan
- apply an exact patch

Bad safe-agent tasks:

- design module boundaries
- choose infrastructure technology
- extract a whole service
- change tenant/payment/webhook behavior
- run deployment scripts

## Step 4 - Mode Selection

Use Zoo Code modes deliberately:

```text
Ask / Chat  -> architect prompts and reviews
Edit        -> one accepted development slice
Agent       -> tiny mechanical tasks only
```

Never use Agent mode for architecture decisions.

## Step 5 - Skills

Create small Zoo Code skills for repeatable checks. Keep them narrow.

Recommended skills:

```text
phase-architecture-review
Review the phase plan against ADRs, Clean Architecture, tenant routing, gateway rules, and validation gates.
```

```text
phase-development-slice
Implement one accepted development slice only. Do not invent architecture or widen scope.
```

```text
phase-safety-check
Check whether the output changed forbidden files, added unsupported packages, skipped validation, or violated architecture constraints.
```

```text
repomix-context-reader
Use repomix-output.xml to summarize relevant repository context for architecture planning only.
```

Do not create a skill named `implement phase end to end`. That invites broad edits.

## Step 6 - MCP Servers

Keep MCP minimal during architecture-heavy phases.

Recommended default:

```text
MCP Servers: Off unless explicitly needed
```

If MCP is enabled, prefer local and bounded capabilities:

```text
filesystem/workspace: allowed only inside this repository
git: status and diff first; commits only by explicit request
terminal: approval required
```

Do not enable MCP capabilities that can modify secrets, deploy Azure resources, push commits, or run arbitrary terminal commands without approval.

## Step 7 - Auto-Approve

Default setting:

```text
Auto-Approve: Off
```

Allowed later, only after trust is established:

```text
read files
list files
inspect git diff
```

Require approval for:

```text
edit files
run terminal commands
dotnet sln add
dotnet new
git reset
git checkout
git clean
deployment scripts
Azure scripts
secret scripts
```

## Step 8 - Development Slice Rules

Every development prompt must include:

```text
accepted architect input
allowed files or folders
forbidden changes
local hypothesis
validation command
expected result
```

The developer model must implement one slice only. If it tries to broaden the task, stop and rerun with a smaller prompt.

## Step 9 - Validation

Run the validation command named in the development file before moving to the next slice.

Common validation commands:

```powershell
pwsh scripts/validate-adr-frontmatter.ps1
dotnet build XYDataLabs.OrderProcessingSystem.sln
dotnet test tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests/XYDataLabs.OrderProcessingSystem.Architecture.Tests.csproj
dotnet test tests/XYDataLabs.OrderProcessingSystem.Application.Tests/XYDataLabs.OrderProcessingSystem.Application.Tests.csproj
dotnet test tests/XYDataLabs.OrderProcessingSystem.API.Tests/XYDataLabs.OrderProcessingSystem.API.Tests.csproj
dotnet test tests/XYDataLabs.OrderProcessingSystem.Gateway.Tests/XYDataLabs.OrderProcessingSystem.Gateway.Tests.csproj
node scripts/validate-doc-links.js
pwsh scripts/validate-ai-customization.ps1
```

When tenant, payment, or webhook behavior is touched, run focused regression tests for those areas before continuing.

## Step 10 - Checkpoints And Git Hygiene

Before each development slice:

```powershell
git status --short
```

After each development slice:

```powershell
git status --short
git diff --check
```

If Zoo Code supports checkpoints, create one before running each development prompt.

Never revert unrelated user changes. If unexpected changes appear, stop and ask for review.

## Phase 9 Example

For Phase 9, the prompt pack lives here:

```text
zoocode/phase 9/
```

The supporting instructions are here:

```text
docs/zoocode/phase9/1-instructions-readme.md
```

Phase 9 flow:

```text
1. Run npx repomix.
2. Run phase9_architect1.0.md with repomix-output.xml.
3. Run phase9_architect1.1.md as the correction gate.
4. Run phase9_architect2.0.md for the blueprint.
5. Review and accept the first slice.
6. Run phase9_development1.0.md.
7. Validate.
8. Continue one development file at a time.
9. Run phase9_architect99.0.md before final closeout.
10. Run phase9_development99.0.md only for closeout/context sync.
```

## What Good Looks Like

A good Zoo Code phase run has:

- one source of architecture truth
- small developer prompts
- no unreviewed architecture changes during implementation
- no broad auto-approve
- validation after each slice
- explicit context handoff between architect, developer, and reviewer profiles
- final closeout that updates docs and active work

If those things are present, Zoo Code is helping. If they are missing, Zoo Code is acting as an uncontrolled agent and should be stopped.
