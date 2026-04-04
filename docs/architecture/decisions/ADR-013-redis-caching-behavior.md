# ADR-013: Redis Caching via ICacheable Pipeline Behavior

**Date:** 2026-03-30
**Status:** Accepted
**Deciders:** Project architect

---

## Context

Phase 6 introduced a distributed caching layer to reduce repeated database reads for stable
reference data (e.g. customer lists, product catalogues). The solution must:

1. Be opt-in per query — not all queries should be cached; commands must never be cached.
2. Require no changes to the `Dispatcher` or any handler to add caching to a query.
3. Work in local development without a running Redis instance.
4. Be backed by Redis in cloud environments where a connection string is configured.

The `IDistributedCache` abstraction in ASP.NET Core supports both Redis (via
`AddStackExchangeRedisCache`) and an in-memory fallback (`AddDistributedMemoryCache`), making it
the natural choice to satisfy requirements 3 and 4 with the same behavior code.

---

## Decision

Caching is implemented as an opt-in `CachingBehavior<TRequest, TResult>` pipeline behavior
(registered as the **outermost** behavior in the CQRS pipeline — see ADR-011) that inspects each
request for the `ICacheable` marker interface. Only requests that implement `ICacheable` are
cached; all others pass through with zero overhead.

### ICacheable interface

```csharp
// Application/CQRS/ICacheable.cs
public interface ICacheable
{
    string CacheKey { get; }
    TimeSpan? Expiration => null;   // default: 5 minutes via CachingBehavior
}
```

A query opts in by implementing `ICacheable`:

```csharp
public sealed record GetAllCustomersQuery
    : IQuery<Result<IEnumerable<CustomerDto>>>, ICacheable
{
    public string CacheKey => "customers:all";
    public TimeSpan? Expiration => TimeSpan.FromMinutes(5);
}
```

### CachingBehavior execution flow

```
Request implements ICacheable?
  No  → pass through to next behavior immediately
  Yes → try IDistributedCache.GetStringAsync(cacheKey)
          Hit  → deserialize JSON → return cached result (pipeline short-circuits)
          Miss → call next() → serialize result as JSON → SetStringAsync with expiration
```

Serialization uses `System.Text.Json`. `Result<T>` has a `[JsonConstructor]`-tagged factory method
to survive round-trips through the cache.

### IDistributedCache registration (Infrastructure/StartupHelper.cs)

```csharp
var redisConnection = builder.Configuration.GetConnectionString("Redis");
if (!string.IsNullOrWhiteSpace(redisConnection))
{
    builder.Services.AddStackExchangeRedisCache(options =>
    {
        options.Configuration = redisConnection;
        options.InstanceName = "OrderProcessing:";
    });
}
else
{
    builder.Services.AddDistributedMemoryCache();
}
```

Redis is activated when a `"Redis"` connection string is present in configuration. In local VS or
local Docker (without a Redis container), `AddDistributedMemoryCache` is used — behaviorally
identical from the perspective of `CachingBehavior` but scoped to a single process.

---

## Rationale

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| `ICacheable` marker + `CachingBehavior` pipeline | Opt-in per query; no handler changes; consistent with CQRS pipeline pattern; same code path for Redis and in-memory | Serialization adds latency on cache miss; JSON round-trip requires `Result<T>` to be JSON-safe | ✅ Selected |
| `IMemoryCache` (in-process only) | Zero latency for local dev; no serialization | Not distributed; doesn't work with multiple App Service instances / horizontal scale | ❌ Rejected |
| Decorator pattern per handler | Explicit, no reflection | One decorator class per cacheable query; too much boilerplate | ❌ Rejected |
| Output caching (ASP.NET Core `[OutputCache]`) | Built-in, simple | HTTP-level only; caches raw response bytes; cannot invalidate by cache key from within domain logic | ❌ Rejected for domain queries |
| No caching (Phase 6 scope only EF retry) | Simplest | Repeated DB round-trips for stable data; unacceptable for high-frequency read paths | ❌ Rejected |

---

## Consequences

**Positive:**
- Adding caching to any query costs two lines of code: implement `ICacheable`, return a cache key.
  No handler, dispatcher, or DI registration changes needed.
- `AddDistributedMemoryCache` fallback means local development and CI pipelines never need a Redis
  instance — the same binary and behavior code runs everywhere.
- The outermost pipeline position means cache hits short-circuit the entire pipeline (validation,
  logging, handler, DB) — maximum latency saving.

**Negative / Trade-offs:**
- Cache invalidation is manual. When an entity is mutated (command), the relevant cache key must
  be explicitly evicted. There is currently no automatic write-through or invalidation — callers
  rely on expiration TTL.
- `System.Text.Json` serialization of complex `Result<IEnumerable<T>>` types adds a small CPU cost
  on cache miss. For objects with circular references or non-JSON-safe types, the behavior would
  fail at runtime. This is an architectural constraint: all `TResult` types used with `ICacheable`
  queries must be JSON-serializable.
- In-memory fallback (`AddDistributedMemoryCache`) is not shared across multiple instances. If the
  app is deployed to >1 App Service instance without Redis, each instance has its own cache — stale
  reads are possible. Redis must be configured before horizontal scaling.

**Future obligations:**
- Phase 9 (microservices): each service that needs distributed caching must include its own Redis
  connection string or connect to a shared Redis instance. `OrderProcessing:` key prefix prevents
  cross-service key collisions.
- Before horizontal scaling of App Service, add a Redis connection string to Key Vault for dev/stg
  environments (prod should already have one). Azure Cache for Redis Basic C1 tier is sufficient
  for non-production.
- Consider adding a `CacheInvalidationBehavior` or `IHandleInvalidation` interface to allow
  commands to declare which cache keys they invalidate — avoids stale reads on sequential
  command → query flows.
- If Redis instrumentation is added to the OTel pipeline (see ADR-012 future obligation), cache
  hits and misses will appear as spans in Application Insights automatically.

---

## Related

- ADR-011: Hand-rolled CQRS — `CachingBehavior` is the outermost pipeline behavior; pipeline
  registration order is defined in `CqrsServiceExtensions.AddCqrs()`
- ADR-012: OpenTelemetry dual-export — future candidate for Redis span instrumentation
- `Application/CQRS/ICacheable.cs` — opt-in marker interface
- `Application/CQRS/Behaviors/CachingBehavior.cs` — full behavior implementation
- `Infrastructure/StartupHelper.cs` — Redis vs in-memory registration switch
- `Application/Features/Customers/Queries/GetAllCustomersQuery.cs` — canonical `ICacheable` example
