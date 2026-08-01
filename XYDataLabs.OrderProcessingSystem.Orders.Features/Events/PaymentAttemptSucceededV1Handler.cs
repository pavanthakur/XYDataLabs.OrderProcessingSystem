using System.Globalization;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Payments.Contracts.Events;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Abstractions;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;

namespace XYDataLabs.OrderProcessingSystem.Orders.Features.Events;

public sealed class PaymentAttemptSucceededV1Handler : IEventHandler<PaymentAttemptSucceededV1>
{
    private readonly IAppDbContext _dbContext;
    private readonly ILogger<PaymentAttemptSucceededV1Handler> _logger;

    public PaymentAttemptSucceededV1Handler(
        IAppDbContext dbContext,
        ILogger<PaymentAttemptSucceededV1Handler> logger)
    {
        _dbContext = dbContext;
        _logger = logger;
    }

    public async Task HandleAsync(
        EventEnvelope envelope,
        PaymentAttemptSucceededV1 @event,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(envelope);
        ArgumentNullException.ThrowIfNull(@event);

        if (!TryParseCustomerOrderId(@event.CustomerOrderId, out var orderId))
        {
            _logger.LogWarning(
                "[{Handler}] Ignoring payment success event {MessageId} because customer order id '{CustomerOrderId}' is not Orders-owned.",
                nameof(PaymentAttemptSucceededV1Handler),
                envelope.MessageId,
                @event.CustomerOrderId);
            return;
        }

        var order = await _dbContext.Orders.SingleOrDefaultAsync(item => item.OrderId == orderId, cancellationToken);
        if (order is null)
        {
            _logger.LogWarning(
                "[{Handler}] Payment success event {MessageId} referenced missing order {OrderId}.",
                nameof(PaymentAttemptSucceededV1Handler),
                envelope.MessageId,
                orderId);
            return;
        }

        if (order.Status is OrderStatus.Paid or OrderStatus.Shipped or OrderStatus.Delivered)
        {
            _logger.LogInformation(
                "[{Handler}] Order {OrderId} is already in state {OrderStatus}; no payment success transition is required.",
                nameof(PaymentAttemptSucceededV1Handler),
                order.OrderId,
                order.Status);
            return;
        }

        var payResult = order.Pay();
        if (payResult.IsFailure)
        {
            _logger.LogWarning(
                "[{Handler}] Order {OrderId} could not transition to Paid from {OrderStatus}: {Reason}",
                nameof(PaymentAttemptSucceededV1Handler),
                order.OrderId,
                order.Status,
                payResult.Error.Description);
            return;
        }

        await _dbContext.SaveChangesAsync(cancellationToken);
        _logger.LogInformation(
            "[{Handler}] Order {OrderId} transitioned to Paid from payment success event {MessageId}.",
            nameof(PaymentAttemptSucceededV1Handler),
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
