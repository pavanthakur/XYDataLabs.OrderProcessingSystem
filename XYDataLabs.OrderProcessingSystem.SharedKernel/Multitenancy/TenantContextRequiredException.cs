namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

public sealed class TenantContextRequiredException : InvalidOperationException
{
    public TenantContextRequiredException(string requestName)
        : base($"Tenant context is required for request '{requestName}'.")
    {
        RequestName = requestName;
    }

    public string RequestName { get; }
}