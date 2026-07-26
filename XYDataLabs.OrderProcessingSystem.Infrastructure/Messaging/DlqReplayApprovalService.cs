using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;

namespace XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;

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

public sealed class DlqReplayApprovalService(
    OrderProcessingSystemDbContext dbContext,
    TimeProvider timeProvider) : IDlqReplayApprovalService
{
    public async Task<DlqReplayApprovalResult?> ApproveAsync(
        Guid quarantineId,
        string approvedBy,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(approvedBy))
        {
            throw new ArgumentException("The approving identity is required.", nameof(approvedBy));
        }

        var quarantine = await dbContext.DlqQuarantineRecords
            .SingleOrDefaultAsync(item => item.Id == quarantineId, cancellationToken)
            .ConfigureAwait(false);
        if (quarantine is null)
        {
            return null;
        }

        var existingRequest = await dbContext.DlqReplayRequests
            .AsNoTracking()
            .SingleOrDefaultAsync(item => item.QuarantineId == quarantineId, cancellationToken)
            .ConfigureAwait(false);
        if (existingRequest is not null)
        {
            return new DlqReplayApprovalResult(
                quarantineId,
                existingRequest.Id,
                quarantine.State,
                existingRequest.ApprovedUtc,
                AlreadyApproved: true);
        }

        if (quarantine.State is DlqQuarantineStates.Rejected or DlqQuarantineStates.Replayed)
        {
            throw new InvalidOperationException(
                $"Quarantine record {quarantineId} cannot be approved from state {quarantine.State}.");
        }

        var approvedUtc = timeProvider.GetUtcNow().UtcDateTime;
        var replayRequest = new DlqReplayRequest
        {
            Id = Guid.NewGuid(),
            QuarantineId = quarantineId,
            ApprovedBy = approvedBy.Trim(),
            ApprovedUtc = approvedUtc
        };

        quarantine.State = DlqQuarantineStates.Approved;
        quarantine.ApprovedBy = replayRequest.ApprovedBy;
        quarantine.ApprovedUtc = approvedUtc;
        dbContext.DlqReplayRequests.Add(replayRequest);

        try
        {
            await dbContext.SaveChangesAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (DbUpdateException)
        {
            dbContext.ChangeTracker.Clear();
            existingRequest = await dbContext.DlqReplayRequests
                .AsNoTracking()
                .SingleOrDefaultAsync(item => item.QuarantineId == quarantineId, cancellationToken)
                .ConfigureAwait(false);
            if (existingRequest is null)
            {
                throw;
            }

            return new DlqReplayApprovalResult(
                quarantineId,
                existingRequest.Id,
                DlqQuarantineStates.Approved,
                existingRequest.ApprovedUtc,
                AlreadyApproved: true);
        }

        return new DlqReplayApprovalResult(
            quarantineId,
            replayRequest.Id,
            quarantine.State,
            approvedUtc,
            AlreadyApproved: false);
    }
}
