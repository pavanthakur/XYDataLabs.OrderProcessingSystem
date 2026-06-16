namespace XYDataLabs.OrderProcessingSystem.Application.PublicApi.Services
{
    public class OrdersService : IOrdersService
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
            _dbContext.Entry(order).State = EntityState.Modified;
            await _dbContext.SaveChangesAsync();
            return order;
        }
    }
}
