using Microsoft.Extensions.Configuration;

namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Configuration;

public sealed class ApplicationInsightsOptions
{
    public const string ConfigurationKey = "APPLICATIONINSIGHTS_CONNECTION_STRING";

    public string? ConnectionString { get; set; }

    public static ApplicationInsightsOptions FromConfiguration(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        return new ApplicationInsightsOptions
        {
            ConnectionString = configuration[ConfigurationKey]?.Trim()
        };
    }
}