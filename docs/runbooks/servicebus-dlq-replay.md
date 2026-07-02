# Service Bus DLQ Replay Runbook

This runbook covers the Phase 10 dead-letter replay path for the `order-events-dlq` topology.

## Scope

- Source topic: `order-events`
- Dead-letter topic: `order-events-dlq`
- Replay subscription: `dlq-replay`
- Replay worker: `XYDataLabs.OrderProcessingSystem.Infrastructure/Messaging/DlqReplayWorker.cs`

## What the worker does

- Reads messages from the DLQ replay subscription.
- Rehydrates the canonical `EventEnvelope`.
- Replays messages that still look safe to deliver.
- Quarantines poison or non-replayable messages in the subscription dead-letter queue.

## Operator checks

1. Confirm the dead-letter topic has traffic.
2. Inspect `EventType`, `EnvelopeMessageId`, `AttemptCount`, and `FailureCategory`.
3. Verify the payload still maps to a known integration event type.
4. Replay only transient or operator-approved messages.
5. Leave poison, malformed, or expired messages quarantined.

## Replay rules

- Replay stays on the canonical envelope contract.
- Replay generates a fresh broker message id.
- Replay preserves trace, correlation, causation, and tenant metadata.
- Replay increments `AttemptCount` and records the source dead-letter context.

## Quarantine rules

- Missing event type metadata goes to quarantine.
- Unknown integration event types go to quarantine.
- Payloads that cannot be deserialized go to quarantine.
- Messages that have exceeded the replay limit go to quarantine.

## Notes

- Do not bulk replay without checking the dead-letter reason.
- Do not introduce `SharedContracts` for replay alone.
- Keep the replay worker disabled unless the Service Bus transport slice is enabled.
