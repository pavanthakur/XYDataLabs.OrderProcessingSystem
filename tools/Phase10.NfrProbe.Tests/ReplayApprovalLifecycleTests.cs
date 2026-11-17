using XYDataLabs.OrderProcessingSystem.Tools.Phase10.NfrProbe;

namespace XYDataLabs.OrderProcessingSystem.Tools.Phase10.NfrProbe.Tests;

public sealed class ReplayApprovalLifecycleTests
{
    [Fact]
    public void SuccessfulReplayAdvancesThroughExplicitStates()
    {
        var lifecycle = new ReplayApprovalLifecycle();

        Assert.Equal(ReplayApprovalLifecycle.NotStarted, lifecycle.Status);
        Assert.False(lifecycle.RequiresReconciliation);
        Assert.False(lifecycle.CanReportSuccess);

        lifecycle.MarkSubmissionIntended();
        Assert.Equal(ReplayApprovalLifecycle.SubmissionIntended, lifecycle.Status);
        Assert.True(lifecycle.RequiresReconciliation);

        lifecycle.MarkApproved();
        Assert.Equal(ReplayApprovalLifecycle.Approved, lifecycle.Status);
        Assert.True(lifecycle.RequiresReconciliation);

        lifecycle.MarkProcessingConfirmed();
        Assert.Equal(ReplayApprovalLifecycle.ProcessingConfirmed, lifecycle.Status);
        Assert.False(lifecycle.RequiresReconciliation);
        Assert.True(lifecycle.CanReportSuccess);
        Assert.True(ReplayApprovalLifecycle.IsConsistent("passed", lifecycle.Status));
    }

    [Theory]
    [InlineData("pending-reconciliation")]
    [InlineData(ReplayApprovalLifecycle.NotStarted)]
    [InlineData(ReplayApprovalLifecycle.SubmissionIntended)]
    [InlineData(ReplayApprovalLifecycle.Approved)]
    public void SuccessfulTerminalResultRejectsUnconfirmedApproval(string approvalStatus)
    {
        Assert.False(ReplayApprovalLifecycle.IsConsistent("passed", approvalStatus));
    }

    [Theory]
    [InlineData(ReplayApprovalLifecycle.NotStarted)]
    [InlineData(ReplayApprovalLifecycle.SubmissionIntended)]
    [InlineData(ReplayApprovalLifecycle.Approved)]
    public void FailureMayPreserveLastKnownApprovalState(string approvalStatus)
    {
        Assert.True(ReplayApprovalLifecycle.IsConsistent("failed", approvalStatus));
    }

    [Fact]
    public void CannotSkipApprovalBeforeConfirmingReplayProcessing()
    {
        var lifecycle = new ReplayApprovalLifecycle();

        Assert.Throws<InvalidOperationException>(lifecycle.MarkApproved);
        Assert.Throws<InvalidOperationException>(lifecycle.MarkProcessingConfirmed);
        Assert.False(lifecycle.CanReportSuccess);
    }
}
