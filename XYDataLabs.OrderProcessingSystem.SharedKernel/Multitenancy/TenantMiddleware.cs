using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Serilog;
using Serilog.Context;

namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

public sealed class TenantMiddleware
{
    private readonly RequestDelegate _next;
    public const string TenantHeaderName = "X-Tenant-Code";
    internal const string HttpContextItemKey = "TenantContext";
    private const string RuntimeConfigurationPath = "/api/v1/info/runtime-configuration";
    private const string HealthPath = "/health";
    private const string HealthLivePath = "/health/live";
    private const string HealthReadyPath = "/health/ready";
    private const string PaymentCallbackPath = "/payment/callback";

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

        if (IsTenantOptionalRequest(context.Request.Path))
        {
            using var bootstrapTenantScope = LogContext.PushProperty(
                "TenantCode",
                ResolveOptionalTenantCode(context));
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
            await WriteFailureAsync(
                context,
                StatusCodes.Status400BadRequest,
                "Tenant header is required.",
                $"Missing required header '{TenantHeaderName}'.",
                "urn:xydatalabs:problem:tenant-header-required",
                requestedTenantCode);
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
            await WriteFailureAsync(
                context,
                StatusCodes.Status400BadRequest,
                "Tenant code is not recognized.",
                $"Tenant code '{requestedTenantCode}' is not recognized.",
                "urn:xydatalabs:problem:tenant-code-unknown",
                requestedTenantCode);
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
            await WriteFailureAsync(
                context,
                StatusCodes.Status403Forbidden,
                "Tenant is not active.",
                $"Tenant '{tenantContext.TenantCode}' is not active.",
                "urn:xydatalabs:problem:tenant-not-active",
                requestedTenantCode);
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

    private static bool IsTenantOptionalRequest(PathString requestPath)
    {
        return IsRuntimeConfigurationRequest(requestPath)
            || IsHealthRequest(requestPath)
            || IsPaymentCallbackRequest(requestPath);
    }

    private static bool IsRuntimeConfigurationRequest(PathString requestPath)
    {
        return string.Equals(requestPath.Value, RuntimeConfigurationPath, StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsHealthRequest(PathString requestPath)
    {
        return string.Equals(requestPath.Value, HealthPath, StringComparison.OrdinalIgnoreCase)
            || string.Equals(requestPath.Value, HealthLivePath, StringComparison.OrdinalIgnoreCase)
            || string.Equals(requestPath.Value, HealthReadyPath, StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsPaymentCallbackRequest(PathString requestPath)
    {
        return string.Equals(requestPath.Value, PaymentCallbackPath, StringComparison.OrdinalIgnoreCase);
    }

    private static string ResolveOptionalTenantCode(HttpContext context)
    {
        if (IsHealthRequest(context.Request.Path))
        {
            return "infrastructure";
        }

        if (IsPaymentCallbackRequest(context.Request.Path))
        {
            var callbackTenantCode = context.Request.Query["tenantCode"].FirstOrDefault()?.Trim();
            return string.IsNullOrWhiteSpace(callbackTenantCode) ? "callback" : callbackTenantCode;
        }

        return "bootstrap";
    }

    private static async Task WriteFailureAsync(
        HttpContext context,
        int statusCode,
        string title,
        string detail,
        string type,
        string? requestedTenantCode)
    {
        context.Response.StatusCode = statusCode;
        context.Response.ContentType = "application/problem+json";

        var problemDetails = new ProblemDetails
        {
            Status = statusCode,
            Title = title,
            Detail = detail,
            Type = type,
            Instance = context.Request.Path
        };

        problemDetails.Extensions["traceId"] = context.TraceIdentifier;
        problemDetails.Extensions["tenantHeaderName"] = TenantHeaderName;

        if (!string.IsNullOrWhiteSpace(requestedTenantCode))
        {
            problemDetails.Extensions["requestedTenantCode"] = requestedTenantCode;
        }

        await context.Response.WriteAsJsonAsync(
            value: problemDetails,
            type: problemDetails.GetType(),
            options: null,
            contentType: "application/problem+json");
    }
}
