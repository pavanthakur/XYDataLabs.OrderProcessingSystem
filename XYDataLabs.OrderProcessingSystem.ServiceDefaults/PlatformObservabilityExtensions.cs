using Azure.Monitor.OpenTelemetry.Exporter;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

namespace XYDataLabs.OrderProcessingSystem.ServiceDefaults;

internal static class PlatformObservabilityExtensions
{
    // Preserve the existing shared meter export name without taking a project dependency
    // on SharedKernel for host-level observability bootstrap.
    private const string SharedBusinessMeterName = "OrderProcessing.Business";
    private const string ApplicationInsightsConnectionStringKey = "APPLICATIONINSIGHTS_CONNECTION_STRING";

    public static IServiceCollection AddPlatformObservability(
        this IServiceCollection services,
        string serviceName,
        IConfiguration configuration,
        params string[] activitySourceNames)
    {
        ArgumentNullException.ThrowIfNull(services);
        ArgumentNullException.ThrowIfNull(configuration);

        var resourceBuilder = ResourceBuilder.CreateDefault()
            .AddService(serviceName);
        var appInsightsConnectionString = configuration[ApplicationInsightsConnectionStringKey]?.Trim();

        services.AddOpenTelemetry()
            .ConfigureResource(r => r.AddService(serviceName))
            .WithTracing(tracing =>
            {
                tracing
                    .SetResourceBuilder(resourceBuilder)
                    .AddAspNetCoreInstrumentation()
                    .AddHttpClientInstrumentation()
                    .AddSqlClientInstrumentation(o => o.SetDbStatementForText = true);

                foreach (var sourceName in activitySourceNames)
                {
                    tracing.AddSource(sourceName);
                }

                if (!string.IsNullOrWhiteSpace(appInsightsConnectionString))
                {
                    tracing.AddAzureMonitorTraceExporter(o => o.ConnectionString = appInsightsConnectionString);
                }

                var otlpEndpoint = Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_ENDPOINT");
                if (!string.IsNullOrWhiteSpace(otlpEndpoint))
                {
                    tracing.AddOtlpExporter(o => o.Endpoint = new Uri(otlpEndpoint));
                }
            })
            .WithMetrics(metrics =>
            {
                metrics
                    .SetResourceBuilder(resourceBuilder)
                    .AddMeter(SharedBusinessMeterName)
                    .AddAspNetCoreInstrumentation()
                    .AddHttpClientInstrumentation()
                    .AddRuntimeInstrumentation();

                if (!string.IsNullOrWhiteSpace(appInsightsConnectionString))
                {
                    metrics.AddAzureMonitorMetricExporter(o => o.ConnectionString = appInsightsConnectionString);
                }

                var otlpEndpoint = Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_ENDPOINT");
                if (!string.IsNullOrWhiteSpace(otlpEndpoint))
                {
                    metrics.AddOtlpExporter(o => o.Endpoint = new Uri(otlpEndpoint));
                }
            });

        return services;
    }
}
