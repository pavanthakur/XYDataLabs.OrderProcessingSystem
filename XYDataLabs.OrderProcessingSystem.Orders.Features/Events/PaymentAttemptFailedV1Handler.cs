using System.Globalization;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Payments.Contracts.Events;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Abstractions;

namespace XYDataLabs.OrderProcessingSystem.Orders.Features.Events;

public sealed class PaymentAttemptFailedV1Handler : IEventHandler<PaymentAttemptFailedV1>
{
    private readonly IAppDbContext _dbContext;
    private readonly ILogger<PaymentAttemptFailedV1Handler> _logger;
    private readonly TimeProvider _timeProvider;

    public PaymentAttemptFailedV1Handler(
        IAppDbContext dbContext,
        ILogger<PaymentAttemptFailedV1Handler> logger,
        TimeProvider timeProvider)
    {
        _dbContext = dbContext;
        _logger = logger;
        _timeProvider = timeProvider;
    }

    public async Task HandleAsync(
        EventEnvelope envelope,
        PaymentAttemptFailedV1 @event,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(envelope);
        ArgumentNullException.ThrowIfNull(@event);

        if (!TryParseCustomerOrderId(@event.CustomerOrderId, out var orderId))
        {
            _logger.LogWarning(
                "[{Handler}] Ignoring payment failure event {MessageId} because customer order id '{CustomerOrderId}' is not Orders-owned.",
                nameof(PaymentAttemptFailedV1Handler),
                envelope.MessageId,
                @event.CustomerOrderId);
            return;
        }

        var order = await _dbContext.Orders.SingleOrDefaultAsync(item => item.OrderId == orderId, cancellationToken);
        if (order is null)
        {
            _logger.LogWarning(
                "[{Handler}] Payment failure event {MessageId} referenced missing order {OrderId}.",
                nameof(PaymentAttemptFailedV1Handler),
                envelope.MessageId,
                orderId);
            return;
        }

        _dbContext.AuditLogs.Add(new AuditLog
        {
            TenantId = @event.TenantId,
            CreatedDate = _timeProvider.GetUtcNow().UtcDateTime,
            EntityName = "Order",
            EntityId = $"OrderId={order.OrderId}",
            Operation = "PaymentFailed",
            TraceId = envelope.TraceParent,
            CorrelationId = envelope.CorrelationId,
            OldValues = JsonSerializer.Serialize(new
            {
                OrderStatus = order.Status.ToString()
            }),
            NewValues = JsonSerializer.Serialize(new
            {
                OrderStatus = order.Status.ToString(),
                PaymentProvider = @event.ProviderName,
                @event.CustomerOrderId,
                @event.ErrorReason
            })
        });

        await _dbContext.SaveChangesAsync(cancellationToken);
        _logger.LogInformation(
            "[{Handler}] Recorded Orders-owned payment failure audit for order {OrderId} from event {MessageId}.",
            nameof(PaymentAttemptFailedV1Handler),
            order.OrderId,
            envelope.MessageId);
    }

    private static bool TryParseCustomerOrderId(string customerOrderId, out int orderId)
    {
        const string orderPrefix = "ORDER-";

        orderId = 0;
        return !string.IsNullOrWhiteSpace(customerOrderId)
            && customerOrderId.StartsWith(orderPrefix, StringComparison.OrdinalIgnoreCase)
            && int.TryParse(
                customerOrderId[orderPrefix.Length..],
                NumberStyles.None,
                CultureInfo.InvariantCulture,
                out orderId)
            && orderId > 0;
    }
}
