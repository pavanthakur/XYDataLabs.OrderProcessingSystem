# Completion Check Rubric

Use this rubric with `/XYDataLabs-completion-check` to decide whether a gap must be fixed now or can be deferred.

## Default Rule

If a gap changes correctness, security, tenant isolation, deployment safety, or shared repo truth, it is non-negotiable.

If a gap is operationally useful but does not weaken those guarantees, it may be deferrable only when recorded in [docs/internal/DEFERRED-WORK-LOG.md](../docs/internal/DEFERRED-WORK-LOG.md).

## Documentation

**Non-negotiable**
- A new workflow, script, prompt, or agent exists without an owning README or discovery path.
- A behavior or constraint changed and the canonical source-of-truth page would become wrong if not updated.
- A human operator would need to guess how to run or validate the new asset.

**Deferrable with log entry**
- Additional examples or nice-to-have prose would improve discoverability but the canonical run/validation path is already accurate.

## Guardrails

**Non-negotiable**
- Secret exposure risk exists.
- Tenant isolation is weakened or unproven.
- A system-boundary input lacks required validation.
- A destructive script or workflow lacks an explicit safeguard.
- A deployment or readiness gate could pass while the system is partially broken.

**Deferrable with log entry**
- Additional diagnostics, richer observability, or secondary lint checks would improve confidence but are not needed to preserve correctness.

## Unit Tests

**Non-negotiable**
- A new or changed domain rule is untested.
- A CQRS handler branch for expected success/failure behavior is untested.
- A regression was fixed without a test that would fail before the fix.

**Deferrable with log entry**
- A pure documentation or metadata change has no executable behavior.
- A trivial pass-through change already remains fully covered by broader existing tests and adding another test would be redundant.

## Integration and Architecture Tests

**Non-negotiable**
- A runtime boundary changed and the end-to-end behavior is not exercised.
- `Program.cs` environment or readiness gates changed without verification.
- A migration, tenant filter, or layer-boundary rule changed without the matching guardrail.

**Deferrable with log entry**
- A local convenience tool changed without affecting runtime behavior, schema, or delivery behavior.

## Automation and CI/CD

**Non-negotiable**
- A repeated manual step is introduced without a stable validation path.
- A repo-shared AI asset, script, or workflow can drift without CI noticing.
- A new workflow or validation rule is undocumented or unreachable from repo discovery surfaces.

**Deferrable with log entry**
- Local-only convenience automation such as optional VS Code tasks or hook templates that mirror an existing CI rule.

## Copilot Context

**Non-negotiable**
- `.github/copilot-instructions.md`, instruction files, prompts, or agents are changed without updating the discovery surfaces they depend on.
- A repo-shared AI customization changes but `pwsh scripts/validate-ai-customization.ps1` was not run.
- The repo would feed stale AI context after the change.

**Deferrable with log entry**
- A broader cleanup or wording refresh would improve clarity but the current context remains factually correct.

## Required Deferral Fields

If a gap is deferred, record all of the following in [docs/internal/DEFERRED-WORK-LOG.md](../docs/internal/DEFERRED-WORK-LOG.md):

1. Item and source task
2. Named owner
3. Rationale
4. Risk if delayed
5. Review date
6. Concrete closure trigger