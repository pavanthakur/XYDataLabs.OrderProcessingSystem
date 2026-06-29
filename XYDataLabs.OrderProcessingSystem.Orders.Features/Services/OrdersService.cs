using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Orders.API;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Abstractions;

namespace XYDataLabs.OrderProcessingSystem.Orders.Features.Services;

public sealed class OrdersService : IOrderModuleApi
{
    private readonly IAppDbContext _dbContext;

    public OrdersService(IAppDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task<Order> CreateOrderAsync(Order order)
    {
        _dbContext.Orders.Add(order);
        await _dbContext.SaveChangesAsync();
        return order;
    }

    public async Task<Order> UpdateOrderAsync(Order order)
    {
        _dbContext.Orders.Update(order);
        await _dbContext.SaveChangesAsync();
        return order;
    }
}

