namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

public sealed record TenantContext(
    int TenantId,
    string TenantCode,
    string TenantExternalId,
    string TenantName,
    string TenantStatus);