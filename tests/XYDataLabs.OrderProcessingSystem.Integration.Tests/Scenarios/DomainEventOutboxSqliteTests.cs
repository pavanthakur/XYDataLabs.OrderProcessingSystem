using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using System.Text.Json;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;
using XYDataLabs.OrderProcessingSystem.Orders.Features.Events;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

[Collection("SqlServer")]
[Trait("Category", "Integration")]
public sealed class DomainEventOutboxSqlServerTests : IClassFixture<SqlServerFixture>
{
    private readonly SqlServerFixture _fixture;
    private readonly IIntegrationEventMapperRegistry _mapperRegistry;
    private readonly TestTenantProvider _tenantProvider = new(42, "TenantSqlite");

    public DomainEventOutboxSqlServerTests(SqlServerFixture fixture)
    {
        _fixture = fixture;
        _mapperRegistry = new IntegrationEventMapperRegistry(new IDomainEventToIntegrationEventMapper[]
        {
            new OrderCreatedDomainEventMapper(),
        });

        using var context = CreateContext();
        context.Database.Migrate();
    }

    [Fact]
    public async Task SaveChangesAsync_Should_Persist_Outbox_And_Clear_DomainEvents_On_Success_Using_SqlServer()
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
    public async Task SaveChangesAsync_Should_Roll_Back_Outbox_And_Keep_DomainEvents_On_Failure_Using_SqlServer()
    {
        var providerId = await SeedBaselineEntitiesAsync();

        await using var failingContext = CreateContext();
        var customer = new Customer
        {
            Name = $"Rollback Customer {Guid.NewGuid():N}",
            Email = $"rollback-{Guid.NewGuid():N}@test.com",
            TenantId = _tenantProvider.TenantId,
            CreatedBy = 1,
            CreatedDate = DateTime.UtcNow,
        };
        failingContext.Customers.Add(customer);
        await failingContext.SaveChangesAsync();

        var product = await failingContext.Products.SingleAsync();

        var orderResult = Order.Create(customer.CustomerId, new[] { product }, DateTime.UtcNow);
        orderResult.IsSuccess.Should().BeTrue();

        var order = orderResult.Value!;
        order.CreatedBy = 1;
        order.CreatedDate = DateTime.UtcNow;
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
        (await verificationContext.Orders.CountAsync(orderRow => orderRow.CustomerId == customer.CustomerId)).Should().Be(0);
        (await verificationContext.OutboxMessages.CountAsync(message =>
            message.Payload != null &&
            message.Payload.Contains($"\"customerId\":{customer.CustomerId.Value}"))).Should().Be(0);
    }

    private async Task<int> SeedBaselineEntitiesAsync()
    {
        await using var context = CreateContext();

        var paymentMethods = await context.PaymentMethods
            .Where(method => method.TenantId == _tenantProvider.TenantId)
            .ToListAsync();
        if (paymentMethods.Count > 0)
        {
            context.PaymentMethods.RemoveRange(paymentMethods);
        }

        var billingCustomers = await context.BillingCustomers
            .Where(customer => customer.TenantId == _tenantProvider.TenantId)
            .ToListAsync();
        if (billingCustomers.Count > 0)
        {
            context.BillingCustomers.RemoveRange(billingCustomers);
        }

        var billingCustomerKeyInfos = await context.BillingCustomerKeyInfos
            .Where(keyInfo => keyInfo.TenantId == _tenantProvider.TenantId)
            .ToListAsync();
        if (billingCustomerKeyInfos.Count > 0)
        {
            context.BillingCustomerKeyInfos.RemoveRange(billingCustomerKeyInfos);
        }

        var cardTransactions = await context.CardTransactions
            .Where(cardTransaction => cardTransaction.TenantId == _tenantProvider.TenantId)
            .ToListAsync();
        if (cardTransactions.Count > 0)
        {
            context.CardTransactions.RemoveRange(cardTransactions);
        }

        var payinLogs = await context.PayinLogs
            .Where(payinLog => payinLog.TenantId == _tenantProvider.TenantId)
            .ToListAsync();
        if (payinLogs.Count > 0)
        {
            context.PayinLogs.RemoveRange(payinLogs);
        }

        var paymentProviders = await context.PaymentProviders
            .Where(provider => provider.TenantId == _tenantProvider.TenantId)
            .ToListAsync();
        if (paymentProviders.Count > 0)
        {
            context.PaymentProviders.RemoveRange(paymentProviders);
        }

        var orders = await context.Orders
            .Where(order => order.TenantId == _tenantProvider.TenantId)
            .ToListAsync();
        if (orders.Count > 0)
        {
            context.Orders.RemoveRange(orders);
        }

        var customers = await context.Customers
            .Where(customer => customer.TenantId == _tenantProvider.TenantId)
            .ToListAsync();
        if (customers.Count > 0)
        {
            context.Customers.RemoveRange(customers);
        }

        var products = await context.Products
            .Where(product => product.TenantId == _tenantProvider.TenantId)
            .ToListAsync();
        if (products.Count > 0)
        {
            context.Products.RemoveRange(products);
        }

        var outboxMessages = await context.OutboxMessages
            .Where(message => message.TenantId == _tenantProvider.TenantId)
            .ToListAsync();
        if (outboxMessages.Count > 0)
        {
            context.OutboxMessages.RemoveRange(outboxMessages);
        }

        if (context.ChangeTracker.HasChanges())
        {
            await context.SaveChangesAsync();
        }

        var tenantExists = await context.Tenants.AnyAsync(tenant => tenant.Id == _tenantProvider.TenantId);
        if (!tenantExists)
        {
            context.Database.ExecuteSqlInterpolated($@"
                SET IDENTITY_INSERT [dbo].[Tenants] ON;
                INSERT INTO [dbo].[Tenants] ([Id], [ExternalId], [Code], [Name], [Status], [TenantTier], [CreatedBy], [CreatedDate])
                VALUES ({_tenantProvider.TenantId}, {"ext-TenantSqlite"}, {_tenantProvider.TenantCode}, {"Tenant Sqlite"}, {"Active"}, {"SharedPool"}, {1}, {DateTime.UtcNow});
                SET IDENTITY_INSERT [dbo].[Tenants] OFF;");
        }

        var paymentProvider = new PaymentProvider
        {
            Name = "OpenPay",
            APIUrl = "https://api.example.com",
            IsProduction = false,
            IsActive = true,
            ProviderType = "OpenPay",
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
            .UseSqlServer(_fixture.ConnectionString)
            .Options;

        return new OrderProcessingSystemDbContext(options, _tenantProvider, _mapperRegistry);
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
