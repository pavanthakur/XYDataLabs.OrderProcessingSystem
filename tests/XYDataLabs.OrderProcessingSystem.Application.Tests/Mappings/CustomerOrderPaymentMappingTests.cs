using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Application.Mappings;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using Xunit;

namespace XYDataLabs.OrderProcessingSystem.Application.Tests.Mappings;

public sealed class CustomerOrderPaymentMappingTests
{
    [Fact]
    public void PaymentOrderDirectory_DoesNotServeStaleCachedOrderState()
    {
        object query = new XYDataLabs.OrderProcessingSystem.Application.Features.Customers.Queries.GetAllCustomersQuery();
        query.Should().NotBeAssignableTo<XYDataLabs.OrderProcessingSystem.Application.CQRS.ICacheable>();
    }

    [Theory]
    [InlineData("INR")]
    [InlineData("MXN")]
    public void CustomerOrderSummary_PreservesPersistedPaymentReferenceAndCurrency(string currency)
    {
        var result = Order.Create(7, [new Product { ProductId=1, Name="Fixture", Price=100m }], currencyCode:currency);
        result.IsSuccess.Should().BeTrue();
        var order = result.Value!;
        order.OrderId=42;
        var customer = new Customer {CustomerId=7,Name="Fixture",Email="fixture@example.test",Orders=[order]};
        var mapped = customer.ToDto().OrderDtos.Single();
        mapped.OrderReferenceId.Should().Be(order.OrderReferenceId);
        mapped.CurrencyCode.Should().Be(currency);
        mapped.TotalPrice.Should().Be(100m);
    }
}
