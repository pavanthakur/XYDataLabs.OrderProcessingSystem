using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Domain.Events;

namespace XYDataLabs.OrderProcessingSystem.Domain.Tests.Entities;

public class PaymentAttemptEntityTests
{
    private static PaymentAttempt BuildAttempt(int tenantId = 1) => new()
    {
        Id = 42,
        TenantId = tenantId,
        CustomerOrderId = "OR-test-001",
        AttemptOrderId = "AT-test-001",
        PaymentTraceId = "trace-001",
        AttemptNumber = 1,
        PaymentProviderName = "Razorpay",
        Status = PaymentAttemptStatus.ProviderAccepted,
    };

    // ── MarkAsSucceeded ───────────────────────────────────────────────────────

    [Fact]
    public void MarkAsSucceeded_ShouldSetStatusAndRaiseDomainEvent()
    {
        var attempt = BuildAttempt();

        attempt.MarkAsSucceeded("Razorpay");

        attempt.Status.Should().Be(PaymentAttemptStatus.Succeeded);
        attempt.ProviderStatus.Should().Be("captured");

        var evt = attempt.DomainEvents.Should().ContainSingle()
            .Which.Should().BeOfType<PaymentAttemptSucceededDomainEvent>().Subject;

        evt.AttemptId.Should().Be(42);
        evt.TenantId.Should().Be(1);
        evt.ProviderName.Should().Be("Razorpay");
        evt.CustomerOrderId.Should().Be("OR-test-001");
        evt.OccurredUtc.Should().BeCloseTo(DateTime.UtcNow, precision: TimeSpan.FromSeconds(5));
    }

    [Fact]
    public void MarkAsSucceeded_WhenAlreadySucceeded_ShouldNotRaiseDuplicateEvent()
    {
        var attempt = BuildAttempt();
        attempt.MarkAsSucceeded("Razorpay");
        attempt.ClearDomainEvents();

        attempt.MarkAsSucceeded("Razorpay"); // second call — idempotent

        attempt.Status.Should().Be(PaymentAttemptStatus.Succeeded);
        attempt.DomainEvents.Should().BeEmpty("second call on an already-Succeeded attempt must not raise a duplicate event");
    }

    // ── MarkAsFailed ──────────────────────────────────────────────────────────

    [Fact]
    public void MarkAsFailed_ShouldSetStatusAndRaiseDomainEvent()
    {
        var attempt = BuildAttempt();

        attempt.MarkAsFailed("OpenPay", "Insufficient funds");

        attempt.Status.Should().Be(PaymentAttemptStatus.Failed);
        attempt.ProviderStatus.Should().Be("failed");
        attempt.LastErrorMessage.Should().Be("Insufficient funds");

        var evt = attempt.DomainEvents.Should().ContainSingle()
            .Which.Should().BeOfType<PaymentAttemptFailedDomainEvent>().Subject;

        evt.AttemptId.Should().Be(42);
        evt.TenantId.Should().Be(1);
        evt.ProviderName.Should().Be("OpenPay");
        evt.ErrorReason.Should().Be("Insufficient funds");
        evt.OccurredUtc.Should().BeCloseTo(DateTime.UtcNow, precision: TimeSpan.FromSeconds(5));
    }

    [Fact]
    public void MarkAsFailed_WhenAlreadyFailed_ShouldNotRaiseDuplicateEvent()
    {
        var attempt = BuildAttempt();
        attempt.MarkAsFailed("OpenPay", "Insufficient funds");
        attempt.ClearDomainEvents();

        attempt.MarkAsFailed("OpenPay", "Duplicate"); // second call — idempotent

        attempt.Status.Should().Be(PaymentAttemptStatus.Failed);
        attempt.DomainEvents.Should().BeEmpty("second call on an already-Failed attempt must not raise a duplicate event");
    }
}
