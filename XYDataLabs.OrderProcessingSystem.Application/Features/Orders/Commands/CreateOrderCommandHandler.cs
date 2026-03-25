using AutoMapper;
using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Orders.Commands;

public sealed class CreateOrderCommandHandler : ICommandHandler<CreateOrderCommand, Result<OrderDto>>
{
    private readonly IAppDbContext _context;
    private readonly IMapper _mapper;

    public CreateOrderCommandHandler(IAppDbContext context, IMapper mapper)
    {
        _context = context;
        _mapper = mapper;
    }

    public async Task<Result<OrderDto>> HandleAsync(CreateOrderCommand command, CancellationToken cancellationToken = default)
    {
        using var activity = OrderActivitySource.Source.StartActivity("CreateOrder");
        activity?.SetTag("order.customer_id", command.CustomerId);
        activity?.SetTag("order.product_count", command.ProductIds.Count);
        var customer = await _context.Customers
            .Include(c => c.Orders)
            .FirstOrDefaultAsync(c => c.CustomerId == command.CustomerId, cancellationToken);

        if (customer is null)
            return Error.Create("NotFound", $"Customer with ID {command.CustomerId} not found.");

        // Validate customer order history: check for unfulfilled orders
        if (customer.Orders is not null && customer.Orders.Any(o => !o.IsFulfilled))
            return Error.Create("Validation", "Customer cannot place a new order until their previous order is fulfilled.");

        // Retrieve products
        var products = await _context.Products
            .Where(p => command.ProductIds.Contains(p.ProductId))
            .ToListAsync(cancellationToken);

        if (products.Count != command.ProductIds.Count)
            return Error.Create("NotFound", "One or more products not found.");

        // Create order with line items
        var order = new Order
        {
            CustomerId = command.CustomerId,
            OrderProducts = products.Select(p => new OrderProduct
            {
                ProductId = p.ProductId,
                Product = p,
                Quantity = 1
            }).ToList()
        };

        order.TotalPrice = order.OrderProducts.Sum(oi => oi.Quantity * oi.Price);

        if (order.TotalPrice <= 0)
            return Error.Create("Validation", "The total price must be greater than zero.");

        _context.Orders.Add(order);
        await _context.SaveChangesAsync(cancellationToken);

        return _mapper.Map<OrderDto>(order);
    }
}
