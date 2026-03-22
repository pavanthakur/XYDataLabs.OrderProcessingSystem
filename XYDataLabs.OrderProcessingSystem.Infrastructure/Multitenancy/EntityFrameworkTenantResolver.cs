using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Multitenancy;

public sealed class EntityFrameworkTenantResolver : ITenantResolver
{
    private readonly OrderProcessingSystemDbContext _dbContext;

    public EntityFrameworkTenantResolver(OrderProcessingSystemDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task<TenantContext?> ResolveTenantAsync(string tenantCode, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(tenantCode))
        {
            return null;
        }

        var tenant = await _dbContext.Tenants
            .AsNoTracking()
            .FirstOrDefaultAsync(item => item.Code == tenantCode.Trim(), cancellationToken);

        if (tenant is null)
        {
            return null;
        }

        return new TenantContext(
            tenant.Id,
            tenant.Code,
            tenant.ExternalId,
            tenant.Name,
            tenant.Status);
    }
}