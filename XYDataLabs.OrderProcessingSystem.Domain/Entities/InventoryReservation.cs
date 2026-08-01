namespace XYDataLabs.OrderProcessingSystem.Domain.Entities;

public sealed class InventoryReservation
{
    public Guid Id { get; set; }

    public int TenantId { get; set; }

    public Guid OrderReferenceId { get; set; }

    public int ProductCount { get; set; }

    public DateTime ReservedUtc { get; set; }

    public string? CorrelationId { get; set; }
}
