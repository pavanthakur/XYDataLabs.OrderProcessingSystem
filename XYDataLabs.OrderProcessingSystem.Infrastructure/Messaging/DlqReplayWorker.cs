using Azure.Messaging.ServiceBus;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using XYDataLabs.OrderProcessingSystem.Application.Events;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

public sealed class DlqReplayWorker : BackgroundService
{
    private static readonly TimeSpan IdleDelay = TimeSpan.FromSeconds(5);
    private static readonly TimeSpan ReceiveWaitTime = TimeSpan.FromSeconds(2);

    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<DlqReplayWorker> _logger;
    private readonly ServiceBusOptions _options;

    public DlqReplayWorker(
        IServiceProvider serviceProvider,
        IOptions<ServiceBusOptions> options,
        ILogger<DlqReplayWorker> logger)
    {
        _serviceProvider = serviceProvider;
        _options = options.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!_options.Enabled || !_options.ReplayEnabled)
        {
            _logger.LogInformation("DLQ replay worker is disabled until the Service Bus transport slice is enabled.");
            return;
        }

        var client = _serviceProvider.GetService<ServiceBusClient>();
        if (client is null)
        {
            _logger.LogInformation("DLQ replay worker is waiting for a Service Bus client before replay can start.");
            return;
        }

        var typeResolver = _serviceProvider.GetService<IIntegrationEventTypeResolver>();
        var messageFactory = _serviceProvider.GetService<ServiceBusMessageFactory>();
        if (typeResolver is null || messageFactory is null)
        {
            _logger.LogInformation("DLQ replay worker is waiting for the application transport services before replay can start.");
            return;
        }

        await using var receiver = client.CreateReceiver(
            _options.DeadLetterTopicName,
            _options.DeadLetterSubscriptionName);
        await using var sender = client.CreateSender(_options.TopicName);

        _logger.LogInformation(
            "DLQ replay worker started for dead-letter topic {DeadLetterTopicName}/{DeadLetterSubscriptionName} and replay target {TopicName}.",
            _options.DeadLetterTopicName,
            _options.DeadLetterSubscriptionName,
            _options.TopicName);

        while (!stoppingToken.IsCancellationRequested)
        {
            IReadOnlyList<ServiceBusReceivedMessage> messages;

            try
            {
                messages = await receiver.ReceiveMessagesAsync(
                    _options.ReplayBatchSize,
                    ReceiveWaitTime,
                    stoppingToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to receive DLQ messages for replay.");
                await Task.Delay(IdleDelay, stoppingToken).ConfigureAwait(false);
                continue;
            }

            if (messages.Count == 0)
            {
                await Task.Delay(IdleDelay, stoppingToken).ConfigureAwait(false);
                continue;
            }

            foreach (var message in messages)
            {
                if (stoppingToken.IsCancellationRequested)
                {
                    break;
                }

                await ProcessMessageAsync(receiver, sender, message, typeResolver, messageFactory, stoppingToken).ConfigureAwait(false);
            }
        }
    }

    private async Task ProcessMessageAsync(
        ServiceBusReceiver receiver,
        ServiceBusSender sender,
        ServiceBusReceivedMessage message,
        IIntegrationEventTypeResolver typeResolver,
        ServiceBusMessageFactory messageFactory,
        CancellationToken cancellationToken)
    {
        if (!DlqMessageEnvelopeHydrator.TryHydrateEnvelope(message, typeResolver, out var envelope, out var failureReason))
        {
            await QuarantineAsync(receiver, message, "dlq-unclassified", failureReason, cancellationToken).ConfigureAwait(false);
            return;
        }

        var attemptCount = GetAttemptCount(message);
        var deadLetterReason = message.DeadLetterReason ?? string.Empty;
        var deadLetterDescription = message.DeadLetterErrorDescription ?? string.Empty;

        if (attemptCount >= _options.MaxReplayAttempts || DlqMessageEnvelopeHydrator.IsPoison(deadLetterReason, deadLetterDescription, failureReason))
        {
            var reason = $"Non-replayable after {attemptCount} attempt(s).";
            var description = failureReason ?? deadLetterDescription ?? deadLetterReason;
            await QuarantineAsync(receiver, message, reason, description, cancellationToken).ConfigureAwait(false);
            return;
        }

        var replayedMessage = messageFactory.Create(envelope, outgoing =>
        {
            outgoing.ApplicationProperties["AttemptCount"] = attemptCount + 1;
            outgoing.ApplicationProperties["FailureCategory"] = "replayed";
            outgoing.ApplicationProperties["ReplaySourceMessageId"] = message.MessageId;
            outgoing.ApplicationProperties["ReplaySourceDeadLetterReason"] = deadLetterReason;
            outgoing.ApplicationProperties["ReplaySourceDeadLetterDescription"] = deadLetterDescription;
            outgoing.ApplicationProperties["ReplayAttempt"] = attemptCount + 1;
        });
        replayedMessage.TimeToLive = _options.MessageTtl;

        await sender.SendMessageAsync(replayedMessage, cancellationToken).ConfigureAwait(false);
        await receiver.CompleteMessageAsync(message, cancellationToken).ConfigureAwait(false);

        _logger.LogInformation(
            "Replayed dead-lettered message {EnvelopeMessageId} for event {EventType} after {AttemptCount} attempt(s).",
            envelope.MessageId,
            envelope.EventType,
            attemptCount);
    }

    private async Task QuarantineAsync(
        ServiceBusReceiver receiver,
        ServiceBusReceivedMessage message,
        string reason,
        string? description,
        CancellationToken cancellationToken)
    {
        try
        {
            await receiver.DeadLetterMessageAsync(message, reason, description ?? string.Empty, cancellationToken).ConfigureAwait(false);
            _logger.LogWarning(
                "Quarantined dead-lettered message {MessageId} with reason {Reason}.",
                message.MessageId,
                reason);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to quarantine dead-lettered message {MessageId}.", message.MessageId);
            throw;
        }
    }

    private static int GetAttemptCount(ServiceBusReceivedMessage message)
    {
        if (message.ApplicationProperties.TryGetValue("AttemptCount", out var raw) && raw is not null)
        {
            return raw switch
            {
                int value => value,
                long value when value is >= int.MinValue and <= int.MaxValue => (int)value,
                string value when int.TryParse(value, out var parsed) => parsed,
                _ when int.TryParse(Convert.ToString(raw), out var parsed) => parsed,
                _ => message.DeliveryCount
            };
        }

        return message.DeliveryCount;
    }
}
