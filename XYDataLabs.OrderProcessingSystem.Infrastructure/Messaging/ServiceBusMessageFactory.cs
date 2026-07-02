using System.Text.Json;
using Azure.Messaging.ServiceBus;
using XYDataLabs.OrderProcessingSystem.Application.Events;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

public sealed class ServiceBusMessageFactory
{
    private readonly JsonSerializerOptions _jsonOptions = new(JsonSerializerDefaults.Web);

    public ServiceBusMessage Create(EventEnvelope envelope, Action<ServiceBusMessage>? configure = null)
    {
        ArgumentNullException.ThrowIfNull(envelope);

        var payloadJson = JsonSerializer.Serialize(envelope.Payload, envelope.Payload.GetType(), _jsonOptions);
        var message = new ServiceBusMessage(BinaryData.FromString(payloadJson));

        MessageMetadataMapper.Apply(message, envelope);
        configure?.Invoke(message);

        return message;
    }
}
