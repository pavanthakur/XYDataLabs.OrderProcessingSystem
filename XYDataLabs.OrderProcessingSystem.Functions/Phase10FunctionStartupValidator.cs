using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Options;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

namespace XYDataLabs.OrderProcessingSystem.Functions;

public sealed class Phase10FunctionStartupValidator(
    IConfiguration configuration,
    IOptions<ServiceBusOptions> serviceBusOptions)
{
    public void Validate()
    {
        var storageConnectionString = configuration["AzureWebJobsStorage"];
        if (string.IsNullOrWhiteSpace(storageConnectionString))
        {
            throw new InvalidOperationException("AzureWebJobsStorage must be configured for Phase 10 Functions local startup.");
        }

        var options = serviceBusOptions.Value;
        if (options.Enabled && string.IsNullOrWhiteSpace(options.ConnectionString))
        {
            throw new InvalidOperationException("ServiceBus:ConnectionString must be configured when ServiceBus:Enabled is true.");
        }

        if (options.Enabled && string.IsNullOrWhiteSpace(configuration["ServiceBusConnection"]))
        {
            throw new InvalidOperationException("ServiceBusConnection must be configured when Service Bus triggers are enabled.");
        }

        if (options.Enabled
            && string.IsNullOrWhiteSpace(configuration.GetConnectionString("OrderProcessingSystemDbConnection")))
        {
            throw new InvalidOperationException(
                "ConnectionStrings:OrderProcessingSystemDbConnection must be configured for durable DLQ quarantine state.");
        }

        if (options.Enabled
            && string.IsNullOrWhiteSpace(configuration["Phase10DlqIntakeSubscriptionName"]))
        {
            throw new InvalidOperationException("Phase10DlqIntakeSubscriptionName must be configured.");
        }

        if (options.Enabled
            && string.IsNullOrWhiteSpace(configuration["Phase10ReplayRequestQueueName"]))
        {
            throw new InvalidOperationException("Phase10ReplayRequestQueueName must be configured.");
        }
    }
}
