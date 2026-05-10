namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Configuration;

public sealed class ObservabilityOptions
{
    public const string SectionName = "Observability";

    public bool EnableEfSensitiveDataLogging { get; set; }
}