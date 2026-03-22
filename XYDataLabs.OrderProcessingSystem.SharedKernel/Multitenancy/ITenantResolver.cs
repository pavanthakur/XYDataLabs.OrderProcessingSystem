namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

public interface ITenantResolver
{
    Task<TenantContext?> ResolveTenantAsync(string tenantCode, CancellationToken cancellationToken = default);
}