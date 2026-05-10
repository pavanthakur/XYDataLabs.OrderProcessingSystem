namespace XYDataLabs.OrderProcessingSystem.Application.Events;

public interface IEventPublisher
{
    Task PublishAsync(EventEnvelope eventEnvelope, CancellationToken cancellationToken = default);
}