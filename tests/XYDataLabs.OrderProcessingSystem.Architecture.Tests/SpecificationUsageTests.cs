using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Domain.Identifiers;
using XYDataLabs.OrderProcessingSystem.Domain.ValueObjects;
using XYDataLabs.OrderProcessingSystem.Orders.Features.Specifications;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests;

public sealed class SpecificationUsageTests
{
    [Fact]
    public void Orders_Feature_Specifications_Should_Be_Usable_For_Module_Level_Query_Shaping()
    {
        var customer = new Customer
        {
            CustomerId = new CustomerId(1),
            Orders = [Order.Create(new CustomerId(1), [new Product { ProductId = new ProductId(2), Price = Money.From(10m) }]).Value!]
        };

        var customerSpec = new CustomerHasOpenOrderSpecification();
        customerSpec.Criteria.Compile().Invoke(customer).Should().BeTrue();

        var productSpec = new ProductsByIdsSpecification([1, 2, 3]);
        productSpec.Criteria.Compile().Invoke(new Product { ProductId = new ProductId(2) }).Should().BeTrue();
    }
}
