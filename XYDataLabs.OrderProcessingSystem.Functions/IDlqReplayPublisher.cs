using Azure.Messaging.ServiceBus;

namespace XYDataLabs.OrderProcessingSystem.Functions;

internal interface IDlqReplayPublisher
{
    Task PublishAsync(ServiceBusMessage message, CancellationToken cancellationToken);
}
