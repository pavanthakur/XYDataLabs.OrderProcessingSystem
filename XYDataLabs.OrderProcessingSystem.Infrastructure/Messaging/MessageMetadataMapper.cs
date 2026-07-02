using System.Globalization;
using Azure.Messaging.ServiceBus;
using XYDataLabs.OrderProcessingSystem.Application.Events;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

public static class MessageMetadataMapper
{
    public static void Apply(ServiceBusMessage message, EventEnvelope envelope)
    {
        ArgumentNullException.ThrowIfNull(message);
        ArgumentNullException.ThrowIfNull(envelope);

        message.MessageId = Guid.NewGuid().ToString("D");
        message.CorrelationId = envelope.CorrelationId ?? envelope.MessageId.ToString("D");
        message.Subject = envelope.EventType;
        message.ContentType = "application/json";
        message.SessionId = envelope.TenantId?.ToString(CultureInfo.InvariantCulture);
        message.ApplicationProperties["EnvelopeMessageId"] = envelope.MessageId.ToString("D");
        message.ApplicationProperties["EventType"] = envelope.EventType;
        message.ApplicationProperties["SchemaVersion"] = envelope.SchemaVersion;
        message.ApplicationProperties["OccurredUtc"] = envelope.OccurredUtc.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture);
        message.ApplicationProperties["CorrelationId"] = message.CorrelationId ?? string.Empty;
        message.ApplicationProperties["CausationId"] = envelope.CausationId ?? string.Empty;
        message.ApplicationProperties["TraceParent"] = envelope.TraceParent ?? string.Empty;
        message.ApplicationProperties["TenantId"] = envelope.TenantId?.ToString(CultureInfo.InvariantCulture) ?? string.Empty;
        message.ApplicationProperties["AttemptCount"] = 0;
        message.ApplicationProperties["FailureCategory"] = string.Empty;
    }
}
