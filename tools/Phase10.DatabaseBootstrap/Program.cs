using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.Infrastructure.SeedData;
using XYDataLabs.OrderProcessingSystem.Inventory.Features.Module;
using XYDataLabs.OrderProcessingSystem.Notifications.Features.Module;
using XYDataLabs.OrderProcessingSystem.Orders.Features.Module;
using XYDataLabs.OrderProcessingSystem.Payments.Features.Module;
using XYDataLabs.OrderProcessingSystem.SharedKernel;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Configuration;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.Phase10.DatabaseBootstrap;

internal static class Program
{
    public static void Main()
    {
        var environmentName = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "Development";
        var configurationBuilder = new ConfigurationBuilder();
        configurationBuilder.LoadSharedSettings(environmentName, isDocker: false);
        var configuration = configurationBuilder.Build();

        var sharedConnectionString = configuration.GetConnectionString(Constants.Configuration.OrderProcessingSystemDbConnectionString);
        if (string.IsNullOrWhiteSpace(sharedConnectionString))
        {
            throw new InvalidOperationException(
                $"ConnectionStrings:{Constants.Configuration.OrderProcessingSystemDbConnectionString} is required for database bootstrap.");
        }

        var services = new ServiceCollection();
        services.AddLogging();
        services.AddCqrs(typeof(OrdersModuleRegistration).Assembly);
        services.AddCqrs(typeof(InventoryModuleRegistration).Assembly);
        services.AddCqrs(typeof(NotificationsModuleRegistration).Assembly);
        services.AddCqrs(typeof(PaymentsModuleRegistration).Assembly);

        using var serviceProvider = services.BuildServiceProvider();
        var mapperRegistry = serviceProvider.GetRequiredService<IIntegrationEventMapperRegistry>();
        var bootstrapTenantProvider = new BootstrapTenantProvider();

        var options = new DbContextOptionsBuilder<OrderProcessingSystemDbContext>()
            .UseSqlServer(
                sharedConnectionString,
                sqlOptions => sqlOptions.EnableRetryOnFailure(
                        maxRetryCount: 5,
                        maxRetryDelay: TimeSpan.FromSeconds(30),
                        errorNumbersToAdd: null)
                    .CommandTimeout(180))
            .Options;

        using var dbContext = new OrderProcessingSystemDbContext(options, bootstrapTenantProvider, mapperRegistry);

        Console.WriteLine($"[bootstrap] environment={environmentName}");
        Console.WriteLine("[bootstrap] applying shared and dedicated tenant migrations plus idempotent local seed data...");

        DbInitializer.InitializeSharedPool(dbContext, configuration, applyMigrations: true);
        DbInitializer.InitializeDedicatedTenants(
            dbContext,
            configuration,
            applyMigrations: true,
            integrationEventMapperRegistry: mapperRegistry);

        Console.WriteLine("[bootstrap] bootstrap completed successfully.");
    }

    private sealed class BootstrapTenantProvider : ITenantProvider
    {
        public bool HasTenantContext => false;

        public int TenantId => 0;

        public string TenantCode => string.Empty;

        public string TenantExternalId => string.Empty;

        public string? ConnectionString => null;

        public bool IsSharedPool => true;
    }
}
