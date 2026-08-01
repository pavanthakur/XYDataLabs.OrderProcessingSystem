namespace XYDataLabs.OrderProcessingSystem.Domain.Entities;

public sealed class ConsumerInboxMessage
{
    public Guid Id { get; set; }

    public int TenantId { get; set; }

    public string ConsumerName { get; set; } = string.Empty;

    public Guid MessageId { get; set; }

    public string EventType { get; set; } = string.Empty;

    public string? CorrelationId { get; set; }

    public DateTime EnqueuedUtc { get; set; }

    public DateTime ReceivedUtc { get; set; }

    public DateTime? ProcessedUtc { get; set; }
}
