using System.Security.Claims;
using Microsoft.AspNetCore.Http;

namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

public sealed class TenantClaimConsistencyMiddleware(RequestDelegate next)
{
    public const string TenantClaimType = "tenant_code";
    private const string RuntimeConfigurationPath = "/api/v1/info/runtime-configuration";
    private const string TenantRegistryPath = "/api/v1/info/tenant-registry";

    public async Task InvokeAsync(HttpContext context)
    {
        ArgumentNullException.ThrowIfNull(context);

        if (IsBootstrapDiscoveryRequest(context.Request.Path))
        {
            await next(context).ConfigureAwait(false);
            return;
        }

        if (context.User.Identity?.IsAuthenticated == true)
        {
            var requestedTenant = context.Request.Headers[TenantMiddleware.TenantHeaderName]
                .FirstOrDefault();

            // Infrastructure endpoints retain their existing authentication policy.
            if (context.Request.Path.StartsWithSegments("/health"))
            {
                await next(context).ConfigureAwait(false);
                return;
            }
            if (!TenantAccessPolicy.CanAccess(context.User, requestedTenant))
            {
                context.Response.StatusCode = StatusCodes.Status403Forbidden;
                await context.Response.WriteAsJsonAsync(new
                {
                    error = "The authenticated account is not authorized for the requested X-Tenant-Code."
                }).ConfigureAwait(false);
                return;
            }
            if (TenantAccessPolicy.IsPlatformAdmin(context.User))
            {
                try { await next(context).ConfigureAwait(false); }
                finally
                {
                    Serilog.Log.Information("Platform admin request Subject={Subject} Tenant={RequestedTenant} TraceId={TraceId} Status={Status}",
                        context.User.FindFirstValue(ClaimTypes.NameIdentifier) ?? context.User.FindFirstValue("sub"),
                        requestedTenant, context.TraceIdentifier, context.Response.StatusCode);
                }
                return;
            }
        }

        await next(context).ConfigureAwait(false);
    }

    private static bool IsBootstrapDiscoveryRequest(PathString requestPath)
    {
        return string.Equals(requestPath.Value, RuntimeConfigurationPath, StringComparison.OrdinalIgnoreCase)
            || string.Equals(requestPath.Value, TenantRegistryPath, StringComparison.OrdinalIgnoreCase);
    }
}
