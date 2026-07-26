using System.Text.Json;
using Azure.Messaging.ServiceBus;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

public sealed class OrderCreatedServiceBusConsumerWorker(
    IServiceScopeFactory scopeFactory,
    ServiceBusClient client,
    OrderCreatedConsumerIdentity consumerIdentity,
    IOptions<ServiceBusOptions> options,
    TimeProvider timeProvider,
    ILogger<OrderCreatedServiceBusConsumerWorker> logger) : BackgroundService
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private readonly ServiceBusOptions _options = options.Value;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await using var receiver = client.CreateReceiver(
            _options.TopicName,
            consumerIdentity.SubscriptionName,
            new ServiceBusReceiverOptions
            {
                ReceiveMode = ServiceBusReceiveMode.PeekLock,
                PrefetchCount = 20
            });

        logger.LogInformation(
            "{ConsumerKind} consumer started for {TopicName}/{SubscriptionName}.",
            consumerIdentity.ConsumerKind,
            _options.TopicName,
            consumerIdentity.SubscriptionName);

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
                continue;
            }

            await ProcessAsync(receiver, message, stoppingToken).ConfigureAwait(false);
        }
    }

    private async Task ProcessAsync(
        ServiceBusReceiver receiver,
        ServiceBusReceivedMessage message,
        CancellationToken cancellationToken)
    {
        try
        {
            var tenantId = ReadRequiredTenantId(message);
            var messageId = ReadEnvelopeMessageId(message);
            var payload = JsonSerializer.Deserialize<OrderCreatedPayload>(
                message.Body.ToString(),
                JsonOptions) ?? throw new InvalidOperationException("OrderCreatedV1 payload is null.");
            if (payload.OrderReferenceId is null || payload.OrderReferenceId == Guid.Empty)
            {
                throw new InvalidOperationException(
                    "OrderCreatedV1 requires OrderReferenceId for durable consumer effects.");
            }

            var tenantContext = await ResolveTenantAsync(tenantId, cancellationToken).ConfigureAwait(false)
                ?? throw new InvalidOperationException($"Tenant {tenantId} could not be resolved.");

            using var tenantScope = scopeFactory.CreateScope();
            tenantScope.ServiceProvider
                .GetRequiredService<ScopedTenantContextAccessor>()
                .Current = tenantContext;
            var dbContext = tenantScope.ServiceProvider
                .GetRequiredService<OrderProcessingSystemDbContext>();

            await using var transaction = await dbContext.Database
                .BeginTransactionAsync(cancellationToken)
                .ConfigureAwait(false);

            var duplicate = await dbContext.ConsumerInboxMessages
                .AnyAsync(
                    item => item.TenantId == tenantId
                        && item.ConsumerName == consumerIdentity.ConsumerKind
                        && item.MessageId == messageId,
                    cancellationToken)
                .ConfigureAwait(false);
            if (duplicate)
            {
                await transaction.RollbackAsync(cancellationToken).ConfigureAwait(false);
                await receiver.CompleteMessageAsync(message, cancellationToken).ConfigureAwait(false);
                logger.LogInformation(
                    "{ConsumerKind} ignored duplicate message {MessageId} for tenant {TenantId}.",
                    consumerIdentity.ConsumerKind,
                    messageId,
                    tenantId);
                return;
            }

            var now = timeProvider.GetUtcNow().UtcDateTime;
            var inbox = new ConsumerInboxMessage
            {
                Id = Guid.NewGuid(),
                TenantId = tenantId,
                ConsumerName = consumerIdentity.ConsumerKind,
                MessageId = messageId,
                EventType = message.Subject ?? "OrderCreatedV1",
                CorrelationId = message.CorrelationId,
                EnqueuedUtc = message.EnqueuedTime.UtcDateTime,
                ReceivedUtc = now
            };
            dbContext.ConsumerInboxMessages.Add(inbox);
            AddBusinessEffect(dbContext, tenantId, payload, message.CorrelationId, now);
            inbox.ProcessedUtc = now;

            await dbContext.SaveChangesAsync(cancellationToken).ConfigureAwait(false);
            await transaction.CommitAsync(cancellationToken).ConfigureAwait(false);
            await receiver.CompleteMessageAsync(message, cancellationToken).ConfigureAwait(false);

            logger.LogInformation(
                "{ConsumerKind} committed message {MessageId}, order {OrderReferenceId}, tenant {TenantId}, correlation {CorrelationId}.",
                consumerIdentity.ConsumerKind,
                messageId,
                payload.OrderReferenceId,
                tenantId,
                message.CorrelationId);
        }
        catch (InvalidOperationException ex)
        {
            await receiver.DeadLetterMessageAsync(
                    message,
                    "permanent-contract-failure",
                    ex.Message,
                    cancellationToken)
                .ConfigureAwait(false);
            logger.LogWarning(
                ex,
                "{ConsumerKind} dead-lettered message {MessageId} as a permanent failure.",
                consumerIdentity.ConsumerKind,
                message.MessageId);
        }
        catch (JsonException ex)
        {
            await receiver.DeadLetterMessageAsync(
                    message,
                    "malformed-payload",
                    ex.Message,
                    cancellationToken)
                .ConfigureAwait(false);
            logger.LogWarning(
                ex,
                "{ConsumerKind} dead-lettered malformed message {MessageId}.",
                consumerIdentity.ConsumerKind,
                message.MessageId);
        }
        catch (Exception ex)
        {
            await receiver.AbandonMessageAsync(message, cancellationToken: cancellationToken)
                .ConfigureAwait(false);
            logger.LogError(
                ex,
                "{ConsumerKind} abandoned message {MessageId} for transient retry.",
                consumerIdentity.ConsumerKind,
                message.MessageId);
        }
    }

    private void AddBusinessEffect(
        OrderProcessingSystemDbContext dbContext,
        int tenantId,
        OrderCreatedPayload payload,
        string? correlationId,
        DateTime now)
    {
        if (consumerIdentity.ConsumerKind.Equals("Inventory", StringComparison.Ordinal))
        {
            dbContext.InventoryReservations.Add(new InventoryReservation
            {
                Id = Guid.NewGuid(),
                TenantId = tenantId,
                OrderReferenceId = payload.OrderReferenceId!.Value,
                ProductCount = payload.ProductCount,
                ReservedUtc = now,
                CorrelationId = correlationId
            });
            return;
        }

        if (consumerIdentity.ConsumerKind.Equals("Notifications", StringComparison.Ordinal))
        {
            dbContext.NotificationDeliveries.Add(new NotificationDelivery
            {
                Id = Guid.NewGuid(),
                TenantId = tenantId,
                OrderReferenceId = payload.OrderReferenceId!.Value,
                NotificationType = "OrderCreated",
                Sink = "local-deterministic",
                AcceptedUtc = now,
                CorrelationId = correlationId
            });
            return;
        }

        throw new InvalidOperationException(
            $"Unsupported OrderCreated consumer kind: {consumerIdentity.ConsumerKind}.");
    }

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

    private sealed record OrderCreatedPayload(
        int CustomerId,
        DateTime OrderDate,
        decimal TotalPrice,
        int ProductCount,
        Guid? OrderReferenceId);
}
