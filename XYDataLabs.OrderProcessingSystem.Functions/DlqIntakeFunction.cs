using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace XYDataLabs.OrderProcessingSystem.Functions;

public sealed class DlqIntakeFunction(ILogger<DlqIntakeFunction> logger)
{
    [Function(nameof(DlqIntakeFunction))]
    public Task RunAsync(
        [ServiceBusTrigger("%Phase10DlqTopicName%", "%Phase10DlqSubscriptionName%", Connection = "ServiceBusConnection")]
        ServiceBusReceivedMessage message,
        CancellationToken cancellationToken)
    {
        logger.LogInformation(
            "Phase 10 DLQ intake received message {MessageId} with subject {Subject}.",
            message.MessageId,
            message.Subject);

        return Task.CompletedTask;
    }
}
