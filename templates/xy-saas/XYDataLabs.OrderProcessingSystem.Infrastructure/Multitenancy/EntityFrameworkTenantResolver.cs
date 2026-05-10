using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Serilog;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Multitenancy;

public sealed class EntityFrameworkTenantResolver : ITenantResolver
{
    private readonly TenantRegistryDbContext _registryContext;
    private readonly IConfiguration _configuration;

    public EntityFrameworkTenantResolver(TenantRegistryDbContext registryContext, IConfiguration configuration)
    {
        _registryContext = registryContext;
        _configuration = configuration;
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

        // Dedicated tenants: resolve connection string from configuration (Key Vault / appsettings),
        // never from the Tenants table. Connection strings are secrets that must not be stored
        // in application data tables.
        string? connectionString = null;
        if (!isSharedPool)
        {
            connectionString = _configuration[$"DedicatedTenantConnectionStrings:{tenant.Code}"];
            if (string.IsNullOrWhiteSpace(connectionString))
            {
                Log.Error(
                    "Tenant {TenantCode} is classified as {TenantTier} but has no ConnectionString in " +
                    "DedicatedTenantConnectionStrings configuration. Returning null to prevent routing " +
                    "to the shared pool database",
                    tenantCode,
                    tenant.TenantTier);
                return null;
            }
        }

        return new TenantContext(
            tenant.Id,
            tenant.Code,
            tenant.ExternalId,
            tenant.Name,
            tenant.Status,
            connectionString,
            isSharedPool);
    }
}