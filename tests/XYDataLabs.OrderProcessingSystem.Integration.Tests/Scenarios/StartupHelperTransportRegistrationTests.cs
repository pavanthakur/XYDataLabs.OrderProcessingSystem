using FluentAssertions;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Infrastructure;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Events;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

public sealed class StartupHelperTransportRegistrationTests
{
    [Fact]
    public async Task InjectInfrastructureDependencies_Should_Register_ServiceBusPublisher_When_Transport_Is_Enabled()
    {
        await using var provider = BuildServiceProvider(
            serviceBusEnabled: true,
            serviceBusConnectionString: "Endpoint=sb://localhost/;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");

        provider.GetRequiredService<IEventPublisher>().Should().BeOfType<ServiceBusEventPublisher>();
    }

    [Fact]
    public async Task InjectInfrastructureDependencies_Should_Register_InMemoryPublisher_When_Transport_Is_Disabled()
    {
        await using var provider = BuildServiceProvider(serviceBusEnabled: false, serviceBusConnectionString: string.Empty);

        provider.GetRequiredService<IEventPublisher>().Should().BeOfType<InMemoryEventPublisher>();
    }

    private static ServiceProvider BuildServiceProvider(bool serviceBusEnabled, string serviceBusConnectionString)
    {
        var builder = Host.CreateApplicationBuilder();

        builder.Configuration.AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["ConnectionStrings:OrderProcessingSystemDbConnection"] = "Server=(localdb)\\MSSQLLocalDB;Database=OrderProcessingSystem.Tests;Trusted_Connection=True;TrustServerCertificate=True",
            ["ConnectionStrings:TenantRegistryDbConnection"] = "Server=(localdb)\\MSSQLLocalDB;Database=OrderProcessingSystem.Tests;Trusted_Connection=True;TrustServerCertificate=True",
            ["ConnectionStrings:Redis"] = string.Empty,
            [$"{ServiceBusOptions.SectionName}:Enabled"] = serviceBusEnabled.ToString(),
            [$"{ServiceBusOptions.SectionName}:ConnectionString"] = serviceBusConnectionString,
            [$"{ServiceBusOptions.SectionName}:TopicName"] = "order-events",
            [$"{ServiceBusOptions.SectionName}:DeadLetterTopicName"] = "order-events-dlq",
            [$"{ServiceBusOptions.SectionName}:DeadLetterSubscriptionName"] = "dlq-replay",
            [$"{ServiceBusOptions.SectionName}:ReplayEnabled"] = "true"
        });

        builder.InjectInfrastructureDependencies();
        return builder.Services.BuildServiceProvider();
    }
}
