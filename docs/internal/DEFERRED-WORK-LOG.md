# Deferred Work Log

Use this register for justified deferrals that remain open after `/XYDataLabs-completion-check` or any other shared governance workflow.

## Rules

1. Every open item needs an owner.
2. Every open item needs a review date.
3. Every open item needs a closure trigger, not just a vague future intent.
4. Closed items stay visible until the next deliberate cleanup pass so the repo retains an audit trail.

## Open Items

| ID | Item | Source | Owner | Rationale | Risk if delayed | Review date | Closure trigger | Status |
|----|------|--------|-------|-----------|-----------------|-------------|-----------------|--------|
| DW-001 | Introduce `Address` value object where it crosses a real aggregate or request boundary | Phase 7 closeout | Phase 8 feature owner | The value object has no stable boundary anchor yet; adding it now would be speculative | Rework and churn if modeled against the wrong boundary | 2026-05-01 | A real aggregate or API request shape requires address behavior beyond primitive strings | Open |
| DW-002 | Broaden optimistic concurrency beyond `Order` | Phase 7 closeout | Domain owner | The first concurrency slice proved the pattern on `Order`; wider rollout should follow real contention points | Silent overwrite risk remains on aggregates not yet protected | 2026-05-15 | Next aggregate-level change identifies a write-conflict path that merits row-version protection | Open |
| DW-003 | Add enhanced OpenTelemetry metrics for the Phase 7 hardening areas | Phase 7 closeout | Observability owner | Readiness semantics and typed-boundary hardening were prioritized first | Lower visibility into boundary failures and startup behavior | 2026-05-15 | The next observability slice defines the exact metrics and alert use cases | Open |
| DW-004 | Formalize audit retention and redaction policy as an ADR | Audit trail planning | Architecture owner | The policy decision should be made with real retention, export, and compliance requirements in view | Audit implementation could drift without an explicit long-term policy | 2026-05-31 | Audit logging reaches compliance-sensitive retention/export scope | Open |
| DW-006 | Pilot shared MCP configuration under read-only controls | AI governance hardening | AI governance owner | Shared MCP adds capability and risk; governance and validation should land first | Uncontrolled external-tool growth or inconsistent local setups | 2026-05-31 | Approved server inventory, auth model, and read-only-first protocol are documented | Open |
| DW-007 | Add an opt-in git hook template for automatic local AI governance validation | AI governance hardening | AI governance owner | The repo now has CI enforcement and a VS Code task bundle; the automatic local hook remains optional until the team decides the extra friction is justified | Contributors may forget to run the local bundle task before push and rely on CI to catch drift | 2026-05-15 | Team agreement that deterministic local enforcement is worth the added commit friction, followed by a repo-owned hook template that mirrors the existing validators | Open |

## Closed Items

Add closed items here instead of deleting them immediately when the closure itself is useful context for future reviewers.

| ID | Item | Closed date | Closure summary |
|----|------|-------------|-----------------|
| DW-005 | Add a repo-owned skills layer for repeated specialist workflows | 2026-04-07 | Added `.github/skills/README.md`, introduced the first repo-owned skill for Azure deployment operations, and extended AI validation/discovery surfaces to govern skills alongside prompts and agents. |