using XYDataLabs.OrderProcessingSystem.Domain.Entities;

namespace XYDataLabs.OrderProcessingSystem.Orders.API;

public interface IOrderModuleApi
{
    Task<Order> CreateOrderAsync(Order order);

    Task<Order> UpdateOrderAsync(Order order);
}

