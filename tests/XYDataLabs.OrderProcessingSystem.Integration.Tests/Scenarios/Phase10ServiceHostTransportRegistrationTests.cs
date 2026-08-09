using FluentAssertions;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;
using XYDataLabs.OrderProcessingSystem.Payments.Contracts.Events;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

public sealed class Phase10ServiceHostTransportRegistrationTests
{
    [Fact]
    public void Phase10HostInfrastructure_Should_Register_Orders_PaymentState_Subscription_Explicitly()
    {
        using var provider = BuildServiceProvider("Orders");

        var subscription = provider.GetRequiredService<ServiceBusConsumerSubscription>();

        subscription.ConsumerKind.Should().Be("Orders");
        subscription.SubscriptionName.Should().Be("orders-payment-state");
        subscription.EventPayloadTypes.Keys.Should().BeEquivalentTo(
            nameof(PaymentAttemptSucceededV1),
            nameof(PaymentAttemptFailedV1));
    }

    [Fact]
    public void Phase10HostInfrastructure_Should_Register_Inventory_OrderCreated_Subscription_Explicitly()
    {
        using var provider = BuildServiceProvider("Inventory");

        var subscription = provider.GetRequiredService<ServiceBusConsumerSubscription>();

        subscription.ConsumerKind.Should().Be("Inventory");
        subscription.SubscriptionName.Should().Be("order-created");
        subscription.EventPayloadTypes.Keys.Should().BeEquivalentTo("OrderCreatedV1");
    }

    [Fact]
    public void Phase10HostInfrastructure_Should_Register_A_Reusable_Consumer_Message_Processor()
    {
        using var provider = BuildServiceProvider("Notifications");

        var processor = provider.GetRequiredService<IServiceBusConsumerMessageProcessor>();

        processor.Should().BeOfType<ServiceBusConsumerMessageProcessor>();
    }

    [Fact]
    public void Phase10HostInfrastructure_Should_Parse_Iso8601_MessageTtl_From_Configuration()
    {
        using var provider = BuildServiceProvider("Orders");

        var options = provider.GetRequiredService<IOptions<ServiceBusOptions>>().Value;

        options.MessageTtl.Should().Be("P7D");
        options.MessageTtlTimeSpan.Should().Be(TimeSpan.FromDays(7));
    }

    private static ServiceProvider BuildServiceProvider(string consumerKind)
    {
        var builder = Host.CreateApplicationBuilder();

        builder.Configuration.AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["ConnectionStrings:OrderProcessingSystemDbConnection"] = "Server=(localdb)\\MSSQLLocalDB;Database=OrderProcessingSystem.Tests;Trusted_Connection=True;TrustServerCertificate=True",
            ["ConnectionStrings:TenantRegistryDbConnection"] = "Server=(localdb)\\MSSQLLocalDB;Database=OrderProcessingSystem.Tests;Trusted_Connection=True;TrustServerCertificate=True",
            [$"{ServiceBusOptions.SectionName}:Enabled"] = "true",
            [$"{ServiceBusOptions.SectionName}:ConnectionString"] = "Endpoint=sb://localhost/;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            [$"{ServiceBusOptions.SectionName}:TopicName"] = "order-events",
            [$"{ServiceBusOptions.SectionName}:SubscriptionName"] = "order-created",
            [$"{ServiceBusOptions.SectionName}:PaymentStateSubscriptionName"] = "orders-payment-state",
            [$"{ServiceBusOptions.SectionName}:DeadLetterTopicName"] = "order-events-dlq",
            [$"{ServiceBusOptions.SectionName}:DeadLetterSubscriptionName"] = "dlq-intake",
            [$"{ServiceBusOptions.SectionName}:MessageTtl"] = "P7D"
        });

        builder.AddPhase10ServiceHostInfrastructure(consumerKind: consumerKind);
        return builder.Services.BuildServiceProvider();
    }
}
