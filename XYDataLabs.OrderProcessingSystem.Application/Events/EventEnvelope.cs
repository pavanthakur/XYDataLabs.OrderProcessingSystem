namespace XYDataLabs.OrderProcessingSystem.Application.Events;

public sealed record EventEnvelope(
    Guid MessageId,
    string EventType,
    int SchemaVersion,
    DateTime OccurredUtc,
    object Payload,
    string? CorrelationId = null,
    string? CausationId = null,
    string? TraceParent = null,
    int? TenantId = null)
{
    public static EventEnvelope Create(
        string eventType,
        int schemaVersion,
        DateTime occurredUtc,
        object payload,
        Guid? messageId = null,
        string? correlationId = null,
        string? causationId = null,
        string? traceParent = null,
        int? tenantId = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(eventType);
        ArgumentNullException.ThrowIfNull(payload);

        return new EventEnvelope(
            messageId ?? Guid.NewGuid(),
            eventType,
            schemaVersion,
            occurredUtc,
            payload,
            correlationId,
            causationId,
            traceParent,
            tenantId);
    }
}