using Microsoft.AspNetCore.Http;

namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

/// <summary>
/// Reads the current tenant context from HttpContext.Items, set by TenantMiddleware.
/// </summary>
public sealed class HeaderTenantProvider : ITenantProvider
{
    private readonly IHttpContextAccessor _httpContextAccessor;
    private readonly ScopedTenantContextAccessor _tenantContextAccessor;

    public HeaderTenantProvider(IHttpContextAccessor httpContextAccessor, ScopedTenantContextAccessor tenantContextAccessor)
    {
        _httpContextAccessor = httpContextAccessor;
        _tenantContextAccessor = tenantContextAccessor;
    }

    public bool HasTenantContext => ResolveTenantContext() is not null;

    public int TenantId => ResolveTenantContext()?.TenantId ?? 0;

    public string TenantCode => ResolveTenantContext()?.TenantCode ?? string.Empty;

    public string TenantExternalId => ResolveTenantContext()?.TenantExternalId ?? string.Empty;

    public string? ConnectionString => ResolveTenantContext()?.ConnectionString;

    public bool IsSharedPool => ResolveTenantContext()?.IsSharedPool ?? true;

    private TenantContext? ResolveTenantContext()
    {
        if (_tenantContextAccessor.Current is not null)
        {
            return _tenantContextAccessor.Current;
        }

        var context = _httpContextAccessor.HttpContext;
        if (context?.Items.TryGetValue(TenantMiddleware.HttpContextItemKey, out var tenantObj) == true
            && tenantObj is TenantContext tenantContext)
        {
            return tenantContext;
        }

        return null;
    }
}
