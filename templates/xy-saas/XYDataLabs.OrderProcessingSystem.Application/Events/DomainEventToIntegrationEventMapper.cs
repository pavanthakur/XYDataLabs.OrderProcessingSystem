namespace XYDataLabs.OrderProcessingSystem.Application.Events;

public abstract class DomainEventToIntegrationEventMapper<TDomainEvent, TIntegrationEvent> : IDomainEventToIntegrationEventMapper<TDomainEvent, TIntegrationEvent>
    where TDomainEvent : class
    where TIntegrationEvent : class, IIntegrationEvent
{
    public Type DomainEventType => typeof(TDomainEvent);
    public Type IntegrationEventType => typeof(TIntegrationEvent);

    public virtual int SchemaVersion => 1;

    public abstract TIntegrationEvent Map(TDomainEvent domainEvent);

    EventEnvelope IDomainEventToIntegrationEventMapper.Map(object domainEvent, EventEnvelopeMetadata metadata)
    {
        ArgumentNullException.ThrowIfNull(domainEvent);
        ArgumentNullException.ThrowIfNull(metadata);

        if (domainEvent is not TDomainEvent typedDomainEvent)
        {
            throw new InvalidOperationException(
                $"Mapper '{GetType().Name}' cannot map '{domainEvent.GetType().FullName}' as '{typeof(TDomainEvent).FullName}'.");
        }

        var integrationEvent = Map(typedDomainEvent);

        return EventEnvelope.Create(
            IntegrationEventType.Name,
            SchemaVersion,
            metadata.OccurredUtc,
            integrationEvent,
            metadata.MessageId,
            metadata.CorrelationId,
            metadata.CausationId,
            metadata.TraceParent,
            metadata.TenantId);
    }
}