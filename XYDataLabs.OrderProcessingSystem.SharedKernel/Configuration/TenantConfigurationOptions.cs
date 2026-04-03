namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Configuration;

public sealed class TenantConfigurationOptions
{
    public const string SectionName = "TenantConfiguration";

    public string ActiveTenantCode { get; set; } = string.Empty;

    public bool UiSelectorEnabled { get; set; } = true;

    public bool UiTenantOverrideEnabled { get; set; } = true;

    public bool SwaggerSelectorEnabled { get; set; } = true;
}