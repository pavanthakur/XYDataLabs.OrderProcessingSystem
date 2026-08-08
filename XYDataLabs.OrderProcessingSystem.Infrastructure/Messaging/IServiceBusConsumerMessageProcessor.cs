using Azure.Messaging.ServiceBus;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

public interface IServiceBusConsumerMessageProcessor
{
    Task<ServiceBusConsumerMessageProcessingResult> ProcessAsync(
        ServiceBusReceivedMessage message,
        CancellationToken cancellationToken);
}
