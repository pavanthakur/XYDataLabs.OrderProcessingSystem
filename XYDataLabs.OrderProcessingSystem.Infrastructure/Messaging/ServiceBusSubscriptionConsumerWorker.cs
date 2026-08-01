using Azure.Messaging.ServiceBus;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

public sealed class ServiceBusSubscriptionConsumerWorker(
    ServiceBusClient client,
    ServiceBusConsumerSubscription consumerSubscription,
    IServiceBusConsumerMessageProcessor messageProcessor,
    IOptions<ServiceBusOptions> options,
    ILogger<ServiceBusSubscriptionConsumerWorker> logger) : BackgroundService
{
    private readonly ServiceBusOptions _options = options.Value;
    private readonly SemaphoreSlim _receiverSettlementGate = new(1, 1);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await using var receiver = client.CreateReceiver(
            _options.TopicName,
            consumerSubscription.SubscriptionName,
            new ServiceBusReceiverOptions
            {
                ReceiveMode = ServiceBusReceiveMode.PeekLock,
                PrefetchCount = Math.Max(20, _options.MaxConcurrentMessages * 5)
            });

        logger.LogInformation(
            "{ConsumerKind} consumer started for {TopicName}/{SubscriptionName}.",
            consumerSubscription.ConsumerKind,
            _options.TopicName,
            consumerSubscription.SubscriptionName);

        var activeProcessingTasks = new List<Task>();
        while (!stoppingToken.IsCancellationRequested)
        {
            ServiceBusReceivedMessage? message;
            try
            {
                message = await receiver
                    .ReceiveMessageAsync(TimeSpan.FromSeconds(5), stoppingToken)
                    .ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }

            if (message is null)
            {
                if (activeProcessingTasks.Count > 0)
                {
                    var completedTask = await Task.WhenAny(activeProcessingTasks).ConfigureAwait(false);
                    activeProcessingTasks.Remove(completedTask);
                }
                continue;
            }

            activeProcessingTasks.Add(ProcessAsync(receiver, message, stoppingToken));
            if (activeProcessingTasks.Count >= Math.Max(1, _options.MaxConcurrentMessages))
            {
                var completedTask = await Task.WhenAny(activeProcessingTasks).ConfigureAwait(false);
                activeProcessingTasks.Remove(completedTask);
            }
        }

        if (activeProcessingTasks.Count > 0)
        {
            await Task.WhenAll(activeProcessingTasks).ConfigureAwait(false);
        }
    }

    private async Task ProcessAsync(
        ServiceBusReceiver receiver,
        ServiceBusReceivedMessage message,
        CancellationToken cancellationToken)
    {
        var result = await messageProcessor.ProcessAsync(message, cancellationToken).ConfigureAwait(false);

        switch (result.Disposition)
        {
            case ServiceBusConsumerMessageDisposition.Complete:
                await SettleMessageAsync(
                    () => receiver.CompleteMessageAsync(message, cancellationToken),
                    cancellationToken).ConfigureAwait(false);

                if (result.EventType is not null
                    && !consumerSubscription.EventPayloadTypes.ContainsKey(result.EventType))
                {
                    logger.LogInformation(
                        "{ConsumerKind} ignored unrelated event type {EventType} for message {MessageId}.",
                        result.ConsumerKind,
                        result.EventType,
                        result.EnvelopeMessageId);
                    return;
                }

                if (result.Duplicate)
                {
                    logger.LogInformation(
                        "{ConsumerKind} ignored duplicate message {MessageId} for tenant {TenantId}.",
                        result.ConsumerKind,
                        result.EnvelopeMessageId,
                        result.TenantId);
                    return;
                }

                logger.LogInformation(
                    "{ConsumerKind} committed message {MessageId}, event {EventType}, tenant {TenantId}, correlation {CorrelationId}.",
                    result.ConsumerKind,
                    result.EnvelopeMessageId,
                    result.EventType,
                    result.TenantId,
                    result.CorrelationId);
                return;

            case ServiceBusConsumerMessageDisposition.DeadLetter:
                await SettleMessageAsync(
                    () => receiver.DeadLetterMessageAsync(
                        message,
                        result.DeadLetterReason,
                        result.DeadLetterDescription,
                        cancellationToken),
                    cancellationToken).ConfigureAwait(false);
                logger.LogWarning(
                    "{ConsumerKind} dead-lettered message {MessageId} with reason {Reason}.",
                    result.ConsumerKind,
                    result.BrokerMessageId,
                    result.DeadLetterReason);
                return;

            default:
                await SettleMessageAsync(
                    () => receiver.AbandonMessageAsync(message, cancellationToken: cancellationToken),
                    cancellationToken).ConfigureAwait(false);
                logger.LogError(
                    "{ConsumerKind} abandoned message {MessageId} for transient retry.",
                    result.ConsumerKind,
                    result.BrokerMessageId);
                return;
        }
    }

    private async Task SettleMessageAsync(
        Func<Task> settleAction,
        CancellationToken cancellationToken)
    {
        await _receiverSettlementGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            await settleAction().ConfigureAwait(false);
        }
        finally
        {
            _receiverSettlementGate.Release();
        }
    }
}

