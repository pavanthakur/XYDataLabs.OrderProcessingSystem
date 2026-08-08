namespace XYDataLabs.OrderProcessingSystem.Application.Abstractions;

public interface IDlqReplayApprovalService
{
    Task<DlqReplayApprovalResult?> ApproveAsync(
        Guid quarantineId,
        string approvedBy,
        CancellationToken cancellationToken);
}

public sealed record DlqReplayApprovalResult(
    Guid QuarantineId,
    Guid ReplayRequestId,
    string State,
    DateTime ApprovedUtc,
    bool AlreadyApproved);
