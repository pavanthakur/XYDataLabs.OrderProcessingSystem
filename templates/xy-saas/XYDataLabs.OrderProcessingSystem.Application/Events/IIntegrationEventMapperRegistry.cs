namespace XYDataLabs.OrderProcessingSystem.Application.Events;

public interface IIntegrationEventMapperRegistry
{
    IReadOnlyCollection<EventEnvelope> Map(
        IEnumerable<object> domainEvents,
        Func<object, EventEnvelopeMetadata> metadataFactory);
}