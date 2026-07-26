using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

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
        await using var registryScope = _serviceProvider.CreateAsyncScope();

        var tenantRegistryContext = registryScope.ServiceProvider.GetRequiredService<TenantRegistryDbContext>();
        var tenantResolver = registryScope.ServiceProvider.GetRequiredService<ITenantResolver>();
        var tenantCodes = await tenantRegistryContext.Tenants
            .AsNoTracking()
            .OrderBy(tenant => tenant.Id)
            .Select(tenant => tenant.Code)
            .ToListAsync(cancellationToken);

        if (tenantCodes.Count == 0)
        {
            return;
        }

        foreach (var tenantCode in tenantCodes)
        {
            var tenantContext = await tenantResolver.ResolveTenantAsync(tenantCode, cancellationToken);
            if (tenantContext is null)
            {
                _logger.LogWarning("Skipping outbox processing for tenant code {TenantCode} because tenant resolution failed.", tenantCode);
                continue;
            }

            await ProcessTenantOutboxMessagesAsync(tenantContext, cancellationToken);
        }
    }

    private async Task ProcessTenantOutboxMessagesAsync(TenantContext tenantContext, CancellationToken cancellationToken)
    {
        await using var tenantScope = _serviceProvider.CreateAsyncScope();
        var tenantContextAccessor = tenantScope.ServiceProvider.GetRequiredService<ScopedTenantContextAccessor>();
        tenantContextAccessor.Current = tenantContext;

        try
        {
            var dbContext = tenantScope.ServiceProvider.GetRequiredService<IAppDbContext>();
            var publisher = tenantScope.ServiceProvider.GetRequiredService<IEventPublisher>();
            var typeResolver = tenantScope.ServiceProvider.GetRequiredService<IIntegrationEventTypeResolver>();

            var pendingMessages = await dbContext.OutboxMessages
                .Where(message => message.ProcessedAt == null && message.TenantId == tenantContext.TenantId)
                .OrderBy(message => message.OccurredUtc)
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

                    await publisher.PublishAsync(envelope, cancellationToken);

                    outboxMessage.ProcessedAt = DateTime.UtcNow;
                    outboxMessage.LastError = null;
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to publish Outbox Message {MessageId}", outboxMessage.MessageId);
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
        finally
        {
            tenantContextAccessor.Current = null;
        }
    }
}
