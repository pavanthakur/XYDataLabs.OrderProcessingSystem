using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Multitenancy;

public sealed class TenantRegistryService : ITenantRegistry
{
    private const string ActiveTenantStatus = "Active";
    private readonly TenantRegistryDbContext _registryContext;

    public TenantRegistryService(TenantRegistryDbContext registryContext)
    {
        _registryContext = registryContext;
    }

    public async Task<IReadOnlyList<TenantInfo>> GetActiveTenantsAsync(CancellationToken cancellationToken = default)
    {
        return await _registryContext.Tenants
            .AsNoTracking()
            .Where(t => t.Status == ActiveTenantStatus)
            .OrderBy(t => t.Name)
            .ThenBy(t => t.Code)
            .Select(t => new TenantInfo(t.Id, t.Code, t.Name))
            .ToListAsync(cancellationToken);
    }
}
