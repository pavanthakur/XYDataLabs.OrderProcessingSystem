using System.Security.Claims;
using Microsoft.AspNetCore.Http;

namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

public sealed class TenantClaimConsistencyMiddleware(RequestDelegate next)
{
    public const string TenantClaimType = "tenant_code";
    private const string RuntimeConfigurationPath = "/api/v1/info/runtime-configuration";

    public async Task InvokeAsync(HttpContext context)
    {
        ArgumentNullException.ThrowIfNull(context);

        if (IsRuntimeConfigurationRequest(context.Request.Path))
        {
            await next(context).ConfigureAwait(false);
            return;
        }

        if (context.User.Identity?.IsAuthenticated == true)
        {
            var tenantClaim = context.User.FindFirstValue(TenantClaimType)
                ?? context.User.FindFirstValue("tenant");
            var requestedTenant = context.Request.Headers[TenantMiddleware.TenantHeaderName]
                .FirstOrDefault();

            if (string.IsNullOrWhiteSpace(tenantClaim)
                || string.IsNullOrWhiteSpace(requestedTenant)
                || !string.Equals(
                    tenantClaim.Trim(),
                    requestedTenant.Trim(),
                    StringComparison.OrdinalIgnoreCase))
            {
                context.Response.StatusCode = StatusCodes.Status403Forbidden;
                await context.Response.WriteAsJsonAsync(new
                {
                    error = "The authenticated tenant claim must match X-Tenant-Code."
                }).ConfigureAwait(false);
                return;
            }
        }

        await next(context).ConfigureAwait(false);
    }

    private static bool IsRuntimeConfigurationRequest(PathString requestPath)
    {
        return string.Equals(requestPath.Value, RuntimeConfigurationPath, StringComparison.OrdinalIgnoreCase);
    }
}
