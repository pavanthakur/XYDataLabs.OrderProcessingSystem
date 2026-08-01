using SharedIntegrationEvent = XYDataLabs.OrderProcessingSystem.Eventing.Abstractions.IIntegrationEvent;

namespace XYDataLabs.OrderProcessingSystem.Application.Events;

public interface IDomainEventToIntegrationEventMapper
{
    Type DomainEventType { get; }
    Type IntegrationEventType { get; }
    int SchemaVersion { get; }
    EventEnvelope Map(object domainEvent, EventEnvelopeMetadata metadata);
}

public interface IDomainEventToIntegrationEventMapper<in TDomainEvent, out TIntegrationEvent> : IDomainEventToIntegrationEventMapper
    where TDomainEvent : class
    where TIntegrationEvent : class, SharedIntegrationEvent
{
    TIntegrationEvent Map(TDomainEvent domainEvent);
}
