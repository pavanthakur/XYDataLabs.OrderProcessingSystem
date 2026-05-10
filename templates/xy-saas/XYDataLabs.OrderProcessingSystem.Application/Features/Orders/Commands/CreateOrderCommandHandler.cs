using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.DTO;
using XYDataLabs.OrderProcessingSystem.Application.Mappings;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Domain.Identifiers;
using XYDataLabs.OrderProcessingSystem.Domain.Results;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Features.Orders.Commands;

public sealed class CreateOrderCommandHandler : ICommandHandler<CreateOrderCommand, Result<OrderDto>>
{
    private readonly IAppDbContext _context;

    public CreateOrderCommandHandler(IAppDbContext context)
    {
        _context = context;
    }

    public async Task<Result<OrderDto>> HandleAsync(CreateOrderCommand command, CancellationToken cancellationToken = default)
    {
        using var activity = OrderActivitySource.Source.StartActivity("CreateOrder");
        activity?.SetTag("order.customer_id", command.CustomerId.Value);
        activity?.SetTag("order.product_count", command.ProductIds.Count);

        var customer = await _context.Customers
            .Include(c => c.Orders)
            .FirstOrDefaultAsync(c => c.CustomerId == command.CustomerId, cancellationToken);

        if (customer is null)
            return Error.Create("NotFound", $"Customer with ID {command.CustomerId.Value} not found.");

        // Validate customer order history: check for unfulfilled orders
        if (customer.Orders is not null && customer.Orders.Any(o => !o.IsClosed))
            return Error.Create("Validation", "Customer cannot place a new order until their previous order is fulfilled.");

        // Retrieve products
        var products = await _context.Products
            .Where(p => command.ProductIds.Contains(p.ProductId))
            .ToListAsync(cancellationToken);

        if (products.Count != command.ProductIds.Count)
            return Error.Create("NotFound", "One or more products not found.");

        var orderResult = Order.Create(command.CustomerId, products);
        if (orderResult.IsFailure || orderResult.Value is null)
        {
            return ToApplicationError(orderResult.Error);
        }

        var order = orderResult.Value;

        _context.Orders.Add(order);
        await _context.SaveChangesAsync(cancellationToken);

        return order.ToDto();
    }

    private static Error ToApplicationError(DomainError error) => Error.Create(error.Code, error.Description);
}
