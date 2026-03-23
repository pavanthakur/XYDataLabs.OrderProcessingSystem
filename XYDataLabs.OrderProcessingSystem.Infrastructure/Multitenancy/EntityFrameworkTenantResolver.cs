using Microsoft.EntityFrameworkCore;
using Serilog;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Multitenancy;

public sealed class EntityFrameworkTenantResolver : ITenantResolver
{
    private readonly TenantRegistryDbContext _registryContext;

    public EntityFrameworkTenantResolver(TenantRegistryDbContext registryContext)
    {
        _registryContext = registryContext;
    }

    public async Task<TenantContext?> ResolveTenantAsync(string tenantCode, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(tenantCode))
        {
            return null;
        }

        var tenant = await _registryContext.Tenants
            .AsNoTracking()
            .FirstOrDefaultAsync(t => t.Code == tenantCode.Trim(), cancellationToken);

        if (tenant is null)
        {
            return null;
        }

        var isSharedPool = string.Equals(tenant.TenantTier, TenantTierConstants.SharedPool, StringComparison.Ordinal);

        // Fail-safe: dedicated tenant without provisioned DB must not silently route to shared pool
        if (!isSharedPool && string.IsNullOrWhiteSpace(tenant.ConnectionString))
        {
            Log.Error(
                "Tenant {TenantCode} is classified as {TenantTier} but has no ConnectionString configured. " +
                "Returning null to prevent routing to the shared pool database",
                tenantCode,
                tenant.TenantTier);
            return null;
        }

        return new TenantContext(
            tenant.Id,
            tenant.Code,
            tenant.ExternalId,
            tenant.Name,
            tenant.Status,
            isSharedPool ? null : tenant.ConnectionString,
            isSharedPool);
    }
}