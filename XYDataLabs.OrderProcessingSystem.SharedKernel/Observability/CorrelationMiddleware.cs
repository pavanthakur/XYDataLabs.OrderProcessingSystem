using System.Diagnostics;
using Microsoft.AspNetCore.Http;
using Serilog.Context;

namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Observability;

public sealed class CorrelationMiddleware
{
    private readonly RequestDelegate _next;

    public CorrelationMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var activity = Activity.Current;
        var traceId = activity?.TraceId.ToString() ?? context.TraceIdentifier;
        var spanId = activity?.SpanId.ToString() ?? string.Empty;

        // Add trace ID as response header for client-side correlation
        context.Response.OnStarting(() =>
        {
            context.Response.Headers["X-Trace-Id"] = traceId;
            return Task.CompletedTask;
        });

        // Enrich Serilog LogContext so {TraceId} and {SpanId} appear in structured logs
        using (LogContext.PushProperty("TraceId", traceId))
        using (LogContext.PushProperty("SpanId", spanId))
        {
            await _next(context);
        }
    }
}
