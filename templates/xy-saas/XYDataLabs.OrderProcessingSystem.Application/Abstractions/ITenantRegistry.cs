namespace XYDataLabs.OrderProcessingSystem.Application.Abstractions;

/// <summary>
/// Read-only tenant registry for bootstrap/admin endpoints that need tenant data
/// without going through the tenant-scoped business DbContext.
/// Implemented by Infrastructure via TenantRegistryDbContext.
/// </summary>
public interface ITenantRegistry
{
    Task<IReadOnlyList<TenantInfo>> GetActiveTenantsAsync(CancellationToken cancellationToken = default);
}

public sealed record TenantInfo(int TenantId, string TenantCode, string TenantName);
