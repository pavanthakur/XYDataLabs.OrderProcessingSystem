using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using Xunit;

namespace XYDataLabs.OrderProcessingSystem.Domain.Tests.Entities
{
    public class CustomerEntityTests
    {
        [Fact]
        public void NewCustomer_ShouldHaveDefaultValues()
        {
            var customer = new Customer();

            customer.CustomerId.Should().Be(0);
            customer.Name.Should().BeEmpty();
            customer.Email.Should().BeEmpty();
            customer.OpenpayCustomerId.Should().BeNull();
            customer.TenantId.Should().BeEmpty();
            customer.CreatedBy.Should().BeNull();
            customer.CreatedDate.Should().BeNull();
        }

        [Fact]
        public void NewCustomer_ShouldInitializeOrdersCollection()
        {
            var customer = new Customer();

            customer.Orders.Should().NotBeNull();
            customer.Orders.Should().BeEmpty();
        }

        [Fact]
        public void Customer_ShouldSetProperties()
        {
            var customer = new Customer
            {
                CustomerId = 1,
                Name = "John Doe",
                Email = "john@example.com",
                OpenpayCustomerId = "op_123",
                TenantId = "tenant-1"
            };

            customer.CustomerId.Should().Be(1);
            customer.Name.Should().Be("John Doe");
            customer.Email.Should().Be("john@example.com");
            customer.OpenpayCustomerId.Should().Be("op_123");
            customer.TenantId.Should().Be("tenant-1");
        }
    }
}
