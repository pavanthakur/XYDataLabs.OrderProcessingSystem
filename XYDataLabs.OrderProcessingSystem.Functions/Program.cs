using Azure.Messaging.ServiceBus;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Functions;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;

var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureAppConfiguration((context, builder) =>
    {
        builder
            .AddJsonFile("local.settings.json", optional: true, reloadOnChange: true)
            .AddEnvironmentVariables();
    })
    .ConfigureServices((context, services) =>
    {
        var serviceBusOptions = context.Configuration
            .GetSection(ServiceBusOptions.SectionName)
            .Get<ServiceBusOptions>() ?? new ServiceBusOptions();

        services.Configure<ServiceBusOptions>(context.Configuration.GetSection(ServiceBusOptions.SectionName));
        services.AddSingleton(TimeProvider.System);
        services.AddSingleton<IIntegrationEventTypeResolver, IntegrationEventTypeResolver>();
        services.AddSingleton<ServiceBusMessageFactory>();
        var operationsConnectionString = context.Configuration.GetConnectionString("OrderProcessingSystemDbConnection");
        if (!string.IsNullOrWhiteSpace(operationsConnectionString))
        {
            services.AddDbContext<OrderProcessingSystemDbContext>(options =>
                options.UseSqlServer(
                    operationsConnectionString,
                    sql => sql.EnableRetryOnFailure(5, TimeSpan.FromSeconds(30), null)));
        }
        if (serviceBusOptions.Enabled)
        {
            if (string.IsNullOrWhiteSpace(serviceBusOptions.ConnectionString))
            {
                throw new InvalidOperationException("ServiceBus:ConnectionString must be configured when ServiceBus:Enabled is true.");
            }

            services.AddSingleton(_ => new ServiceBusClient(serviceBusOptions.ConnectionString));
        }
        services.AddSingleton<Phase10FunctionStartupValidator>();
    })
    .Build();

host.Services.GetRequiredService<Phase10FunctionStartupValidator>().Validate();

await host.RunAsync();
