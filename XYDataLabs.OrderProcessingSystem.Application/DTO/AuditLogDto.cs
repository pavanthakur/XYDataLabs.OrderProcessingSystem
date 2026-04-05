namespace XYDataLabs.OrderProcessingSystem.Application.DTO;

public sealed class AuditLogDto
{
    public string EntityName { get; set; } = string.Empty;

    public string EntityId { get; set; } = string.Empty;

    public string Operation { get; set; } = string.Empty;

    public DateTime? ChangedAt { get; set; }

    public string? TraceId { get; set; }

    public string? CorrelationId { get; set; }

    public string? OldValues { get; set; }

    public string? NewValues { get; set; }
}