using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using Xunit;

namespace XYDataLabs.OrderProcessingSystem.Domain.Tests.Entities
{
    public class OrderEntityTests
    {
        [Fact]
        public void NewOrder_ShouldHaveDefaultValues()
        {
            var order = new Order();

            order.OrderId.Should().Be(0);
            order.CustomerId.Should().Be(0);
            order.TotalPrice.Should().Be(0);
            order.IsFulfilled.Should().BeFalse();
            order.Customer.Should().BeNull();
            order.TenantId.Should().BeEmpty();
        }

        [Fact]
        public void NewOrder_ShouldInitializeOrderProductsCollection()
        {
            var order = new Order();

            order.OrderProducts.Should().NotBeNull();
            order.OrderProducts.Should().BeEmpty();
        }

        [Fact]
        public void OrderProduct_Price_ShouldBeComputed()
        {
            var product = new Product { Price = 9.99m };
            var orderProduct = new OrderProduct
            {
                Quantity = 3,
                Product = product
            };

            orderProduct.Price.Should().Be(29.97m);
        }

        [Fact]
        public void OrderProduct_Price_ShouldBeZero_WhenProductIsNull()
        {
            var orderProduct = new OrderProduct { Quantity = 5 };

            orderProduct.Price.Should().Be(0);
        }

        [Fact]
        public void OrderProduct_ShouldInheritTenantId_FromBaseAuditableCreateEntity()
        {
            var orderProduct = new OrderProduct();

            orderProduct.TenantId.Should().BeEmpty();
            orderProduct.CreatedBy.Should().BeNull();
            orderProduct.CreatedDate.Should().BeNull();
        }
    }
}
