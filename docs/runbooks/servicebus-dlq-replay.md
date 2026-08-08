# Service Bus DLQ Replay Runbook

This runbook covers the Phase 10 dead-letter intake, quarantine, approval, and replay path for the `order-events-dlq` topology. [ADR-024](../architecture/decisions/ADR-024-dlq-ownership-and-approval-replay.md) is authoritative when this runbook and transitional code differ.

## Scope

- Source topic: `order-events`
- Dead-letter topic: `order-events-dlq`
- Current intake subscription: `dlq-intake`
- Phase 10.4 target approved-request entity: `dlq-replay-requests`
- Transitional approval surface: `POST /api/v1/admin/dlq/{quarantineId}/approve`
- Azure implementation target: `XYDataLabs.OrderProcessingSystem.Functions/DlqReplayFunction.cs`

The current intake subscription and transitional approval surface are scaffolding, not the final production ownership model. Phase 10 cannot close until intake and replay use separate entities, one component owns each replay request, the approval surface lands in its final operations-owned shape, and Azure evidence proves the deployed Function package and invocation.

## What the worker does

- Reads only approved messages from the replay-request entity in the final topology.
- Rehydrates the canonical `EventEnvelope`.
- Rejects unapproved, poison, expired, malformed, or replay-limit-exceeded messages.
- Republishes an approved transient message once and records the result.
- Uses the same canonical replay policy in the local background worker and the Azure Functions trigger.

## Operator checks

1. Confirm the dead-letter topic has traffic.
2. Inspect `EventType`, `EnvelopeMessageId`, `AttemptCount`, and `FailureCategory`.
3. Verify the payload still maps to a known integration event type.
4. Confirm the message is transient and has an explicit operator approval record.
5. Leave poison, malformed, or expired messages quarantined.
6. Confirm the replay kill switch is not active and the attempt count is below `5`.
7. Capture the operator, reason, approval time, Function invocation id, replay message id, and outcome.

## Replay rules

- Replay stays on the canonical envelope contract.
- Replay generates a fresh broker message id.
- Replay preserves trace, correlation, causation, and tenant metadata.
- Replay increments `AttemptCount` and records the source dead-letter context.
- Replay attempts stop at `5`.
- Application-controlled settlement requires `AutoCompleteMessages = false`.
- Inbox/idempotency remains mandatory because replay does not provide exactly-once delivery.

## Quarantine rules

- Missing event type metadata goes to quarantine.
- Unknown integration event types go to quarantine.
- Payloads that cannot be deserialized go to quarantine.
- Messages that have exceeded the replay limit go to quarantine.

## Notes

- Do not bulk replay without checking the dead-letter reason.
- Do not attach intake and replay Functions to the same subscription.
- Do not treat `tools/Phase10.TransportSmoke` receive/republish behavior as deployed Function proof.
- Do not introduce `SharedContracts` for replay alone.
- Keep the replay worker disabled unless the Phase 10 transport baseline is enabled.
