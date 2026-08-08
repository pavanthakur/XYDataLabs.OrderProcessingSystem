using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Orders.Contracts.Events;
using XYDataLabs.OrderProcessingSystem.Orders.Features.Events;
using XYDataLabs.OrderProcessingSystem.Payments.Contracts.Events;
using XYDataLabs.OrderProcessingSystem.Payments.Features.Events;
using XYDataLabs.OrderProcessingSystem.Domain.Events;

namespace XYDataLabs.OrderProcessingSystem.Application.Tests.Events;

public sealed class Phase9EventFlowProofTests
{
    [Fact]
    public void IntegrationEventRegistry_Should_Map_Active_PreAzure_Event_Families()
    {
        var registry = new IntegrationEventMapperRegistry(new IDomainEventToIntegrationEventMapper[]
        {
            new OrderCreatedDomainEventMapper(),
            new PaymentAttemptSucceededDomainEventMapper(),
            new PaymentAttemptFailedDomainEventMapper(),
        });

        var now = DateTime.UtcNow;
        var envelopes = registry.Map(
            new object[]
            {
                new OrderCreatedDomainEvent(new Domain.Identifiers.CustomerId(42), now, 25m, 2, now),
                new PaymentAttemptSucceededDomainEvent(1, 42, "OpenPay", "order-1", now),
                new PaymentAttemptFailedDomainEvent(2, 42, "Razorpay", "order-1", "declined", now),
            },
            domainEvent => EventEnvelopeMetadata.Create(now, tenantId: 42));

        envelopes.Should().HaveCount(3);
        envelopes.Select(envelope => envelope.EventType).Should().Contain(new[]
        {
            nameof(OrderCreatedV1),
            nameof(PaymentAttemptSucceededV1),
            nameof(PaymentAttemptFailedV1),
        });
    }
}


