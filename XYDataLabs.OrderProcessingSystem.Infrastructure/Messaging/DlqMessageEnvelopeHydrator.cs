using System.Globalization;
using System.Text.Json;
using Azure.Messaging.ServiceBus;
using XYDataLabs.OrderProcessingSystem.Application.Events;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

public static class DlqMessageEnvelopeHydrator
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public static bool TryHydrateEnvelope(
        ServiceBusReceivedMessage message,
        IIntegrationEventTypeResolver typeResolver,
        out EventEnvelope envelope,
        out string? failureReason)
    {
        ArgumentNullException.ThrowIfNull(message);
        ArgumentNullException.ThrowIfNull(typeResolver);

        envelope = default!;
        failureReason = null;

        var eventType = ReadStringProperty(message, "EventType") ?? message.Subject;
        if (string.IsNullOrWhiteSpace(eventType))
        {
            failureReason = "Missing event type metadata.";
            return false;
        }

        var payloadType = typeResolver.ResolveType(eventType);
        if (payloadType is null)
        {
            failureReason = $"Unresolved integration event type: {eventType}.";
            return false;
        }

        object? payload;
        try
        {
            payload = JsonSerializer.Deserialize(message.Body.ToString(), payloadType, JsonOptions);
        }
        catch (Exception ex)
        {
            failureReason = $"Failed to deserialize payload for {eventType}: {ex.Message}";
            return false;
        }

        if (payload is null)
        {
            failureReason = $"Payload deserialization returned null for {eventType}.";
            return false;
        }

        var envelopeMessageId = ReadGuidProperty(message, "EnvelopeMessageId") ?? ReadGuidProperty(message, "MessageId") ?? Guid.NewGuid();
        var occurredUtc = ReadDateTimeUtc(message, "OccurredUtc") ?? message.EnqueuedTime.UtcDateTime;
        var schemaVersion = ReadInt32Property(message, "SchemaVersion") ?? 1;
        var correlationId = message.CorrelationId ?? ReadStringProperty(message, "CorrelationId");
        var causationId = ReadStringProperty(message, "CausationId");
        var traceParent = ReadStringProperty(message, "TraceParent");
        var tenantId = ReadInt32Property(message, "TenantId");

        envelope = EventEnvelope.Create(
            eventType,
            schemaVersion,
            occurredUtc,
            payload,
            envelopeMessageId,
            correlationId,
            causationId,
            traceParent,
            tenantId);

        return true;
    }

    public static bool IsPoison(string deadLetterReason, string deadLetterDescription, string? failureReason)
    {
        var combined = $"{deadLetterReason} {deadLetterDescription} {failureReason ?? string.Empty}".Trim();

        return combined.Contains("poison", StringComparison.OrdinalIgnoreCase)
            || combined.Contains("deserial", StringComparison.OrdinalIgnoreCase)
            || combined.Contains("unresolved", StringComparison.OrdinalIgnoreCase)
            || combined.Contains("validation", StringComparison.OrdinalIgnoreCase)
            || combined.Contains("expired", StringComparison.OrdinalIgnoreCase);
    }

    private static string? ReadStringProperty(ServiceBusReceivedMessage message, string propertyName)
    {
        if (!message.ApplicationProperties.TryGetValue(propertyName, out var raw) || raw is null)
        {
            return null;
        }

        return raw switch
        {
            string value => value,
            Guid value => value.ToString("D"),
            DateTime value => value.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture),
            DateTimeOffset value => value.UtcDateTime.ToString("O", CultureInfo.InvariantCulture),
            _ => Convert.ToString(raw, CultureInfo.InvariantCulture)
        };
    }

    private static Guid? ReadGuidProperty(ServiceBusReceivedMessage message, string propertyName)
    {
        var value = ReadStringProperty(message, propertyName);
        return Guid.TryParse(value, out var parsed) ? parsed : null;
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
            string value when int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed) => parsed,
            _ when int.TryParse(Convert.ToString(raw, CultureInfo.InvariantCulture), NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed) => parsed,
            _ => null
        };
    }

    private static DateTime? ReadDateTimeUtc(ServiceBusReceivedMessage message, string propertyName)
    {
        var value = ReadStringProperty(message, propertyName);
        return DateTimeOffset.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var parsed)
            ? parsed.UtcDateTime
            : null;
    }
}
