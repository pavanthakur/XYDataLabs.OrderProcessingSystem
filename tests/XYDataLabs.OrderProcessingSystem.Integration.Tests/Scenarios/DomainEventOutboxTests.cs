using FluentAssertions;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

[Collection("SqlServer")]
[Trait("Category", "Integration")]
public sealed class DomainEventOutboxTests : IAsyncLifetime
{
    private readonly SqlServerFixture _fixture;
    private IntegrationTestWebAppFactory _factory = null!;

    public DomainEventOutboxTests(SqlServerFixture fixture)
    {
        _fixture = fixture;
    }

    public Task InitializeAsync()
    {
        _factory = new IntegrationTestWebAppFactory(_fixture.ConnectionString);
        _ = _factory.CreateClient();
        return Task.CompletedTask;
    }

    public async Task DisposeAsync()
    {
        await _factory.DisposeAsync();
    }

    [Fact]
    public async Task SaveChangesAsync_Should_Persist_Outbox_And_Clear_DomainEvents_On_Success()
    {
        var tenant = await IntegrationTestData.CreateTenantAsync(_factory);

        var savedOrder = await _factory.ExecuteTenantDbContextAsync(
            tenant.ToTenantContext(),
            async dbContext =>
            {
                var customer = new Customer
                {
                    Name = $"customer-{Guid.NewGuid():N}",
                    Email = $"customer-{Guid.NewGuid():N}@test.com",
                    TenantId = tenant.TenantId,
                    CreatedBy = 1,
                    CreatedDate = DateTime.UtcNow,
                };

                var product = new Product
                {
                    Name = $"product-{Guid.NewGuid():N}",
                    Description = "Domain event outbox test product",
                    Price = 19.99m,
                    TenantId = tenant.TenantId,
                    CreatedBy = 1,
                    CreatedDate = DateTime.UtcNow,
                };

                dbContext.Customers.Add(customer);
                dbContext.Products.Add(product);
                await dbContext.SaveChangesAsync();

                var orderResult = Order.Create(customer.CustomerId, new[] { product }, DateTime.UtcNow);
                orderResult.IsSuccess.Should().BeTrue();

                var order = orderResult.Value!;
                order.CreatedBy = 1;
                order.CreatedDate = DateTime.UtcNow;

                dbContext.Orders.Add(order);
                await dbContext.SaveChangesAsync();

                order.DomainEvents.Should().BeEmpty();
                return order;
            });

        var outboxMessages = await _factory.ExecuteTenantDbContextAsync(
            tenant.ToTenantContext(),
            dbContext => dbContext.OutboxMessages
                .OrderBy(message => message.Id)
                .ToListAsync());

        outboxMessages.Should().ContainSingle();
        outboxMessages[0].TenantId.Should().Be(tenant.TenantId);
        outboxMessages[0].EventType.Should().Be("OrderCreatedV1");
        outboxMessages[0].ProcessedAt.Should().BeNull();
        outboxMessages[0].Payload.Should().Contain("customerId");
        outboxMessages[0].Payload.Should().Contain(savedOrder.CustomerId.Value.ToString());
    }

    [Fact]
    public async Task SaveChangesAsync_Should_Leave_DomainEvents_Intact_When_Transaction_Fails()
    {
        var tenant = await IntegrationTestData.CreateTenantAsync(_factory);

        var createdCustomerId = await _factory.ExecuteTenantDbContextAsync(
            tenant.ToTenantContext(),
            async dbContext =>
            {
                var customer = new Customer
                {
                    Name = $"customer-{Guid.NewGuid():N}",
                    Email = $"customer-{Guid.NewGuid():N}@test.com",
                    TenantId = tenant.TenantId,
                    CreatedBy = 1,
                    CreatedDate = DateTime.UtcNow,
                };

                var product = new Product
                {
                    Name = $"product-{Guid.NewGuid():N}",
                    Description = "Rollback test product",
                    Price = 9.99m,
                    TenantId = tenant.TenantId,
                    CreatedBy = 1,
                    CreatedDate = DateTime.UtcNow,
                };

                dbContext.Customers.Add(customer);
                dbContext.Products.Add(product);
                await dbContext.SaveChangesAsync();

                var paymentProvider = new PaymentProvider
                {
                    Name = $"provider-{Guid.NewGuid():N}",
                    APIUrl = "https://payments.example.test",
                    IsProduction = false,
                    IsActive = true,
                    ProviderType = "OpenPay",
                    TenantId = tenant.TenantId,
                    CreatedBy = 1,
                    CreatedDate = DateTime.UtcNow,
                };

                dbContext.PaymentProviders.Add(paymentProvider);
                await dbContext.SaveChangesAsync();

                var orderResult = Order.Create(customer.CustomerId, new[] { product }, DateTime.UtcNow);
                orderResult.IsSuccess.Should().BeTrue();

                var order = orderResult.Value!;
                order.CreatedBy = 1;
                order.CreatedDate = DateTime.UtcNow;
                dbContext.Orders.Add(order);

                dbContext.PaymentMethods.Add(new PaymentMethod
                {
                    PaymentProviderId = paymentProvider.Id,
                    Token = "duplicate-token",
                    Status = true,
                    TenantId = tenant.TenantId,
                    CreatedBy = 1,
                    CreatedDate = DateTime.UtcNow,
                });

                dbContext.PaymentMethods.Add(new PaymentMethod
                {
                    PaymentProviderId = paymentProvider.Id,
                    Token = "duplicate-token",
                    Status = true,
                    TenantId = tenant.TenantId,
                    CreatedBy = 1,
                    CreatedDate = DateTime.UtcNow,
                });

                var act = async () => await dbContext.SaveChangesAsync();
                await act.Should().ThrowAsync<DbUpdateException>();

                order.DomainEvents.Should().ContainSingle();
                return customer.CustomerId;
            });

        var persistedOrderCount = await _factory.ExecuteTenantDbContextAsync(
            tenant.ToTenantContext(),
            dbContext => dbContext.Orders.CountAsync(order => order.CustomerId == createdCustomerId));

        var outboxMessageCount = await _factory.ExecuteTenantDbContextAsync(
            tenant.ToTenantContext(),
            dbContext => dbContext.OutboxMessages.CountAsync());

        persistedOrderCount.Should().Be(0);
        outboxMessageCount.Should().Be(0);
    }
}