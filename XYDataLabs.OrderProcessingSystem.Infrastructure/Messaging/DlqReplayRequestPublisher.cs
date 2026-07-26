using System.Text.Json;
using Azure.Messaging.ServiceBus;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

public sealed class DlqReplayRequestPublisher(
    IServiceScopeFactory scopeFactory,
    IOptions<ServiceBusOptions> options,
    ILogger<DlqReplayRequestPublisher> logger) : BackgroundService
{
    private static readonly TimeSpan PollDelay = TimeSpan.FromSeconds(5);
    private readonly ServiceBusOptions _options = options.Value;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!_options.Enabled)
        {
            logger.LogInformation("DLQ replay request publisher is disabled because Service Bus is disabled.");
            return;
        }

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await PublishPendingAsync(stoppingToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Failed to publish pending DLQ replay requests.");
            }

            await Task.Delay(PollDelay, stoppingToken).ConfigureAwait(false);
        }
    }

    private async Task PublishPendingAsync(CancellationToken cancellationToken)
    {
        using var scope = scopeFactory.CreateScope();
        var client = scope.ServiceProvider.GetRequiredService<ServiceBusClient>();
        var dbContext = scope.ServiceProvider.GetRequiredService<OrderProcessingSystemDbContext>();
        var pending = await dbContext.DlqReplayRequests
            .Include(item => item.Quarantine)
            .Where(item => item.PublishedUtc == null)
            .OrderBy(item => item.ApprovedUtc)
            .Take(20)
            .ToListAsync(cancellationToken)
            .ConfigureAwait(false);

        if (pending.Count == 0)
        {
            return;
        }

        await using var sender = client.CreateSender(_options.ReplayRequestQueueName);
        foreach (var request in pending)
        {
            try
            {
                var quarantine = request.Quarantine;
                var message = new ServiceBusMessage(BinaryData.FromString(quarantine.Body))
                {
                    MessageId = request.Id.ToString("D"),
                    Subject = quarantine.Subject ?? quarantine.EventType,
                    ContentType = quarantine.ContentType ?? "application/json",
                    CorrelationId = quarantine.CorrelationId,
                    TimeToLive = _options.MessageTtl
                };

                foreach (var property in DeserializeProperties(quarantine.ApplicationPropertiesJson))
                {
                    message.ApplicationProperties[property.Key] = property.Value;
                }

                message.ApplicationProperties["ReplayApproved"] = true;
                message.ApplicationProperties["QuarantineId"] = quarantine.Id.ToString("D");
                message.ApplicationProperties["ReplayRequestId"] = request.Id.ToString("D");
                message.ApplicationProperties["ApprovedBy"] = request.ApprovedBy;
                message.ApplicationProperties["ApprovedUtc"] = request.ApprovedUtc.ToString("O");
                message.ApplicationProperties["AttemptCount"] = quarantine.ReplayAttemptCount;

                await sender.SendMessageAsync(message, cancellationToken).ConfigureAwait(false);
                request.PublishedUtc = DateTime.UtcNow;
                request.LastError = null;
                await dbContext.SaveChangesAsync(cancellationToken).ConfigureAwait(false);

                logger.LogInformation(
                    "Published approved replay request {ReplayRequestId} for quarantine {QuarantineId} and source message {SourceMessageId}.",
                    request.Id,
                    quarantine.Id,
                    quarantine.SourceMessageId);
            }
            catch (Exception ex)
            {
                request.LastError = ex.Message;
                await dbContext.SaveChangesAsync(cancellationToken).ConfigureAwait(false);
                logger.LogError(
                    ex,
                    "Failed to publish replay request {ReplayRequestId} for quarantine {QuarantineId}.",
                    request.Id,
                    request.QuarantineId);
            }
        }
    }

    private static IReadOnlyDictionary<string, object> DeserializeProperties(string json)
    {
        var source = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(json)
            ?? new Dictionary<string, JsonElement>(StringComparer.Ordinal);
        var result = new Dictionary<string, object>(StringComparer.Ordinal);
        foreach (var item in source)
        {
            result[item.Key] = item.Value.ValueKind switch
            {
                JsonValueKind.True => true,
                JsonValueKind.False => false,
                JsonValueKind.Number when item.Value.TryGetInt64(out var number) => number,
                _ => item.Value.ToString()
            };
        }

        return result;
    }
}
