namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

/// <summary>
/// Canonical tenant tier values. Used in Tenant.TenantTier and resolution logic.
/// </summary>
public static class TenantTierConstants
{
    public const string SharedPool = "SharedPool";
    public const string Dedicated  = "Dedicated";
}
