using System.Text.Json;
using FluentAssertions;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Options;
using XYDataLabs.OrderProcessingSystem.Functions;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

[Trait("Category", "InfrastructureIntegration")]
public sealed class Phase10LocalSetupContractTests
{
    [Fact]
    public void Docker_Compose_Should_Declare_Phase10_Profiles_Without_All_Profile()
    {
        var compose = ReadRepoFile("compose/docker-compose.phase10.yml");

        compose.Should().Contain("profiles: [\"data\"]");
        compose.Should().Contain("profiles: [\"identity\"]");
        compose.Should().Contain("profiles: [\"storage\"]");
        compose.Should().Contain("profiles: [\"messaging\"]");
        compose.Should().Contain("profiles: [\"apps\"]");
        compose.Should().Contain("profiles: [\"functions\"]");
        compose.Should().NotContain("\"all\"");
    }

    [Fact]
    public void Docker_Env_Example_Should_Expose_Local_Emulator_And_Webhook_Settings()
    {
        var envExample = ReadRepoFile("Resources/Docker/.env.local.example");

        var requiredKeys = new[]
        {
            "LOCAL_RAZORPAY_WEBHOOK_SECRET",
            "LOCAL_OPENPAY_WEBHOOK_SECRET",
            "LOCAL_AZURITE_CONNECTION_STRING",
            "LOCAL_SERVICEBUS_ENABLED",
            "LOCAL_SERVICEBUS_CONNECTION_STRING",
            "LOCAL_SERVICEBUS_TOPIC_NAME",
            "LOCAL_SERVICEBUS_INVENTORY_SUBSCRIPTION_NAME",
            "LOCAL_SERVICEBUS_NOTIFICATIONS_SUBSCRIPTION_NAME",
            "LOCAL_SERVICEBUS_DLQ_TOPIC_NAME",
            "LOCAL_SERVICEBUS_DLQ_SUBSCRIPTION_NAME",
            "SERVICEBUS_EMULATOR_SQL_PASSWORD"
        };

        foreach (var key in requiredKeys)
        {
            envExample.Should().Contain($"{key}=");
        }
    }

    [Fact]
    public void ServiceBus_Emulator_Config_Should_Mirror_Azure_Topology_Names()
    {
        using var document = JsonDocument.Parse(ReadRepoFile("Resources/ServiceBus/phase10-emulator-config.json"));
        var topics = document.RootElement
            .GetProperty("UserConfig")
            .GetProperty("Namespaces")[0]
            .GetProperty("Topics");

        topics.EnumerateArray().Select(topic => topic.GetProperty("Name").GetString()).Should().Contain(new[]
        {
            "order-events",
            "order-events-dlq"
        });

        var orderEventsTopic = topics.EnumerateArray().Single(topic => topic.GetProperty("Name").GetString() == "order-events");
        var orderSubscriptions = orderEventsTopic.GetProperty("Subscriptions").EnumerateArray()
            .Select(subscription => subscription.GetProperty("Name").GetString());

        orderSubscriptions.Should().Contain(new[]
        {
            "inventory-order-created",
            "notifications-order-created"
        });

        var dlqTopic = topics.EnumerateArray().Single(topic => topic.GetProperty("Name").GetString() == "order-events-dlq");
        var dlqSubscriptions = dlqTopic.GetProperty("Subscriptions").EnumerateArray()
            .Select(subscription => subscription.GetProperty("Name").GetString());

        dlqSubscriptions.Should().Contain("dlq-replay");
    }

    [Fact]
    public void Functions_Startup_Validator_Should_Allow_Disabled_ServiceBus_With_Azurite_Config()
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["AzureWebJobsStorage"] = "UseDevelopmentStorage=true",
                ["ServiceBus:Enabled"] = "false"
            })
            .Build();

        var options = Options.Create(new ServiceBusOptions
        {
            Enabled = false
        });

        var validator = new Phase10FunctionStartupValidator(configuration, options);

        validator.Invoking(subject => subject.Validate()).Should().NotThrow();
    }

    [Fact]
    public void Functions_Startup_Validator_Should_Require_Trigger_Connection_When_ServiceBus_Is_Enabled()
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["AzureWebJobsStorage"] = "UseDevelopmentStorage=true",
                ["ServiceBus:Enabled"] = "true",
                ["ServiceBus:ConnectionString"] = "Endpoint=sb://localhost;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=SAS_KEY_VALUE;UseDevelopmentEmulator=true;"
            })
            .Build();

        var options = Options.Create(new ServiceBusOptions
        {
            Enabled = true,
            ConnectionString = "Endpoint=sb://localhost;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=SAS_KEY_VALUE;UseDevelopmentEmulator=true;"
        });

        var validator = new Phase10FunctionStartupValidator(configuration, options);

        validator.Invoking(subject => subject.Validate())
            .Should()
            .Throw<InvalidOperationException>()
            .WithMessage("ServiceBusConnection must be configured when Service Bus triggers are enabled.");
    }

    private static string ReadRepoFile(string relativePath)
    {
        var current = new DirectoryInfo(AppContext.BaseDirectory);
        while (current is not null)
        {
            var candidate = Path.Combine(current.FullName, relativePath);
            if (File.Exists(candidate))
            {
                return File.ReadAllText(candidate);
            }

            current = current.Parent;
        }

        throw new FileNotFoundException($"Could not find repository file '{relativePath}' from '{AppContext.BaseDirectory}'.");
    }
}
