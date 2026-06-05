# ADR-020: Webhook Inbox Idempotency — Durable Receipt, Deduplication, and Domain Transition

**Status:** Accepted

## Context

Phase 8.7 adds asynchronous payment lifecycle handling. Real-world payment providers send
webhooks for events such as `payment.captured`, refunds, chargebacks, and dispute lifecycle
changes. These arrive **after** the original synchronous request has returned, so the system
cannot rely on the response to the initial API call for final payment state.

Without a webhook pipeline, 3DS-authorised payments remain `UnknownNeedsReconciliation`
indefinitely. Phase 8 introduced the Outbox for reliable downstream event propagation;
Phase 8.7 adds the Inbox as the symmetric durable receipt point for inbound provider events.

### Key concerns

1. **Provider re-delivery.** HTTP delivery semantics are at-least-once. A provider may send
   the same event multiple times (retry after timeout, restart, etc.). Handlers must be safe
   to call more than once for the same event.

2. **HMAC replay attacks.** A signed payload is valid indefinitely unless the timestamp
   tolerance is checked. Requests with absent or invalid signatures must be rejected before
   any business deserialization.

3. **Concurrent delivery.** Under load a provider may deliver two copies of the same event
   in rapid succession. If both pass Inbox deduplication (before the first commit completes),
   the handler must be protected by optimistic concurrency — the second writer gets a
   `DbUpdateConcurrencyException` and retries.

4. **Tenant isolation.** Webhook events must be scoped to the correct tenant before any DB
   access. The `ITenantRegistry` from Phase 8.6 is the authoritative resolver.

5. **Slow handler isolation.** A slow or failing handler must not cause the provider to
   stop retrying. The endpoint must return 2xx as soon as the event is durably written to
   the Inbox; processing is asynchronous.

## Decision

### 1. Inbox entity

`InboxMessage` (already existed as a thin Phase 8 stub) is extended with:
- `ProviderEventId` — stable identity assigned by the provider; used for deduplication
- `Source` — provider name (e.g. `Razorpay`, `OpenPay`)
- `Payload` — raw JSON preserved for replay and audit
- `Status` — enum: `Received → Processing → Processed | Failed`
- `ProcessingAttempts` — capped at `MaxAttempts = 5`
- `LockExpiry` — distributed lock prevents concurrent workers from double-claiming a message
- `LastError` — last processing error for operational visibility

### 2. Signature validation before deserialization

`IWebhookSignatureValidator` (Application layer interface, Infrastructure implementation)
validates the raw request body against the provider-specific HMAC scheme **before** any
business deserialization. If signature is absent or invalid, the request is rejected with 401
and a metric is emitted (`orderprocessing.webhook.hmac_failures`).

- **Razorpay:** HMAC-SHA256 of raw body, hex-encoded, compared to `X-Razorpay-Signature` header
- **OpenPay:** HMAC-SHA256 of raw body, base64-encoded, compared to `X-OpenPay-Signature` header
- Webhook secrets stored in Key Vault (`kv-orderprocessing-{env}`); resolved via
  `IConfiguration` which is backed by Key Vault at runtime. Config key: `Webhooks:{Provider}:Secret`
- Timing-safe comparison via `CryptographicOperations.FixedTimeEquals`

### 3. Controller: durable receipt and immediate 202

`WebhookController.ReceiveAsync` (`POST /api/v1/webhook/{providerName}`):
1. Buffer raw body (`EnableBuffering`) to allow HMAC validation without consuming the stream
2. Validate HMAC — reject 401 on failure
3. Dispatch `RecordWebhookEventCommand` — persists `InboxMessage` with `Status=Received`
4. Return **202 Accepted** with `{ inboxMessageId }` immediately
   Processing happens asynchronously; the provider is free to consider delivery complete.

### 4. Background Inbox processor

`InboxProcessorWorker` (BackgroundService):
- Polls every 5 seconds
- Iterates all tenants via `TenantRegistryDbContext`
- Claims messages with `LockExpiry` to prevent double-processing across replicas
- Deduplicates by `ProviderEventId + Status=Processed` — if already processed, marks
  duplicate as `Processed` and emits `orderprocessing.inbox.dedup_hits`
- Dispatches to `IWebhookEventHandler` implementations resolved by `EventType`
- `DbUpdateConcurrencyException` (from `PaymentAttempt.RowVersion`) → release lock + retry
- After `MaxAttempts = 5`: transition to `Failed`

### 5. Event-to-domain handler

`IWebhookEventHandler` (Application layer interface) — one implementation per event category:
- `PaymentCapturedHandler` (`payment.captured`): transitions `PaymentAttempt` to `Succeeded`
- Handlers are registered as `IEnumerable<IWebhookEventHandler>` and resolved by `EventType`
- All handlers are idempotent: check current state before writing

### 6. Optimistic concurrency on PaymentAttempt (DW-002 absorbed)

`PaymentAttempt.RowVersion` (byte[], configured as `.IsRowVersion()`) is added to protect
webhook-mutated aggregates. A rapid duplicate delivery that passes Inbox deduplication (before
the first write commits) will fail with `DbUpdateConcurrencyException` on the second writer,
which is caught and retried by the worker. Architecture test enforces RowVersion is present
on `PaymentAttempt`.

### 7. OTel metrics (DW-003 absorbed)

Added to `BusinessMetrics` in SharedKernel:

| Metric | Type | Tags |
|--------|------|------|
| `orderprocessing.webhook.hmac_failures` | Counter | `provider` |
| `orderprocessing.inbox.dedup_hits` | Counter | `provider`, `event_type` |
| `orderprocessing.inbox.handler_duration` | Histogram (ms) | `event_type`, `outcome` |
| `orderprocessing.webhook.unresolvable_tenant` | Counter | `provider`, `event_type` |

## Rationale

| Option | Assessment |
|--------|------------|
| In-process synchronous handling | Rejected — provider retry rate tied to handler latency; one slow DB write causes cascading timeouts |
| Separate Inbox service / microservice | Rejected — premature extraction; Phase 9 extracts module boundaries; Phase 8.7 stays in monolith |
| MediatR for handler dispatch | Rejected — project uses hand-rolled CQRS (`ICommandHandler`); `IWebhookEventHandler` follows same pattern |
| Inbox dedup by `MessageId` alone | Rejected — `MessageId` is assigned by this system on first receipt; re-delivery of the same provider event gets a new `MessageId`; must use `ProviderEventId` |

## Consequences

**Positive**
- Provider can retry as aggressively as it wants; duplicates are absorbed by Inbox dedup
- `PaymentAttempt` can only transition through domain state, even under concurrent delivery
- All 4 OTel metrics are observable in Application Insights and Grafana without code changes
- Webhook handling is self-contained in the monolith; Phase 9/10 can move it without changing handler contracts

**Negative / trade-offs**
- Local development requires webhook secret in user secrets (`Webhooks:{Provider}:Secret`) or
  a bypass mode; the validator currently rejects requests with no secret configured
- Provider sandbox webhook forwarding (e.g. ngrok / smee.io) is required for local end-to-end
  testing; not yet automated
- `MaxAttempts = 5` failure cap means permanently failing handlers eventually stop retrying;
  a dead-letter inbox view or alerting on `Status=Failed` count is needed (deferred)

## Related

- ADR-019: Central Tenant Registry — `ITenantRegistry` is the prerequisite for tenant resolution in webhook handlers
- ADR-012: OpenTelemetry Dual Export — all 4 new metrics flow through the same `BusinessMetrics` Meter
- `docs/internal/phase-closeout-gates.md` — Phase 8.7 Docker bundle invocation
- `XYDataLabs.OrderProcessingSystem.Infrastructure/Webhooks/` — all Phase 8.7 infrastructure
- `XYDataLabs.OrderProcessingSystem.Application/Features/Webhooks/` — handler interface and commands
