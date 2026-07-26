namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

public sealed class DlqReplayRequest
{
    public Guid Id { get; set; }

    public Guid QuarantineId { get; set; }

    public DlqQuarantineRecord Quarantine { get; set; } = null!;

    public string ApprovedBy { get; set; } = string.Empty;

    public DateTime ApprovedUtc { get; set; }

    public DateTime? PublishedUtc { get; set; }

    public DateTime? ProcessedUtc { get; set; }

    public string? LastError { get; set; }
}
