using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

namespace XYDataLabs.OrderProcessingSystem.Functions;

public sealed class DlqReplayFunction(
    IServiceProvider serviceProvider,
    TimeProvider timeProvider,
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

        await RunCoreAsync(
                message,
                new ServiceBusMessageActionsAdapter(message, messageActions),
                cancellationToken)
            .ConfigureAwait(false);
    }

    internal async Task RunCoreAsync(
        ServiceBusReceivedMessage message,
        IDlqReplayMessageActions messageActions,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(message);
        ArgumentNullException.ThrowIfNull(messageActions);

        var options = serviceProvider.GetRequiredService<IOptions<ServiceBusOptions>>().Value;
        if (!options.Enabled || !options.ReplayEnabled)
        {
            await messageActions.AbandonAsync(cancellationToken).ConfigureAwait(false);

            logger.LogInformation(
                "DLQ replay is disabled. Request {MessageId} from {Subject} was abandoned without replay.",
                message.MessageId,
                message.Subject);
            return;
        }

        if (!IsApproved(message, out var quarantineId))
        {
            await messageActions.DeadLetterAsync(
                    "dlq-replay-not-approved",
                    "Replay requests require ReplayApproved=true and a QuarantineId.",
                    cancellationToken)
                .ConfigureAwait(false);
            logger.LogWarning(
                "DLQ replay function rejected unapproved replay request {MessageId}.",
                message.MessageId);
            return;
        }

        var replayState = await LoadReplayStateAsync(message, quarantineId, cancellationToken).ConfigureAwait(false);
        if (replayState is null)
        {
            await messageActions.DeadLetterAsync(
                    "replay-request-not-found",
                    "Replay requests must resolve to one persisted approved replay request.",
                    cancellationToken)
                .ConfigureAwait(false);
            logger.LogWarning(
                "DLQ replay function rejected replay request {MessageId} because no persisted replay request was found.",
                message.MessageId);
            return;
        }

        if (replayState.Request.ProcessedUtc is not null || replayState.Quarantine.State == DlqQuarantineStates.Replayed)
        {
            await messageActions.CompleteAsync(cancellationToken).ConfigureAwait(false);
            logger.LogInformation(
                "DLQ replay function ignored already-processed replay request {ReplayRequestId} for quarantine {QuarantineId}.",
                replayState.Request.Id,
                replayState.Quarantine.Id);
            return;
        }

        if (replayState.Quarantine.State != DlqQuarantineStates.Approved)
        {
            await RejectReplayAsync(
                    replayState,
                    "dlq-replay-not-approved-state",
                    $"Replay request requires Approved state but found {replayState.Quarantine.State}.",
                    cancellationToken)
                .ConfigureAwait(false);
            await messageActions.DeadLetterAsync(
                    "dlq-replay-not-approved-state",
                    $"Replay request requires Approved state but found {replayState.Quarantine.State}.",
                    cancellationToken)
                .ConfigureAwait(false);
            logger.LogWarning(
                "DLQ replay function rejected replay request {ReplayRequestId} for quarantine {QuarantineId} from state {State}.",
                replayState.Request.Id,
                replayState.Quarantine.Id,
                replayState.Quarantine.State);
            return;
        }

        var typeResolver = serviceProvider.GetRequiredService<IIntegrationEventTypeResolver>();


        if (!DlqMessageEnvelopeHydrator.TryHydrateEnvelope(message, typeResolver, out var envelope, out var failureReason))
        {
            await RejectReplayAsync(
                    replayState,
                    "dlq-unclassified",
                    failureReason ?? string.Empty,
                    cancellationToken)
                .ConfigureAwait(false);
            await messageActions.DeadLetterAsync("dlq-unclassified", failureReason ?? string.Empty, cancellationToken)
                .ConfigureAwait(false);
            logger.LogWarning(
                "DLQ replay function quarantined message {MessageId} because it could not be classified.",
                message.MessageId);
            return;
        }

        var attemptCount = Math.Max(
            replayState.Quarantine.ReplayAttemptCount,
            ReadInt32Property(message, "AttemptCount") ?? message.DeliveryCount);
        var deadLetterReason = replayState.Quarantine.FailureReason ?? string.Empty;
        var deadLetterDescription = replayState.Quarantine.FailureDescription ?? string.Empty;

        if (attemptCount >= options.MaxReplayAttempts || DlqMessageEnvelopeHydrator.IsPoison(deadLetterReason, deadLetterDescription, failureReason))
        {
            var reason = $"Non-replayable after {attemptCount} attempt(s).";
            var description = failureReason ?? deadLetterDescription ?? deadLetterReason;
            await RejectReplayAsync(
                    replayState,
                    reason,
                    description ?? string.Empty,
                    cancellationToken)
                .ConfigureAwait(false);
            await messageActions.DeadLetterAsync(reason, description ?? string.Empty, cancellationToken)
                .ConfigureAwait(false);

            logger.LogWarning(
                "DLQ replay function quarantined message {MessageId} after {AttemptCount} attempt(s).",
                message.MessageId,
                attemptCount);
            return;
        }

        var publisher = serviceProvider.GetRequiredService<IDlqReplayPublisher>();
        var replayedMessage = new ServiceBusMessage(message.Body)
        {
            MessageId = envelope.MessageId.ToString("D"),
            Subject = message.Subject ?? envelope.EventType,
            ContentType = message.ContentType ?? "application/json",
            CorrelationId = message.CorrelationId ?? envelope.CorrelationId,
            TimeToLive = options.MessageTtlTimeSpan
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
        replayedMessage.ApplicationProperties["ReplaySourceMessageId"] = replayState.Quarantine.SourceMessageId;
        replayedMessage.ApplicationProperties["ReplaySourceDeadLetterReason"] = deadLetterReason;
        replayedMessage.ApplicationProperties["ReplaySourceDeadLetterDescription"] = deadLetterDescription;
        replayedMessage.ApplicationProperties["ReplayAttempt"] = attemptCount + 1;
        replayedMessage.ApplicationProperties["QuarantineId"] = quarantineId;
        replayedMessage.TimeToLive = options.MessageTtlTimeSpan;

        await publisher.PublishAsync(replayedMessage, cancellationToken).ConfigureAwait(false);
        await MarkReplayProcessedAsync(replayState, cancellationToken).ConfigureAwait(false);
        await messageActions.CompleteAsync(cancellationToken).ConfigureAwait(false);

        logger.LogInformation(
            "DLQ replay function replayed message {EnvelopeMessageId} for event {EventType} after {AttemptCount} attempt(s).",
            envelope.MessageId,
            envelope.EventType,
            attemptCount);
    }

    internal async Task<DlqReplayState?> LoadReplayStateAsync(
        ServiceBusReceivedMessage message,
        string quarantineId,
        CancellationToken cancellationToken)
    {
        if (!message.ApplicationProperties.TryGetValue("ReplayRequestId", out var requestRaw)
            || !Guid.TryParse(Convert.ToString(requestRaw), out var replayRequestId))
        {
            return null;
        }

        using var scope = serviceProvider.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<OrderProcessingSystemDbContext>();
        var parsedQuarantineId = Guid.Parse(quarantineId);
        var request = await dbContext.DlqReplayRequests
            .SingleOrDefaultAsync(item => item.Id == replayRequestId && item.QuarantineId == parsedQuarantineId, cancellationToken)
            .ConfigureAwait(false);
        if (request is null)
        {
            return null;
        }

        var quarantine = await dbContext.DlqQuarantineRecords
            .SingleAsync(item => item.Id == parsedQuarantineId, cancellationToken)
            .ConfigureAwait(false);

        return new DlqReplayState(request, quarantine);
    }

    internal async Task MarkReplayProcessedAsync(
        DlqReplayState replayState,
        CancellationToken cancellationToken)
    {
        using var scope = serviceProvider.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<OrderProcessingSystemDbContext>();
        var quarantine = await dbContext.DlqQuarantineRecords
            .SingleAsync(item => item.Id == replayState.Quarantine.Id, cancellationToken)
            .ConfigureAwait(false);
        var request = await dbContext.DlqReplayRequests
            .SingleAsync(item => item.Id == replayState.Request.Id, cancellationToken)
            .ConfigureAwait(false);

        var processedUtc = timeProvider.GetUtcNow().UtcDateTime;
        quarantine.State = DlqQuarantineStates.Replayed;
        quarantine.ReplayedUtc = processedUtc;
        quarantine.ReplayAttemptCount++;
        request.ProcessedUtc = processedUtc;
        request.LastError = null;

        await dbContext.SaveChangesAsync(cancellationToken).ConfigureAwait(false);
    }

    internal async Task RejectReplayAsync(
        DlqReplayState replayState,
        string reason,
        string description,
        CancellationToken cancellationToken)
    {
        using var scope = serviceProvider.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<OrderProcessingSystemDbContext>();
        var quarantine = await dbContext.DlqQuarantineRecords
            .SingleAsync(item => item.Id == replayState.Quarantine.Id, cancellationToken)
            .ConfigureAwait(false);
        var request = await dbContext.DlqReplayRequests
            .SingleAsync(item => item.Id == replayState.Request.Id, cancellationToken)
            .ConfigureAwait(false);

        quarantine.State = DlqQuarantineStates.Rejected;
        request.LastError = string.IsNullOrWhiteSpace(description) ? reason : $"{reason}: {description}";

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
