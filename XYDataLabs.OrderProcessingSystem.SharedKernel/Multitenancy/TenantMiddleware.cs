using Microsoft.AspNetCore.Http;
using Serilog;
using Serilog.Context;
using System.Text.Json;

namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

public sealed class TenantMiddleware
{
    private readonly RequestDelegate _next;
    public const string TenantHeaderName = "X-Tenant-Code";
    internal const string HttpContextItemKey = "TenantContext";
    private const string RuntimeConfigurationPath = "/api/v1/info/runtime-configuration";

    public TenantMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    public async Task InvokeAsync(HttpContext context, ITenantResolver tenantResolver)
    {
        ArgumentNullException.ThrowIfNull(context);
        ArgumentNullException.ThrowIfNull(tenantResolver);

        var requestedTenantCode = context.Request.Headers[TenantHeaderName].FirstOrDefault()?.Trim();

        using var requestedTenantScope = LogContext.PushProperty(
            "RequestedTenantCode",
            string.IsNullOrWhiteSpace(requestedTenantCode) ? "none" : requestedTenantCode);

        if (IsRuntimeConfigurationRequest(context.Request.Path))
        {
            using var bootstrapTenantScope = LogContext.PushProperty("TenantCode", "bootstrap");
            await _next(context);
            return;
        }

        if (string.IsNullOrWhiteSpace(requestedTenantCode))
        {
            Log.Warning(
                "Rejected request {Method} {Path} because required tenant header {TenantHeaderName} was missing",
                context.Request.Method,
                context.Request.Path,
                TenantHeaderName);
            await WriteFailureAsync(context, StatusCodes.Status400BadRequest, $"Missing required header '{TenantHeaderName}'.");
            return;
        }

        var tenantContext = await tenantResolver.ResolveTenantAsync(requestedTenantCode, context.RequestAborted);
        if (tenantContext is null)
        {
            Log.Warning(
                "Rejected request {Method} {Path} because tenant code {RequestedTenantCode} was not recognized",
                context.Request.Method,
                context.Request.Path,
                requestedTenantCode);
            await WriteFailureAsync(context, StatusCodes.Status400BadRequest, $"Tenant code '{requestedTenantCode}' is not recognized.");
            return;
        }

        if (IsBlockedStatus(tenantContext.TenantStatus))
        {
            Log.Warning(
                "Rejected request {Method} {Path} because tenant {TenantCode} is in blocked status {TenantStatus}",
                context.Request.Method,
                context.Request.Path,
                tenantContext.TenantCode,
                tenantContext.TenantStatus);
            await WriteFailureAsync(context, StatusCodes.Status403Forbidden, $"Tenant '{tenantContext.TenantCode}' is not active.");
            return;
        }

        context.Items[HttpContextItemKey] = tenantContext;

        using (LogContext.PushProperty("TenantId", tenantContext.TenantId))
        using (LogContext.PushProperty("TenantCode", tenantContext.TenantCode))
        using (LogContext.PushProperty("TenantExternalId", tenantContext.TenantExternalId))
        using (LogContext.PushProperty("TenantTier", tenantContext.IsSharedPool ? "SharedPool" : "Dedicated"))
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
