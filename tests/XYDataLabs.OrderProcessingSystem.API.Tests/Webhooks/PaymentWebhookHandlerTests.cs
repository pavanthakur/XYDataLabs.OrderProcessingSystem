using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Moq.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Webhooks;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Webhooks;

public class PaymentWebhookHandlerTests
{
    private readonly Mock<IAppDbContext> _mockContext = new();

    private void SetupAttempts(params PaymentAttempt[] attempts)
    {
        _mockContext.Setup(c => c.PaymentAttempts).ReturnsDbSet(attempts);
    }

    private static PaymentAttempt BuildAttempt(PaymentAttemptStatus status, string refId) => new()
    {
        Id = 1,
        TenantId = 1,
        CustomerOrderId = "OR-test-001",
        AttemptOrderId = "AT-test-001",
        PaymentTraceId = "trace-001",
        AttemptNumber = 1,
        PaymentProviderName = "Razorpay",
        ProviderReferenceId = refId,
        Status = status,
    };

    // ── PaymentCapturedHandler ─────────────────────────────────────────────────

    [Fact]
    public async Task Captured_HandleAsync_ValidPayload_ShouldMarkAttemptAsSucceeded()
    {
        var attempt = BuildAttempt(PaymentAttemptStatus.ProviderAccepted, "rzp_pay_123");
        SetupAttempts(attempt);

        var sut = new PaymentCapturedHandler(_mockContext.Object, NullLogger<PaymentCapturedHandler>.Instance);
        await sut.HandleAsync("Razorpay", """{"payment_id":"rzp_pay_123","event":"payment.captured"}""", tenantId: 1, CancellationToken.None);

        attempt.Status.Should().Be(PaymentAttemptStatus.Succeeded);
        attempt.DomainEvents.Should().ContainSingle().Which.Should().BeOfType<Domain.Events.PaymentAttemptSucceededDomainEvent>();
        _mockContext.Verify(c => c.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task Captured_HandleAsync_AttemptNotFound_ShouldNotSave()
    {
        SetupAttempts(); // empty

        var sut = new PaymentCapturedHandler(_mockContext.Object, NullLogger<PaymentCapturedHandler>.Instance);
        await sut.HandleAsync("Razorpay", """{"payment_id":"rzp_unknown"}""", tenantId: 1, CancellationToken.None);

        _mockContext.Verify(c => c.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task Captured_HandleAsync_AlreadySucceeded_ShouldBeIdempotent()
    {
        var attempt = BuildAttempt(PaymentAttemptStatus.Succeeded, "rzp_pay_done");
        SetupAttempts(attempt);

        var sut = new PaymentCapturedHandler(_mockContext.Object, NullLogger<PaymentCapturedHandler>.Instance);
        await sut.HandleAsync("Razorpay", """{"payment_id":"rzp_pay_done"}""", tenantId: 1, CancellationToken.None);

        _mockContext.Verify(c => c.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Never);
    }

    // ── PaymentFailedHandler ───────────────────────────────────────────────────

    [Fact]
    public async Task Failed_HandleAsync_ValidPayload_ShouldMarkAttemptAsFailed()
    {
        var attempt = BuildAttempt(PaymentAttemptStatus.ProviderAccepted, "rzp_pay_fail_001");
        SetupAttempts(attempt);

        var sut = new PaymentFailedHandler(_mockContext.Object, NullLogger<PaymentFailedHandler>.Instance);
        await sut.HandleAsync("Razorpay", """{"payment_id":"rzp_pay_fail_001","description":"Insufficient funds"}""", tenantId: 1, CancellationToken.None);

        attempt.Status.Should().Be(PaymentAttemptStatus.Failed);
        attempt.LastErrorMessage.Should().Be("Insufficient funds");
        attempt.DomainEvents.Should().ContainSingle().Which.Should().BeOfType<Domain.Events.PaymentAttemptFailedDomainEvent>();
        _mockContext.Verify(c => c.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task Failed_HandleAsync_AttemptNotFound_ShouldNotSave()
    {
        SetupAttempts(); // empty

        var sut = new PaymentFailedHandler(_mockContext.Object, NullLogger<PaymentFailedHandler>.Instance);
        await sut.HandleAsync("Razorpay", """{"payment_id":"rzp_unknown"}""", tenantId: 1, CancellationToken.None);

        _mockContext.Verify(c => c.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task Failed_HandleAsync_AlreadyFailed_ShouldBeIdempotent()
    {
        var attempt = BuildAttempt(PaymentAttemptStatus.Failed, "rzp_pay_already_failed");
        SetupAttempts(attempt);

        var sut = new PaymentFailedHandler(_mockContext.Object, NullLogger<PaymentFailedHandler>.Instance);
        await sut.HandleAsync("Razorpay", """{"payment_id":"rzp_pay_already_failed"}""", tenantId: 1, CancellationToken.None);

        _mockContext.Verify(c => c.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Never);
    }
}

