using Microsoft.AspNetCore.Http;

namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

/// <summary>
/// Reads the current tenant from HttpContext.Items, set by TenantMiddleware.
/// Falls back to "default" when no HttpContext is available (e.g. background services, seed data).
/// </summary>
public sealed class HeaderTenantProvider : ITenantProvider
{
    private readonly IHttpContextAccessor _httpContextAccessor;

    public HeaderTenantProvider(IHttpContextAccessor httpContextAccessor)
    {
        _httpContextAccessor = httpContextAccessor;
    }

    public string TenantId
    {
        get
        {
            var context = _httpContextAccessor.HttpContext;
            if (context?.Items.TryGetValue(TenantMiddleware.HttpContextItemKey, out var tenantObj) == true
                && tenantObj is string tenant
                && !string.IsNullOrWhiteSpace(tenant))
            {
                return tenant;
            }

            return TenantMiddleware.DefaultTenantId;
        }
    }
}
