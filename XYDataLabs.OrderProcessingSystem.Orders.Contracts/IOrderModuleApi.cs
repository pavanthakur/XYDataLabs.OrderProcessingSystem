using XYDataLabs.OrderProcessingSystem.Domain.Entities;

namespace XYDataLabs.OrderProcessingSystem.Orders.Contracts;

public interface IOrderModuleApi
{
    Task<Order> CreateOrderAsync(Order order, CancellationToken cancellationToken = default);

    Task<Order> UpdateOrderAsync(Order order, CancellationToken cancellationToken = default);

    Task<OrderPaymentContextDto?> GetPaymentContextAsync(string customerOrderId, CancellationToken cancellationToken = default);

    Task<OrderPaymentContextDto?> GetPaymentContextByOrderReferenceAsync(Guid orderReferenceId, CancellationToken cancellationToken = default);
}
