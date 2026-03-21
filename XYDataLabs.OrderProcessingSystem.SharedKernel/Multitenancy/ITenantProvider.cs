namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

/// <summary>
/// Provides the current tenant identifier for multi-tenancy isolation.
/// Implemented by HeaderTenantProvider (reads X-Tenant-Id header via HttpContext).
/// Lives in SharedKernel so all layers can depend on it without circular references.
/// </summary>
public interface ITenantProvider
{
    string TenantId { get; }
}
