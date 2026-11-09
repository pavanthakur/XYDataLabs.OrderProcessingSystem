using System.Security.Claims;

namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

/// <summary>Authorization is based on the validated principal, never on display names or directory IDs.</summary>
public static class TenantAccessPolicy
{
    public const string PlatformAdminRole = "platform-admin";
    public const string TenantClaimType = "tenant_code";

    public static bool IsPlatformAdmin(ClaimsPrincipal? user) =>
        user?.Identity?.IsAuthenticated == true && user.IsInRole(PlatformAdminRole);

    public static string? AssignedTenant(ClaimsPrincipal? user) =>
        user?.FindFirstValue(TenantClaimType)?.Trim() ?? user?.FindFirstValue("tenant")?.Trim();

    public static bool CanAccess(ClaimsPrincipal? user, string? tenantCode) =>
        user?.Identity?.IsAuthenticated == true
        && !string.IsNullOrWhiteSpace(tenantCode)
        && (IsPlatformAdmin(user) || (!string.IsNullOrWhiteSpace(AssignedTenant(user))
            && string.Equals(AssignedTenant(user), tenantCode.Trim(), StringComparison.OrdinalIgnoreCase)));

    // Anonymous discovery is retained for the existing topology contract only.
    public static bool CanDiscover(ClaimsPrincipal? user, string tenantCode) =>
        user?.Identity?.IsAuthenticated != true || CanAccess(user, tenantCode);
}
