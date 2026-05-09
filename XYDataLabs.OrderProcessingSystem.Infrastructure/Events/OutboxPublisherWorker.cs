using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Events;

public class OutboxPublisherWorker : BackgroundService
{
    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<OutboxPublisherWorker> _logger;
    private readonly JsonSerializerOptions _jsonOptions = new(JsonSerializerDefaults.Web);

    public OutboxPublisherWorker(IServiceProvider serviceProvider, ILogger<OutboxPublisherWorker> logger)
    {
        _serviceProvider = serviceProvider;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await ProcessOutboxMessagesAsync(stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "An error occurred while processing outbox messages.");
            }

            // Polling interval
            await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
        }
    }

    private async Task ProcessOutboxMessagesAsync(CancellationToken cancellationToken)
    {
        using var scope = _serviceProvider.CreateScope();
        
        var dbContext = scope.ServiceProvider.GetRequiredService<IAppDbContext>();
        var publisher = scope.ServiceProvider.GetRequiredService<IEventPublisher>();
        var typeResolver = scope.ServiceProvider.GetRequiredService<IIntegrationEventTypeResolver>();

        // In Phase 8, we pull unprocessed lines sequentially to avoid competing-consumer locking overhead just yet
        var pendingMessages = await dbContext.OutboxMessages
            .Where(x => x.ProcessedAt == null)
            .OrderBy(x => x.OccurredUtc)
            .Take(20)
            .ToListAsync(cancellationToken);

        if (pendingMessages.Count == 0)
        {
            return;
        }

        foreach (var outboxMessage in pendingMessages)
        {
            try
            {
                var eventType = typeResolver.ResolveType(outboxMessage.EventType);

                if (eventType is null)
                {
                    _logger.LogWarning("Could not resolve integration event type for {EventType}", outboxMessage.EventType);
                    outboxMessage.LastError = $"Unresolved Type: {outboxMessage.EventType}";
                    outboxMessage.PublishAttempts++;
                    continue;
                }

                var payloadObj = JsonSerializer.Deserialize(outboxMessage.Payload, eventType, _jsonOptions);

                if (payloadObj is null)
                {
                    _logger.LogWarning("Could not deserialize payload for {MessageId}", outboxMessage.MessageId);
                    outboxMessage.LastError = "Deserialization yielded null";
                    outboxMessage.PublishAttempts++;
                    continue;
                }

                var envelope = EventEnvelope.Create(
                    outboxMessage.EventType,
                    outboxMessage.SchemaVersion,
                    outboxMessage.OccurredUtc,
                    payloadObj,
                    outboxMessage.MessageId,
                    outboxMessage.CorrelationId,
                    outboxMessage.CausationId,
                    outboxMessage.TraceParent,
                    outboxMessage.TenantId == 0 ? null : outboxMessage.TenantId);

                // Publish synchronously in-memory
                await publisher.PublishAsync(envelope, cancellationToken);

                // Mark processed
                outboxMessage.ProcessedAt = DateTime.UtcNow;
                outboxMessage.LastError = null;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to publish Outbox Message {MessageId}", outboxMessage.MessageId);
                // Truncate to MaxLength(1024) if it's a massive stack trace to avoid truncation errors
                outboxMessage.LastError = ex.Message.Length > 1024 
                    ? ex.Message.Substring(0, 1024) 
                    : ex.Message;
            }
            finally
            {
                outboxMessage.PublishAttempts++;
            }
        }

        await dbContext.SaveChangesAsync(cancellationToken);
    }
}
