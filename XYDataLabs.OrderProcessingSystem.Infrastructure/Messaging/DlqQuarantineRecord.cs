namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

public sealed class DlqQuarantineRecord
{
    public Guid Id { get; set; }

    public string SourceMessageId { get; set; } = string.Empty;

    public int? TenantId { get; set; }

    public string? EventType { get; set; }

    public string? ContentType { get; set; }

    public string Body { get; set; } = string.Empty;

    public string ApplicationPropertiesJson { get; set; } = "{}";

    public string? CorrelationId { get; set; }

    public string? Subject { get; set; }

    public string FailureReason { get; set; } = string.Empty;

    public string? FailureDescription { get; set; }

    public int ReplayAttemptCount { get; set; }

    public string State { get; set; } = DlqQuarantineStates.Quarantined;

    public DateTime CreatedUtc { get; set; }

    public DateTime? ApprovedUtc { get; set; }

    public string? ApprovedBy { get; set; }

    public DateTime? ReplayedUtc { get; set; }
}

public static class DlqQuarantineStates
{
    public const string Quarantined = "Quarantined";
    public const string Approved = "Approved";
    public const string Replayed = "Replayed";
    public const string Rejected = "Rejected";
}
