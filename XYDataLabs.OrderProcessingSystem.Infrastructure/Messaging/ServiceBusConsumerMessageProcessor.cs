using System.Text.Json;
using Azure.Messaging.ServiceBus;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

public sealed class ServiceBusConsumerMessageProcessor(
    IServiceScopeFactory scopeFactory,
    ServiceBusConsumerSubscription consumerSubscription,
    TimeProvider timeProvider,
    ILogger<ServiceBusConsumerMessageProcessor> logger) : IServiceBusConsumerMessageProcessor
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task<ServiceBusConsumerMessageProcessingResult> ProcessAsync(
        ServiceBusReceivedMessage message,
        CancellationToken cancellationToken)
    {
        try
        {
            var tenantId = ReadRequiredTenantId(message);
            var messageId = ReadEnvelopeMessageId(message);
            var eventType = ReadRequiredEventType(message);

            if (!consumerSubscription.EventPayloadTypes.TryGetValue(eventType, out var payloadType))
            {
                return new ServiceBusConsumerMessageProcessingResult(
                    ServiceBusConsumerMessageDisposition.Complete,
                    consumerSubscription.ConsumerKind,
                    message.MessageId,
                    EnvelopeMessageId: messageId,
                    TenantId: tenantId,
                    EventType: eventType,
                    CorrelationId: message.CorrelationId);
            }

            var tenantContext = await ResolveTenantAsync(tenantId, cancellationToken).ConfigureAwait(false)
                ?? throw new InvalidOperationException($"Tenant {tenantId} could not be resolved.");

            using var tenantScope = scopeFactory.CreateScope();
            tenantScope.ServiceProvider
                .GetRequiredService<ScopedTenantContextAccessor>()
                .Current = tenantContext;
            var dbContext = tenantScope.ServiceProvider
                .GetRequiredService<OrderProcessingSystemDbContext>();

            var duplicate = false;
            var executionStrategy = dbContext.Database.CreateExecutionStrategy();
            await executionStrategy.ExecuteAsync(async () =>
            {
                await using var transaction = await dbContext.Database
                    .BeginTransactionAsync(cancellationToken)
                    .ConfigureAwait(false);

                duplicate = await dbContext.ConsumerInboxMessages
                    .AnyAsync(
                        item => item.TenantId == tenantId
                            && item.ConsumerName == consumerSubscription.ConsumerKind
                            && item.MessageId == messageId,
                        cancellationToken)
                    .ConfigureAwait(false);
                if (duplicate)
                {
                    await transaction.RollbackAsync(cancellationToken).ConfigureAwait(false);
                    return;
                }

                var now = timeProvider.GetUtcNow().UtcDateTime;
                var inbox = new ConsumerInboxMessage
                {
                    Id = Guid.NewGuid(),
                    TenantId = tenantId,
                    ConsumerName = consumerSubscription.ConsumerKind,
                    MessageId = messageId,
                    EventType = eventType,
                    CorrelationId = message.CorrelationId,
                    EnqueuedUtc = message.EnqueuedTime.UtcDateTime,
                    ReceivedUtc = now
                };
                dbContext.ConsumerInboxMessages.Add(inbox);

                var payload = DeserializePayload(message, eventType, payloadType);
                var envelope = BuildEnvelope(message, messageId, eventType, payload, tenantId);
                await DispatchToEventHandlersAsync(
                    tenantScope.ServiceProvider,
                    envelope,
                    payload,
                    cancellationToken).ConfigureAwait(false);

                inbox.ProcessedUtc = now;

                await dbContext.SaveChangesAsync(cancellationToken).ConfigureAwait(false);
                await transaction.CommitAsync(cancellationToken).ConfigureAwait(false);
            });

            return new ServiceBusConsumerMessageProcessingResult(
                ServiceBusConsumerMessageDisposition.Complete,
                consumerSubscription.ConsumerKind,
                message.MessageId,
                EnvelopeMessageId: messageId,
                TenantId: tenantId,
                EventType: eventType,
                CorrelationId: message.CorrelationId,
                Duplicate: duplicate);
        }
        catch (InvalidOperationException ex)
        {
            logger.LogWarning(
                ex,
                "{ConsumerKind} classified message {MessageId} as a permanent contract failure.",
                consumerSubscription.ConsumerKind,
                message.MessageId);

            return new ServiceBusConsumerMessageProcessingResult(
                ServiceBusConsumerMessageDisposition.DeadLetter,
                consumerSubscription.ConsumerKind,
                message.MessageId,
                DeadLetterReason: "permanent-contract-failure",
                DeadLetterDescription: ex.Message);
        }
        catch (JsonException ex)
        {
            logger.LogWarning(
                ex,
                "{ConsumerKind} classified message {MessageId} as malformed payload.",
                consumerSubscription.ConsumerKind,
                message.MessageId);

            return new ServiceBusConsumerMessageProcessingResult(
                ServiceBusConsumerMessageDisposition.DeadLetter,
                consumerSubscription.ConsumerKind,
                message.MessageId,
                DeadLetterReason: "malformed-payload",
                DeadLetterDescription: ex.Message);
        }
        catch (Exception ex)
        {
            logger.LogError(
                ex,
                "{ConsumerKind} classified message {MessageId} for transient retry.",
                consumerSubscription.ConsumerKind,
                message.MessageId);

            return new ServiceBusConsumerMessageProcessingResult(
                ServiceBusConsumerMessageDisposition.Abandon,
                consumerSubscription.ConsumerKind,
                message.MessageId);
        }
    }

    private static string ReadRequiredEventType(ServiceBusReceivedMessage message)
    {
        var eventType = message.Subject;
        if (string.IsNullOrWhiteSpace(eventType)
            && message.ApplicationProperties.TryGetValue("EventType", out var raw))
        {
            eventType = Convert.ToString(raw);
        }

        if (string.IsNullOrWhiteSpace(eventType))
        {
            throw new InvalidOperationException("A valid EventType is required.");
        }

        return eventType;
    }

    private static object DeserializePayload(ServiceBusReceivedMessage message, string eventType, Type payloadType)
    {
        return JsonSerializer.Deserialize(message.Body.ToString(), payloadType, JsonOptions)
            ?? throw new InvalidOperationException($"{eventType} payload is null.");
    }

    private static EventEnvelope BuildEnvelope(
        ServiceBusReceivedMessage message,
        Guid envelopeMessageId,
        string eventType,
        object payload,
        int tenantId)
    {
        var schemaVersion = message.ApplicationProperties.TryGetValue("SchemaVersion", out var rawSchemaVersion)
            && int.TryParse(Convert.ToString(rawSchemaVersion), out var parsedSchemaVersion)
                ? parsedSchemaVersion
                : 1;
        var occurredUtc = message.ApplicationProperties.TryGetValue("OccurredUtc", out var rawOccurredUtc)
            && DateTime.TryParse(
                Convert.ToString(rawOccurredUtc),
                null,
                System.Globalization.DateTimeStyles.RoundtripKind,
                out var parsedOccurredUtc)
                    ? parsedOccurredUtc
                    : message.EnqueuedTime.UtcDateTime;

        return EventEnvelope.Create(
            eventType,
            schemaVersion,
            occurredUtc,
            payload,
            messageId: envelopeMessageId,
            correlationId: FirstNonEmpty(message.CorrelationId, ReadApplicationProperty(message, "CorrelationId")),
            causationId: ReadApplicationProperty(message, "CausationId"),
            traceParent: ReadApplicationProperty(message, "TraceParent"),
            tenantId: tenantId);
    }

    private static async Task DispatchToEventHandlersAsync(
        IServiceProvider serviceProvider,
        EventEnvelope envelope,
        object payload,
        CancellationToken cancellationToken)
    {
        var payloadType = payload.GetType();
        var handlerType = typeof(IEventHandler<>).MakeGenericType(payloadType);
        var handlers = serviceProvider.GetServices(handlerType).Cast<object>().ToArray();
        if (handlers.Length == 0)
        {
            throw new InvalidOperationException(
                $"No broker event handlers are registered for payload type '{payloadType.Name}'.");
        }

        var handleMethod = handlerType.GetMethod(nameof(IEventHandler<IIntegrationEvent>.HandleAsync))
            ?? throw new InvalidOperationException($"HandleAsync was not found for handler type '{handlerType.FullName}'.");

        foreach (var handler in handlers)
        {
            var task = (Task?)handleMethod.Invoke(handler, [envelope, payload, cancellationToken]) ?? Task.CompletedTask;
            await task.ConfigureAwait(false);
        }
    }

    private static string? ReadApplicationProperty(ServiceBusReceivedMessage message, string key)
    {
        return message.ApplicationProperties.TryGetValue(key, out var raw)
            ? Convert.ToString(raw)
            : null;
    }

    private static string? FirstNonEmpty(params string?[] values)
        => values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value));

    private async Task<TenantContext?> ResolveTenantAsync(
        int tenantId,
        CancellationToken cancellationToken)
    {
        using var scope = scopeFactory.CreateScope();
        var registry = scope.ServiceProvider.GetRequiredService<TenantRegistryDbContext>();
        var tenantCode = await registry.Tenants
            .AsNoTracking()
            .Where(item => item.Id == tenantId)
            .Select(item => item.Code)
            .SingleOrDefaultAsync(cancellationToken)
            .ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(tenantCode))
        {
            return null;
        }

        return await scope.ServiceProvider
            .GetRequiredService<ITenantResolver>()
            .ResolveTenantAsync(tenantCode, cancellationToken)
            .ConfigureAwait(false);
    }

    private static int ReadRequiredTenantId(ServiceBusReceivedMessage message)
    {
        if (!message.ApplicationProperties.TryGetValue("TenantId", out var raw)
            || !int.TryParse(Convert.ToString(raw), out var tenantId)
            || tenantId <= 0)
        {
            throw new InvalidOperationException("A valid TenantId application property is required.");
        }

        return tenantId;
    }

    private static Guid ReadEnvelopeMessageId(ServiceBusReceivedMessage message)
    {
        if (message.ApplicationProperties.TryGetValue("EnvelopeMessageId", out var raw)
            && Guid.TryParse(Convert.ToString(raw), out var envelopeMessageId))
        {
            return envelopeMessageId;
        }

        if (Guid.TryParse(message.MessageId, out var brokerMessageId))
        {
            return brokerMessageId;
        }

        throw new InvalidOperationException("A valid envelope MessageId is required.");
    }
}
