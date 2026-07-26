using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

namespace XYDataLabs.OrderProcessingSystem.Functions;

public sealed class DlqReplayFunction(
    IServiceProvider serviceProvider,
    ILogger<DlqReplayFunction> logger)
{
    [Function(nameof(DlqReplayFunction))]
    public async Task RunAsync(
        [ServiceBusTrigger(
            "%Phase10ReplayRequestQueueName%",
            Connection = "ServiceBusConnection",
            AutoCompleteMessages = false)]
        ServiceBusReceivedMessage message,
        ServiceBusMessageActions messageActions,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(message);
        ArgumentNullException.ThrowIfNull(messageActions);

        var options = serviceProvider.GetRequiredService<IOptions<ServiceBusOptions>>().Value;
        if (!options.Enabled || !options.ReplayEnabled)
        {
            await messageActions.AbandonMessageAsync(
                    message,
                    cancellationToken: cancellationToken)
                .ConfigureAwait(false);

            logger.LogInformation(
                "DLQ replay is disabled. Request {MessageId} from {Subject} was abandoned without replay.",
                message.MessageId,
                message.Subject);
            return;
        }

        if (!IsApproved(message, out var quarantineId))
        {
            await messageActions.DeadLetterMessageAsync(
                    message,
                    null,
                    "dlq-replay-not-approved",
                    "Replay requests require ReplayApproved=true and a QuarantineId.",
                    cancellationToken)
                .ConfigureAwait(false);
            logger.LogWarning(
                "DLQ replay function rejected unapproved replay request {MessageId}.",
                message.MessageId);
            return;
        }

        var client = serviceProvider.GetRequiredService<ServiceBusClient>();
        var typeResolver = serviceProvider.GetRequiredService<IIntegrationEventTypeResolver>();

        await using var sender = client.CreateSender(options.TopicName);

        if (!DlqMessageEnvelopeHydrator.TryHydrateEnvelope(message, typeResolver, out var envelope, out var failureReason))
        {
            await messageActions.DeadLetterMessageAsync(message, null, "dlq-unclassified", failureReason ?? string.Empty, cancellationToken)
                .ConfigureAwait(false);
            logger.LogWarning(
                "DLQ replay function quarantined message {MessageId} because it could not be classified.",
                message.MessageId);
            return;
        }

        var attemptCount = ReadInt32Property(message, "AttemptCount") ?? message.DeliveryCount;
        var deadLetterReason = message.DeadLetterReason ?? string.Empty;
        var deadLetterDescription = message.DeadLetterErrorDescription ?? string.Empty;

        if (attemptCount >= options.MaxReplayAttempts || DlqMessageEnvelopeHydrator.IsPoison(deadLetterReason, deadLetterDescription, failureReason))
        {
            var reason = $"Non-replayable after {attemptCount} attempt(s).";
            var description = failureReason ?? deadLetterDescription ?? deadLetterReason;
            await messageActions.DeadLetterMessageAsync(message, null, reason, description ?? string.Empty, cancellationToken)
                .ConfigureAwait(false);

            logger.LogWarning(
                "DLQ replay function quarantined message {MessageId} after {AttemptCount} attempt(s).",
                message.MessageId,
                attemptCount);
            return;
        }

        var replayedMessage = new ServiceBusMessage(message.Body)
        {
            MessageId = envelope.MessageId.ToString("D"),
            Subject = message.Subject ?? envelope.EventType,
            ContentType = message.ContentType ?? "application/json",
            CorrelationId = message.CorrelationId ?? envelope.CorrelationId,
            TimeToLive = options.MessageTtl
        };
        foreach (var property in message.ApplicationProperties)
        {
            if (property.Key is not ("ReplayApproved" or "ApprovedBy" or "ApprovedUtc"))
            {
                replayedMessage.ApplicationProperties[property.Key] = property.Value;
            }
        }

        replayedMessage.ApplicationProperties["AttemptCount"] = attemptCount + 1;
        replayedMessage.ApplicationProperties["FailureCategory"] = "replayed";
        replayedMessage.ApplicationProperties["ReplaySourceMessageId"] = message.MessageId;
        replayedMessage.ApplicationProperties["ReplaySourceDeadLetterReason"] = deadLetterReason;
        replayedMessage.ApplicationProperties["ReplaySourceDeadLetterDescription"] = deadLetterDescription;
        replayedMessage.ApplicationProperties["ReplayAttempt"] = attemptCount + 1;
        replayedMessage.ApplicationProperties["QuarantineId"] = quarantineId;
        replayedMessage.TimeToLive = options.MessageTtl;

        await sender.SendMessageAsync(replayedMessage, cancellationToken).ConfigureAwait(false);
        await MarkReplayProcessedAsync(message, quarantineId, cancellationToken).ConfigureAwait(false);
        await messageActions.CompleteMessageAsync(message, cancellationToken).ConfigureAwait(false);

        logger.LogInformation(
            "DLQ replay function replayed message {EnvelopeMessageId} for event {EventType} after {AttemptCount} attempt(s).",
            envelope.MessageId,
            envelope.EventType,
            attemptCount);
    }

    private async Task MarkReplayProcessedAsync(
        ServiceBusReceivedMessage message,
        string quarantineId,
        CancellationToken cancellationToken)
    {
        var dbContext = serviceProvider.GetRequiredService<OrderProcessingSystemDbContext>();
        var parsedQuarantineId = Guid.Parse(quarantineId);
        var quarantine = await dbContext.DlqQuarantineRecords
            .SingleAsync(item => item.Id == parsedQuarantineId, cancellationToken)
            .ConfigureAwait(false);

        DlqReplayRequest? request = null;
        if (message.ApplicationProperties.TryGetValue("ReplayRequestId", out var requestRaw)
            && Guid.TryParse(Convert.ToString(requestRaw), out var replayRequestId))
        {
            request = await dbContext.DlqReplayRequests
                .SingleOrDefaultAsync(item => item.Id == replayRequestId, cancellationToken)
                .ConfigureAwait(false);
        }

        var processedUtc = DateTime.UtcNow;
        quarantine.State = DlqQuarantineStates.Replayed;
        quarantine.ReplayedUtc = processedUtc;
        quarantine.ReplayAttemptCount++;
        if (request is not null)
        {
            request.ProcessedUtc = processedUtc;
            request.LastError = null;
        }

        await dbContext.SaveChangesAsync(cancellationToken).ConfigureAwait(false);
    }

    private static bool IsApproved(ServiceBusReceivedMessage message, out string quarantineId)
    {
        quarantineId = string.Empty;
        if (!message.ApplicationProperties.TryGetValue("ReplayApproved", out var approvedRaw)
            || !bool.TryParse(Convert.ToString(approvedRaw), out var approved)
            || !approved)
        {
            return false;
        }

        if (!message.ApplicationProperties.TryGetValue("QuarantineId", out var quarantineRaw))
        {
            return false;
        }

        quarantineId = Convert.ToString(quarantineRaw) ?? string.Empty;
        return Guid.TryParse(quarantineId, out _);
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
            string value when int.TryParse(value, out var parsed) => parsed,
            _ when int.TryParse(Convert.ToString(raw), out var parsed) => parsed,
            _ => null
        };
    }
}
