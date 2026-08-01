using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Domain.Identifiers;
using XYDataLabs.OrderProcessingSystem.Domain.Results;
using XYDataLabs.OrderProcessingSystem.SharedKernel.CQRS;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Abstractions;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;
using XYDataLabs.OrderProcessingSystem.Inventory.API;
using XYDataLabs.OrderProcessingSystem.Orders.Contracts;
using XYDataLabs.OrderProcessingSystem.Orders.Features.Mappings;
using XYDataLabs.OrderProcessingSystem.Orders.Features.Specifications;
using XYDataLabs.OrderProcessingSystem.Orders.Features;

namespace XYDataLabs.OrderProcessingSystem.Orders.Features.Commands;

public sealed class CreateOrderCommandHandler : ICommandHandler<CreateOrderCommand, Result<OrderDto>>
{
    private readonly IAppDbContext _context;
    private readonly IInventoryModuleApi _inventoryModuleApi;

    public CreateOrderCommandHandler(
        IAppDbContext context,
        IInventoryModuleApi inventoryModuleApi)
    {
        ArgumentNullException.ThrowIfNull(context);
        ArgumentNullException.ThrowIfNull(inventoryModuleApi);

        _context = context;
        _inventoryModuleApi = inventoryModuleApi;
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

        var requestedProductIds = command.ProductIds
            .Select(static id => id.Value)
            .ToArray();

        var productSnapshots = await _inventoryModuleApi
            .GetProductsByIdsAsync(requestedProductIds, cancellationToken)
            .ConfigureAwait(false);

        if (productSnapshots.Count != requestedProductIds.Length)
            return Error.Create("NotFound", "One or more products not found.");

        var products = productSnapshots
            .Select(snapshot =>
            {
                if (_context is not DbContext dbContext)
                {
                    return new Product
                    {
                        ProductId = snapshot.ProductId,
                        Name = snapshot.Name,
                        Description = snapshot.Description ?? string.Empty,
                        Price = snapshot.Price
                    };
                }

                var trackedProduct = dbContext.Set<Product>().Local
                    .FirstOrDefault(product => product.ProductId.Value == snapshot.ProductId);

                if (trackedProduct is not null)
                {
                    return trackedProduct;
                }

                return dbContext.Set<Product>().Attach(new Product
                {
                    ProductId = snapshot.ProductId,
                    Name = snapshot.Name,
                    Description = snapshot.Description ?? string.Empty,
                    Price = snapshot.Price
                }).Entity;
            })
            .ToList();

        var orderResult = Order.Create(
            command.CustomerId,
            products,
            currencyCode: command.CurrencyCode);
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

