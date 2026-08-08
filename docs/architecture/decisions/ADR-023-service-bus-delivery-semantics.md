# ADR-023: Service Bus Delivery Semantics

**Status:** Accepted  
**Date:** 2026-07-25

## Context

The order-created flow crosses database and broker boundaries and Azure Service Bus provides at-least-once delivery. Retries, restarts, duplicate messages, out-of-order delivery, and tenant-specific database routing are therefore normal operating conditions rather than exceptional cases.

The application already has canonical envelope, outbox, inbox, and idempotency concepts. Phase 10 must define how those concepts govern real publishers and consumers.

## Decision

Phase 10 adopts **at-least-once transport with idempotent business effects**.

- Business transactions commit domain state and outbox records atomically.
- An outbox publisher sends the canonical envelope to Service Bus and marks publication only after broker acknowledgement.
- Consumers resolve and validate tenant context before opening the tenant database.
- Consumers record inbox/idempotency state before side effects and complete a broker message only after the business transaction commits.
- Transient failures are abandoned/retried; permanent failures are dead-lettered with an inspectable reason and description.
- Broker entities use a 7-day TTL and maximum delivery count of 10 unless an evidence-backed environment exception is approved.
- Messages are limited to 256 KB. Larger payloads require the Phase 12 Blob claim-check design.
- There is no global ordering guarantee. Consumers must tolerate out-of-order delivery.
- Service Bus sessions are not enabled by default. A measured per-order ordering requirement must amend this ADR before sessions are introduced.
- Local emulator connections may use connection strings. Azure workloads use `DefaultAzureCredential` and least-privilege Service Bus data roles.

## Alternatives

| Option | Result |
|---|---|
| At-least-once plus outbox/inbox idempotency | Selected: aligns with Service Bus behavior and existing persistence patterns |
| Exactly-once transport | Rejected: cannot be guaranteed across SQL, broker, and consumer boundaries |
| Complete message before committing state | Rejected: can lose business effects |
| Global ordering | Rejected: unnecessary coupling and throughput cost |
| Sessions for every message | Deferred: introduce only when a concrete per-aggregate ordering invariant requires them |

## Consequences

Positive:

- Restarts and duplicate delivery are safe and testable.
- Transport concerns remain outside domain handlers.
- Shared and dedicated tenant databases use the same delivery contract.

Trade-offs:

- Inbox/outbox storage and cleanup require operational ownership.
- Consumers must be idempotent and order-tolerant.
- End-to-end latency includes outbox polling and broker processing.

## Obligations

- Prove one committed order produces one Inventory and one Notification business effect.
- Prove duplicate delivery, consumer restart, transient retry, and permanent DLQ behavior.
- Measure outbox-to-broker and broker-to-consumer latency.
- Keep message metadata sufficient for tracing, tenant resolution, and replay.

## Related

- ADR-020: Webhook Inbox Idempotency
- ADR-021: Phase 9 Module Isolation Before Service Extraction
- ADR-024: DLQ Ownership And Approval Replay
- [Service Bus DLQ Replay Runbook](../../runbooks/servicebus-dlq-replay.md)

