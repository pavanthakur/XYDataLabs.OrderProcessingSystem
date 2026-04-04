# ADR-011: Hand-Rolled CQRS with Pipeline Behaviors

**Date:** 2026-03-28
**Status:** Accepted
**Deciders:** Project architect

---

## Context

The Application layer needed a use-case dispatch mechanism to route commands (write operations) and
queries (read operations) through cross-cutting concerns (validation, logging, caching) before
reaching the handler. Two options were evaluated: adopting MediatR (the de-facto community choice)
or implementing a minimal hand-rolled CQRS kernel.

The project already uses Clean Architecture with strict dependency inversion — Application defines
interfaces; Infrastructure implements them. Adding MediatR would introduce a third-party NuGet
package to the Application layer, creating a framework dependency in the business logic tier.
The feature set required was a small subset of what MediatR provides.

**Scope of the custom implementation:**

| Component | File |
|-----------|------|
| `ICommand<TResult>` / `IQuery<TResult>` | `Application/CQRS/ICommand.cs`, `IQuery.cs` |
| `ICommandHandler<,>` / `IQueryHandler<,>` | `Application/CQRS/ICommandHandler.cs`, `IQueryHandler.cs` |
| `IDispatcher` | `Application/CQRS/IDispatcher.cs` |
| `Dispatcher` | `Application/CQRS/Dispatcher.cs` |
| `IPipelineBehavior<TRequest, TResult>` | `Application/CQRS/IPipelineBehavior.cs` |
| `CachingBehavior<,>` | `Application/CQRS/Behaviors/CachingBehavior.cs` |
| `LoggingBehavior<,>` | `Application/CQRS/Behaviors/LoggingBehavior.cs` |
| `ValidationBehavior<,>` | `Application/CQRS/Behaviors/ValidationBehavior.cs` |
| `AddCqrs()` extension | `Application/CQRS/CqrsServiceExtensions.cs` |

---

## Decision

Implement a hand-rolled CQRS kernel inside the `Application` project with no external library
dependencies. The kernel consists of marker interfaces (`ICommand<T>`, `IQuery<T>`), handler
interfaces (`ICommandHandler<,>`, `IQueryHandler<,>`), a pipeline behavior interface
(`IPipelineBehavior<,>`), and a `Dispatcher` that resolves handlers and behaviors from the
`IServiceProvider` using reflection at dispatch time.

### Dispatch flow

```
Controller → IDispatcher.SendAsync / QueryAsync
  → Dispatcher resolves ICommandHandler / IQueryHandler via IServiceProvider
  → Dispatcher builds behavior pipeline in reverse registration order
  → CachingBehavior (outermost) → LoggingBehavior → ValidationBehavior → Handler
```

### Handler auto-registration

`AddCqrs(assembly)` in `CqrsServiceExtensions` scans the calling assembly at DI startup via
reflection and registers every concrete `ICommandHandler<,>` and `IQueryHandler<,>` implementation
as `Scoped`. Pipeline behaviors are registered explicitly in the correct order:

```csharp
services.AddScoped(typeof(IPipelineBehavior<,>), typeof(CachingBehavior<,>));
services.AddScoped(typeof(IPipelineBehavior<,>), typeof(LoggingBehavior<,>));
services.AddScoped(typeof(IPipelineBehavior<,>), typeof(ValidationBehavior<,>));
```

Behaviors are reversed inside `Dispatcher.BuildPipeline` so the first-registered behavior wraps
the outermost position in the chain.

### Validation integration

`ValidationBehavior` resolves all `IValidator<TRequest>` instances from DI. When `TResult` is
`Result<T>`, validation failures are returned as `Result<T>.Failure(error)` rather than thrown as
exceptions — preserving the no-exception-for-business-logic rule. When `TResult` is not `Result<T>`,
a `ValidationException` is thrown (covered by the global error-handling middleware).

---

## Rationale

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| Hand-rolled CQRS | Zero library dependency in Application layer; only what is needed; full control over pipeline chaining and reflection | Slightly more code to maintain; no community support | ✅ Selected |
| MediatR | Battle-tested, community-supported, less boilerplate | External NuGet dependency in Application layer; couples business logic to a framework; more features than needed | ❌ Rejected |
| No dispatcher (direct handler injection) | Simplest | No cross-cutting pipeline; controllers must call validators/loggers individually; no caching hook | ❌ Rejected |

---

## Consequences

**Positive:**
- Application layer has zero NuGet dependencies beyond the BCL and FluentValidation (domain concern).
- The full pipeline is visible, debuggable, and unit-testable without a mocking framework for the
  dispatcher itself.
- New cross-cutting behaviors (e.g., `TenantValidationBehavior`) can be added without modifying
  any existing code — open/closed principle.
- Assembly scanning means handlers are auto-discovered; no manual DI registration per handler.

**Negative / Trade-offs:**
- Dispatch uses reflection (`GetMethod`, `Invoke`) at runtime, not compile-time generics. This adds
  a small latency cost (~microseconds) and means type errors surface at runtime rather than
  compile time.
- Developers unfamiliar with the pattern must understand `Dispatcher.BuildPipeline` to reason about
  behavior ordering. A comment in `CqrsServiceExtensions` documents the order explicitly.
- If MediatR publishes a major pattern change (e.g., cancellable streams), the team must evaluate
  whether to adopt it manually.

**Future obligations:**
- Any new cross-cutting concern (e.g., tenant enforcement, idempotency) must be added as an
  `IPipelineBehavior<,>` and registered in `CqrsServiceExtensions` — not injected into individual
  handlers.
- `Result<T>` must remain JSON-round-trippable (has `[JsonConstructor]`) for the `CachingBehavior`
  to deserialize correctly.
- Architecture tests (`Architecture.Tests`) enforce that Application handlers only implement
  `ICommandHandler<,>` or `IQueryHandler<,>` — do not bypass via direct constructor injection from
  the API layer.

---

## Related

- ADR-001: Clean Architecture with DDD Layers — establishes the dependency rule that Application
  must not reference Infrastructure
- ADR-013: Redis caching pipeline behavior — `CachingBehavior` described here is the consumer of that pattern
- `Application/CQRS/` — full source of the hand-rolled kernel
- `tests/XYDataLabs.OrderProcessingSystem.Application.Tests/` — handler unit tests use the real
  `Dispatcher` wired with in-memory mocks
