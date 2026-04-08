using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using Xunit;

namespace XYDataLabs.OrderProcessingSystem.Domain.Tests.Entities
{
    public class OrderEntityTests
    {
        [Fact]
        public void Create_ShouldInitializeAggregateWithCreatedStatus()
        {
            var products = new List<Product>
            {
                new() { ProductId = 1, Name = "Product 1", Description = "Description 1", Price = 10m },
                new() { ProductId = 2, Name = "Product 2", Description = "Description 2", Price = 15m }
            };

            var result = Order.Create(7, products, new DateTime(2026, 4, 5, 10, 0, 0, DateTimeKind.Utc));

            result.IsSuccess.Should().BeTrue();
            var order = result.Value!;

            order.OrderId.Should().Be(0);
            order.CustomerId.Should().Be(7);
            order.TotalPrice.Should().Be(25m);
            order.IsFulfilled.Should().BeFalse();
            order.IsClosed.Should().BeFalse();
            order.Status.Should().Be(OrderStatus.Created);
            order.Customer.Should().BeNull();
            order.TenantId.Should().Be(0);
        }

        [Fact]
        public void Create_ShouldInitializeOrderProductsCollection()
        {
            var result = Order.Create(1, new[]
            {
                new Product { ProductId = 1, Name = "Product 1", Description = "Description 1", Price = 9.99m }
            });

            result.IsSuccess.Should().BeTrue();
            var order = result.Value!;

            order.OrderProducts.Should().NotBeNull();
            order.OrderProducts.Should().ContainSingle();
        }

        [Fact]
        public void Create_ShouldFail_WhenProductsAreMissing()
        {
            var result = Order.Create(1, Array.Empty<Product>());

            result.IsFailure.Should().BeTrue();
            result.Error.Code.Should().Be("Validation");
        }

        [Fact]
        public void Deliver_ShouldRequirePaidThenShippedSequence()
        {
            var order = Order.Create(1, new[]
            {
                new Product { ProductId = 1, Name = "Product 1", Description = "Description 1", Price = 20m }
            }).Value!;

            order.Deliver().IsFailure.Should().BeTrue();

            order.Pay().IsSuccess.Should().BeTrue();
            order.Ship().IsSuccess.Should().BeTrue();
            order.Deliver().IsSuccess.Should().BeTrue();

            order.Status.Should().Be(OrderStatus.Delivered);
            order.IsFulfilled.Should().BeTrue();
            order.IsClosed.Should().BeTrue();
        }

        [Fact]
        public void Cancel_ShouldFail_AfterShipment()
        {
            var order = Order.Create(1, new[]
            {
                new Product { ProductId = 1, Name = "Product 1", Description = "Description 1", Price = 20m }
            }).Value!;

            order.Pay().IsSuccess.Should().BeTrue();
            order.Ship().IsSuccess.Should().BeTrue();

            var result = order.Cancel();

            result.IsFailure.Should().BeTrue();
            result.Error.Code.Should().Be("Conflict");
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

            orderProduct.TenantId.Should().Be(0);
            orderProduct.CreatedBy.Should().BeNull();
            orderProduct.CreatedDate.Should().BeNull();
        }

        [Fact]
        public void RowVersion_ShouldDefaultToEmptyArray()
        {
            var order = Order.Create(1, new[]
            {
                new Product { ProductId = 1, Name = "Product 1", Description = "Description 1", Price = 20m }
            }).Value!;

            order.RowVersion.Should().NotBeNull();
            order.RowVersion.Should().BeEmpty();
        }
    }
}
