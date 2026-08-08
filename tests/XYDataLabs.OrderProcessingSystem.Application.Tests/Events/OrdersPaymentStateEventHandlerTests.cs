using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Application.Tests.TestBase;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Orders.Contracts.Events;
using XYDataLabs.OrderProcessingSystem.Orders.Features.Events;
using XYDataLabs.OrderProcessingSystem.Payments.Contracts.Events;

namespace XYDataLabs.OrderProcessingSystem.Application.Tests.Events;

public sealed class OrdersPaymentStateEventHandlerTests : OrderServiceTestBase
{
    [Fact]
    public async Task PaymentAttemptSucceededHandler_ShouldTransition_Order_ToPaid()
    {
        var order = CreateTestOrder(orderId: 42);
        MockDbContext.Setup(db => db.Orders).Returns(GetMockDbSet(new[] { order }.AsQueryable()).Object);
        MockDbContext.Setup(db => db.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);

        var handler = new PaymentAttemptSucceededV1Handler(
            MockDbContext.Object,
            NullLogger<PaymentAttemptSucceededV1Handler>.Instance);

        await handler.HandleAsync(
            CreateEnvelope(nameof(PaymentAttemptSucceededV1)),
            new PaymentAttemptSucceededV1(9, 1, "OpenPay", "ORDER-42", new DateTime(2026, 7, 29, 10, 0, 0, DateTimeKind.Utc)));

        order.Status.Should().Be(OrderStatus.Paid);
        MockDbContext.Verify(db => db.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task PaymentAttemptFailedHandler_ShouldRecord_AuditLog_WithoutCancelling_Order()
    {
        var order = CreateTestOrder(orderId: 42);
        MockDbContext.Setup(db => db.Orders).Returns(GetMockDbSet(new[] { order }.AsQueryable()).Object);

        var auditLogs = new List<AuditLog>();
        var auditLogSet = new Mock<DbSet<AuditLog>>();
        auditLogSet.Setup(set => set.Add(It.IsAny<AuditLog>()))
            .Callback<AuditLog>(auditLog => auditLogs.Add(auditLog));
        MockDbContext.Setup(db => db.AuditLogs).Returns(auditLogSet.Object);
        MockDbContext.Setup(db => db.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);

        var timeProvider = new Mock<TimeProvider>();
        timeProvider.Setup(provider => provider.GetUtcNow()).Returns(new DateTimeOffset(2026, 7, 29, 10, 0, 0, TimeSpan.Zero));

        var handler = new PaymentAttemptFailedV1Handler(
            MockDbContext.Object,
            NullLogger<PaymentAttemptFailedV1Handler>.Instance,
            timeProvider.Object);

        await handler.HandleAsync(
            CreateEnvelope(nameof(PaymentAttemptFailedV1)),
            new PaymentAttemptFailedV1(9, 1, "Razorpay", "ORDER-42", "declined", new DateTime(2026, 7, 29, 10, 0, 0, DateTimeKind.Utc)));

        order.Status.Should().Be(OrderStatus.Created);
        auditLogs.Should().ContainSingle();
        auditLogs.Single().EntityName.Should().Be("Order");
        auditLogs.Single().EntityId.Should().Be("OrderId=42");
        auditLogs.Single().Operation.Should().Be("PaymentFailed");
        auditLogs.Single().TenantId.Should().Be(1);
    }

    private static EventEnvelope CreateEnvelope(string eventType)
    {
        return EventEnvelope.Create(
            eventType,
            schemaVersion: 1,
            occurredUtc: new DateTime(2026, 7, 29, 10, 0, 0, DateTimeKind.Utc),
            payload: new { },
            correlationId: "corr-123",
            causationId: "cause-123",
            traceParent: "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00",
            tenantId: 1);
    }
}


