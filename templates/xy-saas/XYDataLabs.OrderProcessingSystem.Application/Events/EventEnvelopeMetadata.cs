namespace XYDataLabs.OrderProcessingSystem.Application.Events;

public sealed record EventEnvelopeMetadata(
    Guid MessageId,
    DateTime OccurredUtc,
    string? CorrelationId = null,
    string? CausationId = null,
    string? TraceParent = null,
    int? TenantId = null)
{
    public static EventEnvelopeMetadata Create(
        DateTime occurredUtc,
        string? correlationId = null,
        string? causationId = null,
        string? traceParent = null,
        int? tenantId = null,
        Guid? messageId = null)
    {
        return new EventEnvelopeMetadata(
            messageId ?? Guid.NewGuid(),
            occurredUtc,
            correlationId,
            causationId,
            traceParent,
            tenantId);
    }
}