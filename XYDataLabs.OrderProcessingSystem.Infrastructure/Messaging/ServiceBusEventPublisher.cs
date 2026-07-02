using Azure.Messaging.ServiceBus;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using XYDataLabs.OrderProcessingSystem.Application.Events;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

public sealed class ServiceBusEventPublisher : IEventPublisher, IAsyncDisposable
{
    private readonly ServiceBusOptions _options;
    private readonly ServiceBusClient _client;
    private readonly ILogger<ServiceBusEventPublisher> _logger;
    private readonly ServiceBusMessageFactory _messageFactory;
    private ServiceBusSender? _sender;

    public ServiceBusEventPublisher(
        ServiceBusClient client,
        IOptions<ServiceBusOptions> options,
        ServiceBusMessageFactory messageFactory,
        ILogger<ServiceBusEventPublisher> logger)
    {
        _client = client;
        _options = options.Value;
        _messageFactory = messageFactory;
        _logger = logger;
    }

    public async Task PublishAsync(EventEnvelope eventEnvelope, CancellationToken cancellationToken = default)
    {
        if (!_options.Enabled)
        {
            _logger.LogDebug("Service Bus is disabled; skipping publish for {EventType}.", eventEnvelope.EventType);
            return;
        }

        var sender = _sender ??= _client.CreateSender(_options.TopicName);
        var message = _messageFactory.Create(eventEnvelope);
        message.TimeToLive = _options.MessageTtl;

        await sender.SendMessageAsync(message, cancellationToken).ConfigureAwait(false);
    }

    public async ValueTask DisposeAsync()
    {
        if (_sender is not null)
        {
            await _sender.DisposeAsync().ConfigureAwait(false);
        }
    }
}
