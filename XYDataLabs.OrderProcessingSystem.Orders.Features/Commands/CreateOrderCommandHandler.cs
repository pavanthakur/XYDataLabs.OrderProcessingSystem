using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Domain.Identifiers;
using XYDataLabs.OrderProcessingSystem.Domain.Results;
using XYDataLabs.OrderProcessingSystem.SharedKernel.CQRS;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Abstractions;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;
using XYDataLabs.OrderProcessingSystem.Orders.API;
using XYDataLabs.OrderProcessingSystem.Orders.Features.Mappings;
using XYDataLabs.OrderProcessingSystem.Orders.Features.Specifications;
using XYDataLabs.OrderProcessingSystem.Orders.Features;

namespace XYDataLabs.OrderProcessingSystem.Orders.Features.Commands;

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

        var openOrderSpecification = new CustomerHasOpenOrderSpecification();

        if (customer.Orders is not null && openOrderSpecification.Criteria.Compile().Invoke(customer))
            return Error.Create("Validation", "Customer cannot place a new order until their previous order is fulfilled.");

        var productsByIdsSpecification = new ProductsByIdsSpecification(command.ProductIds.Select(id => id.Value).ToList());

        var products = await _context.Products
            .Where(productsByIdsSpecification.Criteria)
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

