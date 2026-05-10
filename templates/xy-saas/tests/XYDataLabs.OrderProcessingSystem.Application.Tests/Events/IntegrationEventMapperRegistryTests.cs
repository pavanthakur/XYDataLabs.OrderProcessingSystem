using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Application.Features.Orders.Events;
using XYDataLabs.OrderProcessingSystem.Domain.Events;
using XYDataLabs.OrderProcessingSystem.Domain.Identifiers;

namespace XYDataLabs.OrderProcessingSystem.Application.Tests.Events;

public class IntegrationEventMapperRegistryTests
{
    [Fact]
    public void AddCqrs_ShouldRegister_OrderCreatedMapper_And_Map_OrderCreatedDomainEvent()
    {
        var services = new ServiceCollection();
        services.AddCqrs(typeof(XYDataLabs.OrderProcessingSystem.Application.StartupHelper).Assembly);

        using var serviceProvider = services.BuildServiceProvider();
        var registry = serviceProvider.GetRequiredService<IIntegrationEventMapperRegistry>();
        var occurredUtc = new DateTime(2026, 5, 9, 12, 0, 0, DateTimeKind.Utc);
        var domainEvent = new OrderCreatedDomainEvent(new CustomerId(7), occurredUtc, 25m, 2, occurredUtc);

        var envelopes = registry.Map(
            new object[] { domainEvent },
            _ => EventEnvelopeMetadata.Create(occurredUtc, correlationId: "trace-123", tenantId: 42));

        var eventEnvelope = envelopes.Should().ContainSingle().Subject;

        eventEnvelope.EventType.Should().Be(nameof(OrderCreatedV1));
        eventEnvelope.SchemaVersion.Should().Be(1);
        eventEnvelope.OccurredUtc.Should().Be(occurredUtc);
        eventEnvelope.CorrelationId.Should().Be("trace-123");
        eventEnvelope.TenantId.Should().Be(42);

        var payload = eventEnvelope.Payload.Should().BeOfType<OrderCreatedV1>().Subject;
        payload.CustomerId.Should().Be(7);
        payload.OrderDate.Should().Be(occurredUtc);
        payload.TotalPrice.Should().Be(25m);
        payload.ProductCount.Should().Be(2);
    }
}