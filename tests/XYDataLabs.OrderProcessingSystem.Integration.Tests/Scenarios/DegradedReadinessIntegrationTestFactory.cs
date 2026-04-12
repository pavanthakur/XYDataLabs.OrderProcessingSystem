using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

internal sealed class DegradedReadinessIntegrationTestFactory(string connectionString)
    : IntegrationTestWebAppFactory(connectionString)
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        base.ConfigureWebHost(builder);

        builder.ConfigureServices(services =>
        {
            services.AddHealthChecks()
                .AddCheck(
                    "synthetic-degraded-ready-check",
                    () => HealthCheckResult.Degraded("Synthetic degraded dependency for readiness probe verification."),
                    tags: new[] { "ready" });
        });
    }
}