# Domain

**Zero external dependencies.** Pure business entities, value objects, and domain logic only.

## Entities

| Entity | Purpose |
|--------|---------|
| `Order` / `OrderProduct` | Core order aggregate |
| `Customer` / `BillingCustomer` | Customer and billing profile |
| `Product` | Product catalogue |
| `Tenant` | Tenant row — owns `PaymentProviderCode` (routing authority per ADR-019) |
| `PaymentProvider` | Per-tenant provider config — `Use3DSecure`, `IsActive`, credentials (DB-owned, never from config) |
| `PaymentAttempt` / `PaymentAttemptHistory` | Payment lifecycle and audit trail |
| `TransactionStatusHistory` | Provider callback/webhook status events |
| `CardTransaction` / `PayinLog` / `PayinLogDetails` | Raw transaction records |
| `OutboxMessage` / `InboxMessage` | Transactional outbox/inbox for reliable async messaging (Phase 10+) |
| `AuditLog` | Cross-entity audit trail |

## Column limits (enforce in handlers — 500 does not mean truncate silently)

- `TransactionStatusHistory.Notes` — 255 chars
- `PaymentAttemptHistory.Notes` — 512 chars
- `PaymentAttempt.LastErrorMessage` — 512 chars

## Rules

- No EF Core, Azure SDK, or infrastructure imports.
- Strongly typed IDs and `Money` value object; EF converters live in Infrastructure.
- `OrderStatus` and `PaymentAttemptStatus` are the canonical state machines.
