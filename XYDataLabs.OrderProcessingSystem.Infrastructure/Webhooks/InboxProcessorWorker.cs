using System.Diagnostics;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.Application.Features.Webhooks;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Observability;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Webhooks;

/// <summary>
/// Background worker that processes InboxMessages in status Received.
/// Per-tenant: iterates all tenants from the registry, processes up to 20 messages per poll.
/// Distributed locking via LockExpiry prevents double-processing across multiple instances.
/// Emits OTel metrics: dedup hits, handler duration, unresolvable tenant (DW-003).
/// </summary>
public sealed class InboxProcessorWorker : BackgroundService
{
    private static readonly TimeSpan LockDuration = TimeSpan.FromMinutes(2);
    private const int BatchSize = 20;
    private const int MaxAttempts = 5;

    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<InboxProcessorWorker> _logger;

    public InboxProcessorWorker(IServiceProvider serviceProvider, ILogger<InboxProcessorWorker> logger)
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
                await ProcessAllTenantsAsync(stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "InboxProcessorWorker: unhandled error during poll cycle.");
            }

            await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
        }
    }

    private async Task ProcessAllTenantsAsync(CancellationToken cancellationToken)
    {
        using var registryScope = _serviceProvider.CreateScope();
        var tenantRegistryContext = registryScope.ServiceProvider.GetRequiredService<TenantRegistryDbContext>();
        var tenantResolver = registryScope.ServiceProvider.GetRequiredService<ITenantResolver>();

        var tenantCodes = await tenantRegistryContext.Tenants
            .AsNoTracking()
            .OrderBy(t => t.Id)
            .Select(t => t.Code)
            .ToListAsync(cancellationToken);

        foreach (var tenantCode in tenantCodes)
        {
            var tenantContext = await tenantResolver.ResolveTenantAsync(tenantCode, cancellationToken);
            if (tenantContext is null)
            {
                BusinessMetrics.RecordWebhookUnresolvableTenant("unknown", "inbox.process");
                _logger.LogWarning("InboxProcessorWorker: could not resolve tenant {TenantCode}", tenantCode);
                continue;
            }

            await ProcessTenantInboxAsync(tenantContext, cancellationToken);
        }
    }

    private async Task ProcessTenantInboxAsync(TenantContext tenantContext, CancellationToken cancellationToken)
    {
        using var tenantScope = _serviceProvider.CreateScope();
        var tenantContextAccessor = tenantScope.ServiceProvider.GetRequiredService<ScopedTenantContextAccessor>();
        tenantContextAccessor.Current = tenantContext;

        try
        {
            var dbContext = tenantScope.ServiceProvider.GetRequiredService<DataContext.OrderProcessingSystemDbContext>();
            var handlers = tenantScope.ServiceProvider.GetServices<IWebhookEventHandler>()
                .ToDictionary(h => h.EventType, StringComparer.OrdinalIgnoreCase);

            var now = DateTime.UtcNow;
            var messages = await dbContext.InboxMessages
                .Where(m =>
                    m.TenantId == tenantContext.TenantId &&
                    m.Status == InboxMessageStatus.Received &&
                    m.ProcessingAttempts < MaxAttempts &&
                    (m.LockExpiry == null || m.LockExpiry < now))
                .OrderBy(m => m.CreatedDate)
                .Take(BatchSize)
                .ToListAsync(cancellationToken);

            if (messages.Count == 0) return;

            // Claim the batch by setting lock expiry.
            foreach (var msg in messages)
            {
                msg.Status = InboxMessageStatus.Processing;
                msg.LockExpiry = now.Add(LockDuration);
            }
            await dbContext.SaveChangesAsync(cancellationToken);

            foreach (var msg in messages)
            {
                await ProcessMessageAsync(dbContext, handlers, msg, tenantContext.TenantId, cancellationToken);
            }

            await dbContext.SaveChangesAsync(cancellationToken);
        }
        finally
        {
            tenantContextAccessor.Current = null;
        }
    }

    private async Task ProcessMessageAsync(
        DataContext.OrderProcessingSystemDbContext dbContext,
        Dictionary<string, IWebhookEventHandler> handlers,
        InboxMessage msg,
        int tenantId,
        CancellationToken cancellationToken)
    {
        // Deduplication: if a message with the same ProviderEventId was already processed, skip.
        var alreadyProcessed = await dbContext.InboxMessages
            .AnyAsync(
                m => m.TenantId == tenantId
                  && m.ProviderEventId == msg.ProviderEventId
                  && m.Status == InboxMessageStatus.Processed
                  && m.Id != msg.Id,
                cancellationToken);

        if (alreadyProcessed)
        {
            BusinessMetrics.RecordInboxDedupHit(msg.Source, msg.EventType);
            _logger.LogInformation(
                "InboxProcessorWorker: duplicate event detected. InboxMessageId={Id} ProviderEventId={ProviderEventId}",
                msg.Id, msg.ProviderEventId);
            msg.Status = InboxMessageStatus.Processed;
            msg.ProcessedUtc = DateTime.UtcNow;
            msg.LockExpiry = null;
            return;
        }

        var sw = Stopwatch.StartNew();
        string outcome = "success";

        try
        {
            if (!handlers.TryGetValue(msg.EventType, out var handler))
            {
                _logger.LogWarning(
                    "InboxProcessorWorker: no handler registered for EventType={EventType} Source={Source}",
                    msg.EventType, msg.Source);
                outcome = "no_handler";
                msg.Status = InboxMessageStatus.Processed; // don't retry unhandled event types
                msg.ProcessedUtc = DateTime.UtcNow;
                msg.LockExpiry = null;
                return;
            }

            await handler.HandleAsync(msg.Source, msg.Payload, tenantId, cancellationToken);

            msg.Status = InboxMessageStatus.Processed;
            msg.ProcessedUtc = DateTime.UtcNow;
            msg.LockExpiry = null;
            msg.LastError = null;
        }
        catch (DbUpdateConcurrencyException ex)
        {
            outcome = "concurrency_conflict";
            _logger.LogWarning(ex,
                "InboxProcessorWorker: concurrency conflict processing InboxMessage {Id}. Will retry.",
                msg.Id);
            msg.Status = InboxMessageStatus.Received;
            msg.LockExpiry = null;
            msg.LastError = ex.Message.Length > 1024 ? ex.Message[..1024] : ex.Message;
        }
        catch (Exception ex)
        {
            outcome = "error";
            msg.ProcessingAttempts++;
            msg.Status = msg.ProcessingAttempts >= MaxAttempts
                ? InboxMessageStatus.Failed
                : InboxMessageStatus.Received;
            msg.LockExpiry = null;
            msg.LastError = ex.Message.Length > 1024 ? ex.Message[..1024] : ex.Message;
            _logger.LogError(ex,
                "InboxProcessorWorker: failed to process InboxMessage {Id} (attempt {Attempt}/{Max})",
                msg.Id, msg.ProcessingAttempts, MaxAttempts);
        }
        finally
        {
            sw.Stop();
            BusinessMetrics.RecordInboxHandlerDuration(msg.EventType, outcome, sw.Elapsed);
        }
    }
}
