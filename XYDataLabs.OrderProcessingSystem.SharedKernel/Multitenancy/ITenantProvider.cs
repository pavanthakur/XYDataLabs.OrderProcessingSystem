namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

/// <summary>
/// Provides the current resolved tenant context for multi-tenancy isolation.
/// </summary>
public interface ITenantProvider
{
    bool HasTenantContext { get; }

    int TenantId { get; }

    string TenantCode { get; }

    string TenantExternalId { get; }
}
