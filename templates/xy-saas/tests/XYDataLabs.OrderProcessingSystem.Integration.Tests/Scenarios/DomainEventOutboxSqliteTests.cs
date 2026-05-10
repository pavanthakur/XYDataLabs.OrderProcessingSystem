using FluentAssertions;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Application.Features.Orders.Events;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

[Trait("Category", "Integration")]
public sealed class DomainEventOutboxSqliteTests : IDisposable
{
    private readonly SqliteConnection _connection;
    private readonly IIntegrationEventMapperRegistry _mapperRegistry;
    private readonly TestTenantProvider _tenantProvider = new(42, "TenantSqlite");

    public DomainEventOutboxSqliteTests()
    {
        _connection = new SqliteConnection("Data Source=:memory:");
        _connection.Open();
        _mapperRegistry = new IntegrationEventMapperRegistry(new IDomainEventToIntegrationEventMapper[]
        {
            new OrderCreatedDomainEventMapper(),
        });

        using var context = CreateContext();
        context.Database.EnsureCreated();
    }

    public void Dispose()
    {
        _connection.Dispose();
    }

    [Fact]
    public async Task SaveChangesAsync_Should_Persist_Outbox_And_Clear_DomainEvents_On_Success_Using_Sqlite()
    {
        await SeedBaselineEntitiesAsync();

        await using var context = CreateContext();
        var customer = await context.Customers.SingleAsync();
        var product = await context.Products.SingleAsync();

        var orderResult = Order.Create(customer.CustomerId, new[] { product }, DateTime.UtcNow);
        orderResult.IsSuccess.Should().BeTrue();

        var order = orderResult.Value!;
        order.CreatedBy = 1;
        order.CreatedDate = DateTime.UtcNow;
        foreach (var orderProduct in order.OrderProducts.Select((value, index) => new { value, index }))
        {
            orderProduct.value.SysId = orderProduct.index + 1;
        }

        context.Orders.Add(order);
        await context.SaveChangesAsync();

        order.DomainEvents.Should().BeEmpty();

        var outboxMessages = await context.OutboxMessages.ToListAsync();
        outboxMessages.Should().ContainSingle();
        outboxMessages[0].TenantId.Should().Be(_tenantProvider.TenantId);
        outboxMessages[0].EventType.Should().Be(nameof(OrderCreatedV1));
        outboxMessages[0].Payload.Should().Contain("customerId");
        outboxMessages[0].Payload.Should().Contain(customer.CustomerId.Value.ToString());
    }

    [Fact]
    public async Task SaveChangesAsync_Should_Roll_Back_Outbox_And_Keep_DomainEvents_On_Failure_Using_Sqlite()
    {
        var providerId = await SeedBaselineEntitiesAsync();

        await using var failingContext = CreateContext();
        var customer = await failingContext.Customers.SingleAsync();
        var product = await failingContext.Products.SingleAsync();

        var orderResult = Order.Create(customer.CustomerId, new[] { product }, DateTime.UtcNow);
        orderResult.IsSuccess.Should().BeTrue();

        var order = orderResult.Value!;
        order.CreatedBy = 1;
        order.CreatedDate = DateTime.UtcNow;
        foreach (var orderProduct in order.OrderProducts.Select((value, index) => new { value, index }))
        {
            orderProduct.value.SysId = orderProduct.index + 1;
        }
        failingContext.Orders.Add(order);

        failingContext.PaymentMethods.Add(new PaymentMethod
        {
            PaymentProviderId = providerId,
            Token = "duplicate-token",
            Status = true,
            TenantId = _tenantProvider.TenantId,
            CreatedBy = 1,
            CreatedDate = DateTime.UtcNow,
        });

        failingContext.PaymentMethods.Add(new PaymentMethod
        {
            PaymentProviderId = providerId,
            Token = "duplicate-token",
            Status = true,
            TenantId = _tenantProvider.TenantId,
            CreatedBy = 1,
            CreatedDate = DateTime.UtcNow,
        });

        var act = async () => await failingContext.SaveChangesAsync();
        await act.Should().ThrowAsync<DbUpdateException>();

        order.DomainEvents.Should().ContainSingle();

        await using var verificationContext = CreateContext();
        (await verificationContext.Orders.CountAsync()).Should().Be(0);
        (await verificationContext.OutboxMessages.CountAsync()).Should().Be(0);
    }

    private async Task<int> SeedBaselineEntitiesAsync()
    {
        await using var context = CreateContext();

        if (await context.PaymentProviders.AnyAsync())
        {
            return await context.PaymentProviders.Select(provider => provider.Id).SingleAsync();
        }

        context.Tenants.Add(new Tenant
        {
            Id = _tenantProvider.TenantId,
            ExternalId = "ext-TenantSqlite",
            Code = _tenantProvider.TenantCode,
            Name = "Tenant Sqlite",
            Status = "Active",
            TenantTier = "SharedPool",
            CreatedBy = 1,
            CreatedDate = DateTime.UtcNow,
        });

        var paymentProvider = new PaymentProvider
        {
            Name = "DefaultGateway",
            APIUrl = "https://api.example.com",
            IsProduction = false,
            IsActive = true,
            Use3DSecure = true,
            TenantId = _tenantProvider.TenantId,
            CreatedBy = 1,
            CreatedDate = DateTime.UtcNow,
        };

        var customer = new Customer
        {
            Name = "Sqlite Customer",
            Email = "sqlite-customer@test.com",
            TenantId = _tenantProvider.TenantId,
            CreatedBy = 1,
            CreatedDate = DateTime.UtcNow,
        };

        var product = new Product
        {
            Name = "Sqlite Product",
            Description = "Sqlite persistence primitive test product",
            Price = 11.50m,
            TenantId = _tenantProvider.TenantId,
            CreatedBy = 1,
            CreatedDate = DateTime.UtcNow,
        };

        context.PaymentProviders.Add(paymentProvider);
        context.Customers.Add(customer);
        context.Products.Add(product);
        await context.SaveChangesAsync();

        return paymentProvider.Id;
    }

    private OrderProcessingSystemDbContext CreateContext()
    {
        var options = new DbContextOptionsBuilder<OrderProcessingSystemDbContext>()
            .UseSqlite(_connection)
            .Options;

        return new SqliteOrderProcessingSystemDbContext(options, _tenantProvider, _mapperRegistry);
    }

    private sealed class SqliteOrderProcessingSystemDbContext : OrderProcessingSystemDbContext
    {
        public SqliteOrderProcessingSystemDbContext(
            DbContextOptions<OrderProcessingSystemDbContext> options,
            ITenantProvider tenantProvider,
            IIntegrationEventMapperRegistry integrationEventMapperRegistry)
            : base(options, tenantProvider, integrationEventMapperRegistry)
        {
        }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);

            modelBuilder.Entity<Order>()
                .Property(order => order.RowVersion)
                .IsConcurrencyToken()
                .ValueGeneratedNever();
        }
    }

    private sealed class TestTenantProvider : ITenantProvider
    {
        public TestTenantProvider(int tenantId, string tenantCode)
        {
            TenantId = tenantId;
            TenantCode = tenantCode;
        }

        public bool HasTenantContext => true;
        public int TenantId { get; }
        public string TenantCode { get; }
        public string TenantExternalId => $"ext-{TenantCode}";
        public string? ConnectionString => null;
        public bool IsSharedPool => true;
    }
}