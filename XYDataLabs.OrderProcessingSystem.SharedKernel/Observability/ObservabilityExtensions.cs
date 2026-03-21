using Azure.Monitor.OpenTelemetry.Exporter;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Observability;

public static class ObservabilityExtensions
{
    public static IServiceCollection AddObservability(
        this IServiceCollection services,
        string serviceName,
        IConfiguration configuration,
        params string[] activitySourceNames)
    {
        var resourceBuilder = ResourceBuilder.CreateDefault()
            .AddService(serviceName);

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

                // Azure Monitor exporter (App Insights)
                var appInsightsConnStr = configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"]
                    ?? Environment.GetEnvironmentVariable("APPLICATIONINSIGHTS_CONNECTION_STRING");

                if (!string.IsNullOrWhiteSpace(appInsightsConnStr))
                {
                    tracing.AddAzureMonitorTraceExporter(o => o.ConnectionString = appInsightsConnStr);
                }

                // OTLP exporter (Jaeger, Aspire Dashboard, etc.) — conditional
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
                    .AddAspNetCoreInstrumentation()
                    .AddHttpClientInstrumentation()
                    .AddRuntimeInstrumentation();

                // Azure Monitor metrics exporter
                var appInsightsConnStr = configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"]
                    ?? Environment.GetEnvironmentVariable("APPLICATIONINSIGHTS_CONNECTION_STRING");

                if (!string.IsNullOrWhiteSpace(appInsightsConnStr))
                {
                    metrics.AddAzureMonitorMetricExporter(o => o.ConnectionString = appInsightsConnStr);
                }

                // OTLP metrics exporter — conditional
                var otlpEndpoint = Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_ENDPOINT");
                if (!string.IsNullOrWhiteSpace(otlpEndpoint))
                {
                    metrics.AddOtlpExporter(o => o.Endpoint = new Uri(otlpEndpoint));
                }
            });

        return services;
    }
}
