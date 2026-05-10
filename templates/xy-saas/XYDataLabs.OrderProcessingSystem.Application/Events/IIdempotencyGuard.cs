namespace XYDataLabs.OrderProcessingSystem.Application.Events;

public interface IIdempotencyGuard
{
    Task<bool> HasProcessedAsync(Guid messageId, CancellationToken cancellationToken = default);
    Task MarkProcessedAsync(Guid messageId, CancellationToken cancellationToken = default);
}