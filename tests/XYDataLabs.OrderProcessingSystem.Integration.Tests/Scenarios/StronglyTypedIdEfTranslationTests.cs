using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Domain.Identifiers;
using XYDataLabs.OrderProcessingSystem.Domain.ValueObjects;
using XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;
using Xunit;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

[Collection("SqlServer")]
[Trait("Category", "Integration")]
public sealed class StronglyTypedIdEfTranslationTests : IAsyncLifetime
{
    private readonly SqlServerFixture _fixture;
    private IntegrationTestWebAppFactory _factory = null!;
    private TestTenantContext _tenant = null!;

    public StronglyTypedIdEfTranslationTests(SqlServerFixture fixture)
    {
        _fixture = fixture;
    }

    public async Task InitializeAsync()
    {
        _factory = new IntegrationTestWebAppFactory(_fixture.ConnectionString);
        _tenant = await IntegrationTestData.CreateTenantAsync(_factory);
    }

    public async Task DisposeAsync()
    {
        await _factory.DisposeAsync();
    }

    [Fact]
    public async Task StronglyTypedIds_AndMoney_RoundTrip_AndTranslate_QueryPredicates()
    {
        var persistedIds = await _factory.ExecuteDbContextAsync(async dbContext =>
        {
            var createdAt = DateTime.UtcNow;

            var customer = new Customer
            {
                Name = "Typed Customer",
                Email = $"typed-{Guid.NewGuid():N}@test.com",
                TenantId = _tenant.TenantId,
                CreatedBy = 1,
                CreatedDate = createdAt
            };

            var product = new Product
            {
                Name = "Typed Product",
                Description = "Typed ID query translation test product",
                Price = 42.50m,
                TenantId = _tenant.TenantId,
                CreatedBy = 1,
                CreatedDate = createdAt
            };

            dbContext.Customers.Add(customer);
            dbContext.Products.Add(product);
            await dbContext.SaveChangesAsync();

            var orderResult = Order.Create(customer.CustomerId, new[] { product }, createdAt);
            if (orderResult.IsFailure || orderResult.Value is null)
            {
                throw new InvalidOperationException(orderResult.Error.Description);
            }

            var order = orderResult.Value;
            order.TenantId = _tenant.TenantId;
            order.CreatedBy = 1;
            order.CreatedDate = createdAt;

            foreach (var orderProduct in order.OrderProducts)
            {
                orderProduct.TenantId = _tenant.TenantId;
                orderProduct.CreatedBy = 1;
                orderProduct.CreatedDate = createdAt;
            }

            dbContext.Orders.Add(order);
            await dbContext.SaveChangesAsync();

            return new PersistedIds(customer.CustomerId, product.ProductId, order.OrderId);
        });

        await _factory.ExecuteDbContextAsync(async dbContext =>
        {
            var customer = await dbContext.Customers.FindAsync([persistedIds.CustomerId]);
            customer.Should().NotBeNull();
            customer!.CustomerId.Should().Be(persistedIds.CustomerId);

            var order = await dbContext.Orders
                .AsNoTracking()
                .FirstOrDefaultAsync(item => item.OrderId == persistedIds.OrderId);

            order.Should().NotBeNull();
            order!.OrderId.Should().Be(persistedIds.OrderId);
            order.CustomerId.Should().Be(persistedIds.CustomerId);
            order.TotalPrice.Should().Be(Money.From(42.50m));

            var productIds = new[] { persistedIds.ProductId };
            var products = await dbContext.Products
                .AsNoTracking()
                .Where(item => productIds.Contains(item.ProductId))
                .ToListAsync();

            products.Should().ContainSingle();
            products[0].ProductId.Should().Be(persistedIds.ProductId);
            products[0].Price.Should().Be(Money.From(42.50m));
        });
    }

    private sealed record PersistedIds(CustomerId CustomerId, ProductId ProductId, OrderId OrderId);
}