namespace XYDataLabs.OrderProcessingSystem.Application.PublicApi.Services
{
    public interface IOrdersService
    {
        Task<Order> CreateOrderAsync(Order order);
        Task<Order> UpdateOrderAsync(Order order);
    }
}
