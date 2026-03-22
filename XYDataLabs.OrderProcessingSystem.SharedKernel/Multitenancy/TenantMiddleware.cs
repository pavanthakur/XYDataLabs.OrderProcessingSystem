using Microsoft.AspNetCore.Http;
using Serilog.Context;
using System.Text.Json;

namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

public sealed class TenantMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ITenantResolver _tenantResolver;
    public const string TenantHeaderName = "X-Tenant-Code";
    internal const string HttpContextItemKey = "TenantContext";
    private const string RuntimeConfigurationPath = "/api/v1/info/runtime-configuration";

    public TenantMiddleware(RequestDelegate next, ITenantResolver tenantResolver)
    {
        _next = next;
        _tenantResolver = tenantResolver;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        if (IsRuntimeConfigurationRequest(context.Request.Path))
        {
            await _next(context);
            return;
        }

        var tenantCode = context.Request.Headers[TenantHeaderName].FirstOrDefault();

        if (string.IsNullOrWhiteSpace(tenantCode))
        {
            await WriteFailureAsync(context, StatusCodes.Status400BadRequest, $"Missing required header '{TenantHeaderName}'.");
            return;
        }

        var tenantContext = await _tenantResolver.ResolveTenantAsync(tenantCode, context.RequestAborted);
        if (tenantContext is null)
        {
            await WriteFailureAsync(context, StatusCodes.Status400BadRequest, $"Tenant code '{tenantCode}' is not recognized.");
            return;
        }

        if (IsBlockedStatus(tenantContext.TenantStatus))
        {
            await WriteFailureAsync(context, StatusCodes.Status403Forbidden, $"Tenant '{tenantContext.TenantCode}' is not active.");
            return;
        }

        context.Items[HttpContextItemKey] = tenantContext;

        using (LogContext.PushProperty("TenantId", tenantContext.TenantId))
        using (LogContext.PushProperty("TenantCode", tenantContext.TenantCode))
        using (LogContext.PushProperty("TenantExternalId", tenantContext.TenantExternalId))
        {
            await _next(context);
        }
    }

    private static bool IsBlockedStatus(string? tenantStatus)
    {
        return string.Equals(tenantStatus, "Suspended", StringComparison.OrdinalIgnoreCase)
            || string.Equals(tenantStatus, "Decommissioned", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsRuntimeConfigurationRequest(PathString requestPath)
    {
        return string.Equals(requestPath.Value, RuntimeConfigurationPath, StringComparison.OrdinalIgnoreCase);
    }

    private static async Task WriteFailureAsync(HttpContext context, int statusCode, string message)
    {
        context.Response.StatusCode = statusCode;
        context.Response.ContentType = "application/json";

        await context.Response.WriteAsync(JsonSerializer.Serialize(new { message }));
    }
}
