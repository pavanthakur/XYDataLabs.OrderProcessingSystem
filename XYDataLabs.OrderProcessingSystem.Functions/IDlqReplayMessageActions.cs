namespace XYDataLabs.OrderProcessingSystem.Functions;

internal interface IDlqReplayMessageActions
{
    Task AbandonAsync(CancellationToken cancellationToken);

    Task DeadLetterAsync(string reason, string description, CancellationToken cancellationToken);

    Task CompleteAsync(CancellationToken cancellationToken);
}
