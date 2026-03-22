using Microsoft.AspNetCore.Http;

namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

/// <summary>
/// Reads the current tenant context from HttpContext.Items, set by TenantMiddleware.
/// </summary>
public sealed class HeaderTenantProvider : ITenantProvider
{
    private readonly IHttpContextAccessor _httpContextAccessor;

    public HeaderTenantProvider(IHttpContextAccessor httpContextAccessor)
    {
        _httpContextAccessor = httpContextAccessor;
    }

    public bool HasTenantContext => ResolveTenantContext() is not null;

    public int TenantId => ResolveTenantContext()?.TenantId ?? 0;

    public string TenantCode => ResolveTenantContext()?.TenantCode ?? string.Empty;

    public string TenantExternalId => ResolveTenantContext()?.TenantExternalId ?? string.Empty;

    private TenantContext? ResolveTenantContext()
    {
        var context = _httpContextAccessor.HttpContext;
        if (context?.Items.TryGetValue(TenantMiddleware.HttpContextItemKey, out var tenantObj) == true
            && tenantObj is TenantContext tenantContext)
        {
            return tenantContext;
        }

        return null;
    }
}
