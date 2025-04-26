using AutoMapper;
using FluentValidation;
using FluentValidation.Results;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Interfaces;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace XYDataLabs.OrderProcessingSystem.Application.Services
{
    public class OrderService : IOrderService
    {
        private readonly OrderProcessingSystemDbContext _context;
        private readonly IValidator<Order> _orderValidator;
        private readonly IMapper _autoMapper;


        public OrderService(OrderProcessingSystemDbContext context, IValidator<Order> orderValidator, IMapper autoMapper)
        {
            _context = context;
            _orderValidator = orderValidator;
            _autoMapper = autoMapper;
        }

        // Create a new order
        public async Task<OrderDto> CreateOrderAsync(int customerId, List<int> productIds)
        {
            var customer = await _context.Customers.Include(c => c.Orders)
                .FirstOrDefaultAsync(c => c.CustomerId == customerId);
            if (customer == null)
                throw new KeyNotFoundException($"Customer with ID {customerId} not found.");

            // Validate customer order history: Check if there is an unfulfilled order
            if (customer.Orders != null && customer.Orders.Any(o => !o.IsFulfilled))
                throw new ValidationException("Customer cannot place a new order until their previous order is fulfilled.");

            // Retrieve the products and check if they exist
            var products = await _context.Products.Where(p => productIds.Contains(p.ProductId)).ToListAsync();
            if (products.Count != productIds.Count)
                throw new KeyNotFoundException("One or more products not found.");

            // Create new order
            var order = new Order
            {
                CustomerId = customerId,
                OrderProducts = products.Select(p => new OrderProduct
                {
                    ProductId = p.ProductId,
                    Product = p,
                    Quantity = 1  // Assuming quantity of 1 for simplicity
                }).ToList()
            };

            // Calculate the total price
            order.TotalPrice = order.OrderProducts.Sum(oi => oi.Quantity * oi.Price);

            // Validate the order using FluentValidation
            ValidationResult validationResult = await _orderValidator.ValidateAsync(order);
            if (!validationResult.IsValid)
            {
                throw new ValidationException(validationResult.Errors);
            }

            _context.Orders.Add(order);
            await _context.SaveChangesAsync();

            // Map the order to OrderDto
            var orderDto = _autoMapper.Map<OrderDto>(order);
            return orderDto;
        }

        // Retrieve an order by ID, including the total price
        public async Task<OrderDto> GetOrderDetailsAsync(int orderId)
        {
            var order = await _context.Orders
                .Include(o => o.OrderProducts)
                .ThenInclude(oi => oi.Product)
                .FirstOrDefaultAsync(o => o.OrderId == orderId);

            if (order == null)
                throw new KeyNotFoundException($"Order with ID {orderId} not found.");

            return _autoMapper.Map<OrderDto>(order);
        }
    }
}
