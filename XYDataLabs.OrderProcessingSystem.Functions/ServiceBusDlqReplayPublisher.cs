using Azure.Messaging.ServiceBus;
using Microsoft.Extensions.Options;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

namespace XYDataLabs.OrderProcessingSystem.Functions;

internal sealed class ServiceBusDlqReplayPublisher(
    ServiceBusClient client,
    IOptions<ServiceBusOptions> options) : IDlqReplayPublisher
{
    private readonly ServiceBusOptions _options = options.Value;

    public async Task PublishAsync(ServiceBusMessage message, CancellationToken cancellationToken)
    {
        await using var sender = client.CreateSender(_options.TopicName);
        await sender.SendMessageAsync(message, cancellationToken).ConfigureAwait(false);
    }
}
