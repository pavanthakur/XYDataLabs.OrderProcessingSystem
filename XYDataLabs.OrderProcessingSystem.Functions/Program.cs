using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using XYDataLabs.OrderProcessingSystem.Functions;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

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
        services.Configure<ServiceBusOptions>(context.Configuration.GetSection(ServiceBusOptions.SectionName));
        services.AddSingleton<Phase10FunctionStartupValidator>();
    })
    .Build();

host.Services.GetRequiredService<Phase10FunctionStartupValidator>().Validate();

await host.RunAsync();
