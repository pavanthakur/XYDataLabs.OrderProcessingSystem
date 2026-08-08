using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;
using XYDataLabs.OrderProcessingSystem.Orders.Contracts.Events;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

public sealed class ServiceBusMessageFactoryTests
{
    [Fact]
    public void Create_Should_Preserve_Canonical_Envelope_And_Emit_Replay_Safe_Metadata()
    {
        var occurredUtc = new DateTime(2026, 5, 9, 12, 0, 0, DateTimeKind.Utc);
        var payload = new OrderCreatedV1(
            CustomerId: 11,
            OrderDate: occurredUtc,
            TotalPrice: 25.50m,
            ProductCount: 2);

        var envelope = EventEnvelope.Create(
            nameof(OrderCreatedV1),
            schemaVersion: 1,
            occurredUtc: occurredUtc,
            payload: payload,
            messageId: Guid.Parse("11111111-2222-3333-4444-555555555555"),
            correlationId: "corr-123",
            causationId: "cause-456",
            traceParent: "trace-parent",
            tenantId: 42);

        var factory = new ServiceBusMessageFactory();

        var message = factory.Create(envelope);
        var replayMessage = factory.Create(envelope);

        message.MessageId.Should().NotBe(envelope.MessageId.ToString("D"));
        replayMessage.MessageId.Should().NotBe(message.MessageId);
        replayMessage.ApplicationProperties["EnvelopeMessageId"].Should().Be(message.ApplicationProperties["EnvelopeMessageId"]);
        message.CorrelationId.Should().Be("corr-123");
        message.Subject.Should().Be(nameof(OrderCreatedV1));
        message.ContentType.Should().Be("application/json");
        message.SessionId.Should().Be("42");

        message.ApplicationProperties["EnvelopeMessageId"].Should().Be(envelope.MessageId.ToString("D"));
        message.ApplicationProperties["EventType"].Should().Be(nameof(OrderCreatedV1));
        message.ApplicationProperties["SchemaVersion"].Should().Be(1);
        message.ApplicationProperties["OccurredUtc"].Should().Be(occurredUtc.ToUniversalTime().ToString("O"));
        message.ApplicationProperties["CorrelationId"].Should().Be("corr-123");
        message.ApplicationProperties["CausationId"].Should().Be("cause-456");
        message.ApplicationProperties["TraceParent"].Should().Be("trace-parent");
        message.ApplicationProperties["TenantId"].Should().Be("42");
        message.ApplicationProperties["AttemptCount"].Should().Be(0);
        message.ApplicationProperties["FailureCategory"].Should().Be(string.Empty);
        message.Body.ToString().Should().Contain("\"customerId\":11");
        message.Body.ToString().Should().Contain("\"productCount\":2");
    }
}


