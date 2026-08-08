using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Orders.Contracts;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Abstractions;
using Microsoft.EntityFrameworkCore;
using System.Globalization;

namespace XYDataLabs.OrderProcessingSystem.Orders.Features.Services;

public sealed class OrdersService : IOrderModuleApi
{
    private readonly IAppDbContext _dbContext;

    public OrdersService(IAppDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task<Order> CreateOrderAsync(Order order, CancellationToken cancellationToken = default)
    {
        _dbContext.Orders.Add(order);
        await _dbContext.SaveChangesAsync(cancellationToken);
        return order;
    }

    public async Task<Order> UpdateOrderAsync(Order order, CancellationToken cancellationToken = default)
    {
        _dbContext.Orders.Update(order);
        await _dbContext.SaveChangesAsync(cancellationToken);
        return order;
    }

    public async Task<OrderPaymentContextDto?> GetPaymentContextAsync(string customerOrderId, CancellationToken cancellationToken = default)
    {
        if (!TryParseCustomerOrderId(customerOrderId, out var orderId))
        {
            return null;
        }

        var order = await _dbContext.Orders
            .AsNoTracking()
            .SingleOrDefaultAsync(item => item.OrderId == orderId, cancellationToken);

        if (order is null)
        {
            return null;
        }

        return new OrderPaymentContextDto(
            order.OrderId,
            $"ORDER-{order.OrderId}",
            order.OrderReferenceId,
            order.TotalPrice.Value,
            order.CurrencyCode.Trim().ToUpperInvariant(),
            order.Status.ToString(),
            Convert.ToBase64String(order.RowVersion));
    }

    public async Task<OrderPaymentContextDto?> GetPaymentContextByOrderReferenceAsync(Guid orderReferenceId, CancellationToken cancellationToken = default)
    {
        if (orderReferenceId == Guid.Empty)
        {
            return null;
        }

        var order = await _dbContext.Orders
            .AsNoTracking()
            .SingleOrDefaultAsync(item => item.OrderReferenceId == orderReferenceId, cancellationToken);

        if (order is null)
        {
            return null;
        }

        return new OrderPaymentContextDto(
            order.OrderId,
            $"ORDER-{order.OrderId}",
            order.OrderReferenceId,
            order.TotalPrice.Value,
            order.CurrencyCode.Trim().ToUpperInvariant(),
            order.Status.ToString(),
            Convert.ToBase64String(order.RowVersion));
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

