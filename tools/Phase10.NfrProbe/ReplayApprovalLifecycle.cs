namespace XYDataLabs.OrderProcessingSystem.Tools.Phase10.NfrProbe;

internal sealed class ReplayApprovalLifecycle
{
    public const string NotStarted = "not-started";
    public const string SubmissionIntended = "submission-intended";
    public const string Approved = "approved";
    public const string ProcessingConfirmed = "processing-confirmed";

    public string Status { get; private set; } = NotStarted;

    public bool RequiresReconciliation => Status is SubmissionIntended or Approved;

    public bool CanReportSuccess => Status == ProcessingConfirmed;

    public void MarkSubmissionIntended()
    {
        RequireStatus(NotStarted);
        Status = SubmissionIntended;
    }

    public void MarkApproved()
    {
        RequireStatus(SubmissionIntended);
        Status = Approved;
    }

    public void MarkProcessingConfirmed()
    {
        RequireStatus(Approved);
        Status = ProcessingConfirmed;
    }

    public static bool IsConsistent(string overallStatus, string approvalStatus)
        => !string.Equals(overallStatus, "passed", StringComparison.OrdinalIgnoreCase)
            || string.Equals(approvalStatus, ProcessingConfirmed, StringComparison.Ordinal);

    private void RequireStatus(string expected)
    {
        if (Status != expected)
        {
            throw new InvalidOperationException(
                $"Replay approval lifecycle cannot move from '{Status}' when '{expected}' is required.");
        }
    }
}
