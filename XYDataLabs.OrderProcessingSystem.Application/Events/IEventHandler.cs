namespace XYDataLabs.OrderProcessingSystem.Application.Events;

public interface IEventHandler<in TIntegrationEvent>
    where TIntegrationEvent : class, IIntegrationEvent
{
    Task HandleAsync(EventEnvelope envelope, TIntegrationEvent integrationEvent, CancellationToken cancellationToken = default);
}