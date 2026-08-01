using SharedIntegrationEvent = XYDataLabs.OrderProcessingSystem.Eventing.Abstractions.IIntegrationEvent;

namespace XYDataLabs.OrderProcessingSystem.Application.Events;

public interface IEventHandler<in TIntegrationEvent>
    where TIntegrationEvent : class, SharedIntegrationEvent
{
    Task HandleAsync(EventEnvelope envelope, TIntegrationEvent integrationEvent, CancellationToken cancellationToken = default);
}
