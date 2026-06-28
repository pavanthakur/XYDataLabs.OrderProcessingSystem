using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Domain.Events;
using XYDataLabs.OrderProcessingSystem.Payments.Features.Events;
using XYDataLabs.OrderProcessingSystem.Payments.Features.Module;

namespace XYDataLabs.OrderProcessingSystem.Application.Tests.Features.Payments.Events;

public class PaymentAttemptEventMapperTests
{
    private readonly IIntegrationEventMapperRegistry _registry;
    private readonly DateTime _occurredUtc = new(2026, 6, 5, 10, 0, 0, DateTimeKind.Utc);

    public PaymentAttemptEventMapperTests()
    {
        var services = new ServiceCollection();
        services.AddCqrs(typeof(PaymentsModuleRegistration).Assembly);
        var sp = services.BuildServiceProvider();
        _registry = sp.GetRequiredService<IIntegrationEventMapperRegistry>();
    }

    [Fact]
    public void AddCqrs_ShouldRegister_PaymentAttemptSucceededMapper_And_Map_DomainEvent()
    {
        var domainEvent = new PaymentAttemptSucceededDomainEvent(
            AttemptId: 42,
            TenantId: 1,
            ProviderName: "Razorpay",
            CustomerOrderId: "OR-test-001",
            OccurredUtc: _occurredUtc);

        var envelopes = _registry.Map(
            new object[] { domainEvent },
            _ => EventEnvelopeMetadata.Create(_occurredUtc, correlationId: "corr-abc", tenantId: 1));

        var envelope = envelopes.Should().ContainSingle().Subject;

        envelope.EventType.Should().Be(nameof(PaymentAttemptSucceededV1));
        envelope.SchemaVersion.Should().Be(1);
        envelope.OccurredUtc.Should().Be(_occurredUtc);
        envelope.CorrelationId.Should().Be("corr-abc");
        envelope.TenantId.Should().Be(1);

        var payload = envelope.Payload.Should().BeOfType<PaymentAttemptSucceededV1>().Subject;
        payload.AttemptId.Should().Be(42);
        payload.TenantId.Should().Be(1);
        payload.ProviderName.Should().Be("Razorpay");
        payload.CustomerOrderId.Should().Be("OR-test-001");
        payload.OccurredUtc.Should().Be(_occurredUtc);
    }

    [Fact]
    public void AddCqrs_ShouldRegister_PaymentAttemptFailedMapper_And_Map_DomainEvent()
    {
        var domainEvent = new PaymentAttemptFailedDomainEvent(
            AttemptId: 7,
            TenantId: 3,
            ProviderName: "OpenPay",
            ErrorReason: "Insufficient funds",
            OccurredUtc: _occurredUtc);

        var envelopes = _registry.Map(
            new object[] { domainEvent },
            _ => EventEnvelopeMetadata.Create(_occurredUtc, correlationId: "corr-xyz", tenantId: 3));

        var envelope = envelopes.Should().ContainSingle().Subject;

        envelope.EventType.Should().Be(nameof(PaymentAttemptFailedV1));
        envelope.SchemaVersion.Should().Be(1);
        envelope.TenantId.Should().Be(3);

        var payload = envelope.Payload.Should().BeOfType<PaymentAttemptFailedV1>().Subject;
        payload.AttemptId.Should().Be(7);
        payload.TenantId.Should().Be(3);
        payload.ProviderName.Should().Be("OpenPay");
        payload.ErrorReason.Should().Be("Insufficient funds");
        payload.OccurredUtc.Should().Be(_occurredUtc);
    }
}
