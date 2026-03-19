# ADR-005: Serilog for Structured Logging

**Date:** 2025-03-01  
**Status:** Accepted — enrichers pending  
**Deciders:** Project architect

---

## Context

Default ASP.NET Core logging (`ILogger<T>`) produces unstructured text that is difficult to:
- Query in Application Insights (no property-based filtering)
- Parse in Docker/ACA container environments where logs are JSON stdout
- Correlate across multiple services (no automatic correlation ID propagation)

## Decision

Replace default logging with **Serilog** via `UseSerilog()` in `Program.cs` for both API and UI projects.

```csharp
// Program.cs
builder.Host.UseSerilog((ctx, cfg) => cfg
    .ReadFrom.Configuration(ctx.Configuration)
    .WriteTo.Console(new JsonFormatter())
    .WriteTo.ApplicationInsights(
        TelemetryConfiguration.Active, TelemetryConverter.Traces));
```

**Key rule:** Use structured properties, never string interpolation:
```csharp
// ✅ Correct — queryable in App Insights by OrderId, CustomerId
Log.Information("Order {OrderId} placed for {CustomerId}", orderId, customerId);

// ❌ Wrong — unsearchable string blob
Log.Information($"Order {orderId} placed for {customerId}");
```

## Rationale

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| Serilog | Structured JSON, rich sink ecosystem, App Insights integration, widely used | Additional NuGet dependency | ✅ Selected |
| Default ILogger | Zero dependencies, works everywhere | Unstructured text, no sinks, poor App Insights integration | ❌ Rejected for production |
| NLog | Mature, structured support | Less .NET 8 ecosystem fit vs Serilog | ❌ Rejected |

## Consequences

**Positive:**
- Every log entry is a structured JSON document — queryable by property in App Insights
- Same code works locally (console), in Docker (stdout JSON), and in Azure (App Insights)
- `WithCorrelationId()` enricher will propagate trace IDs across service calls (pending)

**Negative / Trade-offs:**
- `Serilog.Sinks.ApplicationInsights` requires Application Insights telemetry configuration
- Must ensure Serilog is bootstrapped before `WebApplication.CreateBuilder()` to catch startup exceptions

**Current state (March 2026):**
- ✅ `Serilog.AspNetCore` + `UseSerilog()` wired in API + UI
- ✅ Console + File + ApplicationInsights sinks
- ❌ `WithMachineName()`, `WithEnvironmentName()`, `WithCorrelationId()` enrichers not yet added
- ❌ Cross-service correlation ID propagation (planned Day 65)

## Related
- ADR-001: Clean Architecture — Serilog configured in API/UI entry points, not in Application/Domain layers
- Day 65 curriculum: Add enrichers + verify correlation ID flow in App Insights
