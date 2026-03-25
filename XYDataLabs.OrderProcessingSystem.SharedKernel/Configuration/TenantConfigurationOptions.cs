namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Configuration;

public sealed class TenantConfigurationOptions
{
    public const string SectionName = "TenantConfiguration";

    public string ActiveTenantCode { get; set; } = string.Empty;
}