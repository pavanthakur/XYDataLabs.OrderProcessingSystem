using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using System.Text.Json;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

namespace XYDataLabs.OrderProcessingSystem.Functions;

public sealed class DlqIntakeFunction(
    OrderProcessingSystemDbContext dbContext,
    TimeProvider timeProvider,
    ILogger<DlqIntakeFunction> logger)
{
    [Function(nameof(DlqIntakeFunction))]
    public async Task RunAsync(
        [ServiceBusTrigger(
            "%Phase10DlqTopicName%",
            "%Phase10DlqIntakeSubscriptionName%",
            Connection = "ServiceBusConnection",
            AutoCompleteMessages = false)]
        ServiceBusReceivedMessage message,
        ServiceBusMessageActions messageActions,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(message);
        ArgumentNullException.ThrowIfNull(messageActions);

        var quarantineReason = message.ApplicationProperties.TryGetValue("FailureCategory", out var failureCategory)
            && failureCategory is not null
                ? $"quarantined-{failureCategory}"
                : "quarantined-awaiting-classification";

        var existing = await dbContext.DlqQuarantineRecords
            .AsNoTracking()
            .SingleOrDefaultAsync(
                item => item.SourceMessageId == message.MessageId,
                cancellationToken)
            .ConfigureAwait(false);

        if (existing is null)
        {
            var tenantId = ReadInt32Property(message, "TenantId");
            var replayAttempts = ReadInt32Property(message, "AttemptCount") ?? message.DeliveryCount;
            var record = new DlqQuarantineRecord
            {
                Id = Guid.NewGuid(),
                SourceMessageId = message.MessageId,
                TenantId = tenantId,
                EventType = ReadStringProperty(message, "EventType") ?? message.Subject,
                ContentType = message.ContentType,
                Body = message.Body.ToString(),
                ApplicationPropertiesJson = JsonSerializer.Serialize(message.ApplicationProperties),
                CorrelationId = message.CorrelationId,
                Subject = message.Subject,
                FailureReason = message.DeadLetterReason ?? quarantineReason,
                FailureDescription = message.DeadLetterErrorDescription,
                ReplayAttemptCount = replayAttempts,
                State = DlqQuarantineStates.Quarantined,
                CreatedUtc = timeProvider.GetUtcNow().UtcDateTime
            };
            dbContext.DlqQuarantineRecords.Add(record);
            try
            {
                await dbContext.SaveChangesAsync(cancellationToken).ConfigureAwait(false);
                existing = record;
            }
            catch (DbUpdateException)
            {
                dbContext.ChangeTracker.Clear();
                existing = await dbContext.DlqQuarantineRecords
                    .AsNoTracking()
                    .SingleAsync(
                        item => item.SourceMessageId == message.MessageId,
                        cancellationToken)
                    .ConfigureAwait(false);
            }
        }

        await messageActions.CompleteMessageAsync(message, cancellationToken).ConfigureAwait(false);

        logger.LogWarning(
            "Phase 10 DLQ intake persisted quarantine {QuarantineId} for message {MessageId}, tenant {TenantId}, subject {Subject}, and reason {QuarantineReason}.",
            existing.Id,
            message.MessageId,
            existing.TenantId,
            message.Subject,
            quarantineReason);
    }

    private static string? ReadStringProperty(ServiceBusReceivedMessage message, string propertyName)
    {
        return message.ApplicationProperties.TryGetValue(propertyName, out var raw) && raw is not null
            ? Convert.ToString(raw)
            : null;
    }

    private static int? ReadInt32Property(ServiceBusReceivedMessage message, string propertyName)
    {
        if (!message.ApplicationProperties.TryGetValue(propertyName, out var raw) || raw is null)
        {
            return null;
        }

        return raw switch
        {
            int value => value,
            long value when value is >= int.MinValue and <= int.MaxValue => (int)value,
            _ when int.TryParse(Convert.ToString(raw), out var parsed) => parsed,
            _ => null
        };
    }
}
