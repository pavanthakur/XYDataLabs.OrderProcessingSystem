namespace XYDataLabs.OrderProcessingSystem.Application.Events;

public sealed class IntegrationEventMapperRegistry : IIntegrationEventMapperRegistry
{
    private readonly IReadOnlyDictionary<Type, IDomainEventToIntegrationEventMapper> _mappers;

    public IntegrationEventMapperRegistry(IEnumerable<IDomainEventToIntegrationEventMapper> mappers)
    {
        ArgumentNullException.ThrowIfNull(mappers);

        _mappers = mappers
            .GroupBy(mapper => mapper.DomainEventType)
            .ToDictionary(
                group => group.Key,
                group => group.Count() == 1
                    ? group.Single()
                    : throw new InvalidOperationException(
                        $"More than one domain-event mapper is registered for '{group.Key.FullName}'."));
    }

    public IReadOnlyCollection<EventEnvelope> Map(
        IEnumerable<object> domainEvents,
        Func<object, EventEnvelopeMetadata> metadataFactory)
    {
        ArgumentNullException.ThrowIfNull(domainEvents);
        ArgumentNullException.ThrowIfNull(metadataFactory);

        var envelopes = new List<EventEnvelope>();

        foreach (var domainEvent in domainEvents)
        {
            ArgumentNullException.ThrowIfNull(domainEvent);

            if (!_mappers.TryGetValue(domainEvent.GetType(), out var mapper))
            {
                throw new InvalidOperationException(
                    $"No integration-event mapper is registered for domain event '{domainEvent.GetType().FullName}'.");
            }

            envelopes.Add(mapper.Map(domainEvent, metadataFactory(domainEvent)));
        }

        return envelopes.AsReadOnly();
    }
}