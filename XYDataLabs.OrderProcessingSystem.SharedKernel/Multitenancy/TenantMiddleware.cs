using Microsoft.AspNetCore.Http;
using Serilog.Context;

namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

public sealed class TenantMiddleware
{
    private readonly RequestDelegate _next;
    internal const string DefaultTenantId = "default";
    internal const string TenantHeaderName = "X-Tenant-Id";
    internal const string HttpContextItemKey = "TenantId";

    public TenantMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var tenantId = context.Request.Headers[TenantHeaderName].FirstOrDefault();

        if (string.IsNullOrWhiteSpace(tenantId))
        {
            tenantId = DefaultTenantId;
        }

        context.Items[HttpContextItemKey] = tenantId;

        using (LogContext.PushProperty("TenantId", tenantId))
        {
            await _next(context);
        }
    }
}
