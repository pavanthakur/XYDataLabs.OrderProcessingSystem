namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

public sealed class NotificationDelivery
{
    public Guid Id { get; set; }

    public int TenantId { get; set; }

    public Guid OrderReferenceId { get; set; }

    public string NotificationType { get; set; } = string.Empty;

    public string Sink { get; set; } = "local-deterministic";

    public DateTime AcceptedUtc { get; set; }

    public string? CorrelationId { get; set; }
}
