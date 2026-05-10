namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

/// <summary>
/// Scoped ambient tenant context for non-request execution paths such as hosted workers.
/// Request paths still flow through TenantMiddleware and HttpContext.
/// </summary>
public sealed class ScopedTenantContextAccessor
{
    public TenantContext? Current { get; set; }
}