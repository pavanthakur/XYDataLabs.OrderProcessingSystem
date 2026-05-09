namespace XYDataLabs.OrderProcessingSystem.Application.Events;

public interface IEventHandler<in TIntegrationEvent>
    where TIntegrationEvent : class, IIntegrationEvent
{
    Task HandleAsync(TIntegrationEvent integrationEvent, CancellationToken cancellationToken = default);
}