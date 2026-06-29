using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Hosting;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Observability;

namespace XYDataLabs.OrderProcessingSystem.ServiceDefaults;

public static class ServiceDefaultsExtensions
{
    public static IHostApplicationBuilder AddServiceDefaults(
        this IHostApplicationBuilder builder,
        string serviceName,
        params string[] activitySourceNames)
    {
        ArgumentNullException.ThrowIfNull(builder);

        builder.Services.AddProblemDetails();
        builder.Services.AddHealthChecks();
        builder.Services.AddObservability(serviceName, builder.Configuration, activitySourceNames);

        builder.Services.AddHttpClient();
        return builder;
    }

    public static WebApplication MapDefaultEndpoints(this WebApplication app)
    {
        ArgumentNullException.ThrowIfNull(app);

        app.MapHealthChecks("/health/alive", new HealthCheckOptions
        {
            Predicate = _ => false
        });

        app.MapHealthChecks("/health/ready", new HealthCheckOptions
        {
            Predicate = check => check.Tags.Contains("ready", StringComparer.OrdinalIgnoreCase)
        });

        return app;
    }
}
