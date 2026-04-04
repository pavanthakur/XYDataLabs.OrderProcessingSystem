# ADR-012: OpenTelemetry Dual-Export Strategy

**Date:** 2026-03-29
**Status:** Accepted
**Deciders:** Project architect

---

## Context

Phase 3 (Observability) introduced distributed tracing and metrics to provide end-to-end
visibility across the API and UI. The system runs in two fundamentally different contexts:

- **Azure (dev / stg / prod)** — Azure Application Insights is available via a connection string
  stored in Key Vault / App Service config.
- **Local development (VS, Docker)** — Application Insights is not available or not desired;
  developers use local tooling (Jaeger, .NET Aspire Dashboard, or simply log output).

A single hardcoded exporter would break one of these two contexts. The solution must export
telemetry to Azure Monitor **and** conditionally to an OTLP-compatible collector, using the same
pipeline and the same `ActivitySource` definitions.

**Instrumentation scope required:**

| Signal | Sources |
|--------|---------|
| Traces | ASP.NET Core, HttpClient, SQL Client, `OrderProcessing.Orders`, `OrderProcessing.Customers`, `OrderProcessing.Payments` |
| Metrics | ASP.NET Core, HttpClient, .NET runtime |
| Logs | Serilog (primary) enriched with `TraceId` / `SpanId` via `CorrelationMiddleware` |

---

## Decision

All observability is configured through a single `AddObservability(serviceName, configuration,
params string[] activitySourceNames)` extension method in
`SharedKernel/Observability/ObservabilityExtensions.cs`. The method applies the OpenTelemetry SDK
once and conditionally activates exporters based on environment variables — no code changes required
to switch destinations.

### Exporter activation rules

| Exporter | Condition | Variable |
|----------|-----------|----------|
| Azure Monitor (traces + metrics) | `APPLICATIONINSIGHTS_CONNECTION_STRING` is non-empty | Stored in Key Vault; surfaced via App Service config in Azure; absent locally |
| OTLP (traces + metrics) | `OTEL_EXPORTER_OTLP_ENDPOINT` is non-empty | Set in `docker-compose.dev.yml` for Aspire Dashboard / Jaeger; absent in Azure |

Both exporters may be active simultaneously — Azure Monitor for production observability, OTLP
for local real-time dashboards.

### Domain-scoped ActivitySources

Each business domain owns its `ActivitySource`:

```
OrderProcessing.Orders    → Application/Features/Orders/OrderActivitySource.cs
OrderProcessing.Customers → Application/Features/Customers/CustomerActivitySource.cs
OrderProcessing.Payments  → Application/Features/Payments/PaymentActivitySource.cs
```

Sources are registered with the tracing SDK via `AddObservability(... activitySourceNames)` called
from `API/Program.cs`:

```csharp
builder.Services.AddObservability(
    "OrderProcessingSystem.API",
    builder.Configuration,
    OrderActivitySource.Name,
    CustomerActivitySource.Name,
    PaymentActivitySource.Name);
```

### Correlation bridging (Serilog ↔ OpenTelemetry)

`CorrelationMiddleware` runs after `TenantMiddleware` in the ASP.NET Core pipeline. It reads the
active `Activity.TraceId` (set by the OpenTelemetry SDK's ASP.NET Core instrumentation) and pushes
`TraceId` and `SpanId` into Serilog's `LogContext`. This makes every Serilog log line contain the
same trace identifier as the OpenTelemetry span — enabling log-to-trace correlation in Application
Insights:

```csharp
using (LogContext.PushProperty("TraceId", traceId))
using (LogContext.PushProperty("SpanId", spanId))
{
    await _next(context);
}
```

The `X-Trace-Id` response header exposes the trace ID to API clients for support correlation.

---

## Rationale

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| Dual-export (Azure Monitor + OTLP, both conditional) | Works in all environments; no code change needed to switch; aligns with OTel vendor-neutral philosophy | Two exporters can increase trace volume and cost slightly | ✅ Selected |
| Azure Monitor only | Simple config; official Azure first-party | Breaks local developer experience; requires App Insights in every environment | ❌ Rejected |
| Serilog + Application Insights SDK only (no OTel) | Simpler setup | Serilog and AI SDK are not OTel-native; distributed traces across services are not correlated automatically; dead end before Phase 9 microservices | ❌ Rejected |
| OTLP only (Collector → Azure Monitor) | One export path | Requires OTel Collector in Azure (additional infrastructure); overkill for a monolith | ❌ Deferred to Phase 9 |

---

## Consequences

**Positive:**
- Trace IDs appear in both OTel spans and Serilog structured logs — queries in App Insights can
  pivot from a log line to its full distributed trace without any additional fields.
- Adding a future service (Phase 9 microservices) requires only registering its own `ActivitySource`
  and calling `AddObservability` — no changes to the existing pipeline.
- Local development works with zero Azure credentials; developers run the Aspire Dashboard or
  Jaeger via docker-compose to visualise traces.
- Sensitive SQL statements are included in SQL Client spans (`SetDbStatementForText = true`) — useful
  for performance debugging; **not** enabled in production (no change required; Azure Monitor
  sampling controls what is stored).

**Negative / Trade-offs:**
- Dual export in staging/production means spans are sent twice if both env vars are set; avoid
  setting `OTEL_EXPORTER_OTLP_ENDPOINT` in production App Service config.
- The `ApplicationInsightsOptions.FromConfiguration` reader expects the exact key
  `APPLICATIONINSIGHTS_CONNECTION_STRING` — changing this key in config requires updating this class.
- `CorrelationMiddleware` depends on `Activity.Current` being set before it runs, which is
  guaranteed only when `AddAspNetCoreInstrumentation()` is registered first. The middleware must
  stay after the OTel SDK builder call.

**Future obligations:**
- Phase 9 (microservices): each new service calls `AddObservability` with its own `ActivitySource`
  names. The Dispatcher-level `LoggingBehavior` already records request names; handlers emit spans
  using the relevant `ActivitySource`.
- When Redis is wired (ADR-013), consider adding `StackExchange.Redis` instrumentation to the OTel
  tracing pipeline.
- Consider adding `AddConsoleExporter()` gated on `IsDevelopment` for VS debugging without Docker.

---

## Related

- ADR-005: Serilog structured logging — Serilog is the primary log sink; OTel bridges `TraceId`
  into Serilog `LogContext` via `CorrelationMiddleware`
- ADR-010: Runtime environment detection — `WEBSITE_SITE_NAME` / `DOTNET_RUNNING_IN_CONTAINER`
  distinguish Azure from local; OTel exporter selection uses dedicated environment variables
- ADR-013: Redis caching pipeline behavior — future candidate for Redis span instrumentation
- `SharedKernel/Observability/ObservabilityExtensions.cs` — canonical exporter setup
- `SharedKernel/Observability/CorrelationMiddleware.cs` — log-to-trace correlation bridge
- `Application/Features/*/ActivitySource.cs` — domain-scoped `ActivitySource` definitions
