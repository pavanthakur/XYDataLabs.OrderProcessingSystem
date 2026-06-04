namespace XYDataLabs.OrderProcessingSystem.Application.Abstractions;

/// <summary>
/// Read-only tenant registry for bootstrap/admin endpoints that need tenant data
/// without going through the tenant-scoped business DbContext.
/// Implemented by Infrastructure via TenantRegistryDbContext.
/// </summary>
public interface ITenantRegistry
{
    /// <summary>
    /// Returns all active tenants. Used by admin/info endpoints.
    /// </summary>
    Task<IReadOnlyList<TenantInfo>> GetActiveTenantsAsync(CancellationToken cancellationToken = default);

    /// <summary>
    /// Returns the registry entry for the given tenant code, or null if not found.
    /// Synchronous — safe for use in constructor-time or synchronous resolver paths.
    /// Note: does not filter by tenant Status — the caller is responsible for status
    /// enforcement (middleware enforces 403 for Suspended/Decommissioned on request paths).
    /// </summary>
    TenantRegistryEntry? FindByCode(string tenantCode);

    /// <summary>
    /// Returns the registry entry for the given tenant code, or null if not found.
    /// Note: does not filter by tenant Status — the caller is responsible for status
    /// enforcement (middleware enforces 403 for Suspended/Decommissioned on request paths).
    /// </summary>
    Task<TenantRegistryEntry?> FindByCodeAsync(string tenantCode, CancellationToken cancellationToken = default);
}

/// <summary>
/// Lightweight tenant summary used by admin/info endpoints (backward-compatible).
/// </summary>
public sealed record TenantInfo(int TenantId, string TenantCode, string TenantName);

/// <summary>
/// Full registry entry used by payment routing and provider resolution.
/// PaymentProviderCode is the authoritative source for which provider a tenant uses.
/// </summary>
public sealed record TenantRegistryEntry(
    int TenantId,
    string TenantCode,
    string TenantName,
    string TenantTier,
    string? PaymentProviderCode);
