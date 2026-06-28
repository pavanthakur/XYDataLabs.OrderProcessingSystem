namespace XYDataLabs.OrderProcessingSystem.Tenants.API;

public interface ITenantRegistryApi
{
    string? GetPaymentProviderCode(string tenantCode);
}

