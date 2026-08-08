# ADR-024: DLQ Ownership And Approval Replay

**Status:** Accepted  
**Date:** 2026-07-25

## Context

Dead-letter intake and replay have different safety responsibilities. Intake must classify and preserve a failed delivery. Replay changes system state and can amplify poison messages or duplicate business effects.

Using the same subscription for intake and replay creates competing consumers. Automatically replaying every transient-looking message can create loops, while a broker test utility that receives and republishes a message does not prove that deployed Function code owns the operational path.

## Decision

DLQ intake, quarantine, approval, and replay are separate governed stages.

- `dlq-intake` receives forwarded dead letters, validates the envelope, classifies failure, and persists quarantine metadata.
- `dlq-replay-requests` contains only explicitly approved replay requests.
- Intake and replay Functions never listen to the same subscription.
- Application-controlled settlement uses `AutoCompleteMessages = false`.
- Poison, expired, malformed, unauthorized-tenant, and policy-rejected messages are not automatically replayed.
- Transient messages require approval unless a later ADR authorizes a narrowly bounded automatic policy.
- Replay preserves body, content type, application properties, message/correlation/causation/tenant identifiers, trace context, failure metadata, and original enqueue metadata.
- Replay attempts are capped at five and guarded by a runtime kill switch.
- Inbox/idempotency remains the final protection against duplicate business effects.
- Only one component owns replay publication for a replay request.
- Azure smoke must prove the deployed Function package, function discovery, and invocation identity. Equivalent broker operations performed by `Phase10.TransportSmoke` are broker-path evidence only.

## Alternatives

| Option | Result |
|---|---|
| Separate intake and approved replay entities | Selected: explicit ownership and auditable transitions |
| One shared DLQ subscription | Rejected: competing consumers and nondeterministic ownership |
| Blind bulk replay | Rejected: poison amplification and duplicate side effects |
| Smoke utility as Function proof | Rejected: bypasses deployed trigger and package |
| Unlimited retries | Rejected: creates replay loops and hides permanent defects |

## Consequences

Positive:

- Operators can distinguish classification, quarantine, approval, and execution.
- Poison messages remain inspectable without re-entering the business flow.
- Function deployment evidence matches the behavior being claimed.

Trade-offs:

- Additional entities and persisted operational metadata are required.
- Replay has an approval and audit workflow instead of being a single command.
- Failure drills require more than broker-level topology checks.

## Obligations

- Implement separate Function triggers and explicit settlement.
- Persist approval, operator, reason, attempts, timestamps, and outcome.
- Alert on DLQ depth, oldest age, replay failures, and rejected approvals.
- Prove transient replay once, poison quarantine, kill switch, max attempts, and no replay loop.

## Related

- ADR-020: Webhook Inbox Idempotency
- ADR-023: Service Bus Delivery Semantics
- [Phase 10 Azure Smoke Runbook](../../runbooks/phase10-azure-smoke.md)
- [Service Bus DLQ Replay Runbook](../../runbooks/servicebus-dlq-replay.md)

