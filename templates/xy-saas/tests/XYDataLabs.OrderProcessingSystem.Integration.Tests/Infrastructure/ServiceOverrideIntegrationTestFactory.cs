using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.DependencyInjection;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;

internal sealed class ServiceOverrideIntegrationTestFactory(
    string connectionString,
    Action<IServiceCollection> configureServices,
    bool enableBackgroundWorkers = false,
    string? dedicatedConnectionString = null)
    : IntegrationTestWebAppFactory(connectionString, dedicatedConnectionString, enableBackgroundWorkers)
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        base.ConfigureWebHost(builder);
        builder.ConfigureServices(configureServices);
    }
}