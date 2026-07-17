using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.Infrastructure.SeedData;
using XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;
using XYDataLabs.OrderProcessingSystem.Orders.Features.Events;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

[Collection("SqlServer")]
[Trait("Category", "Integration")]
public sealed class DbInitializerSeedProviderTests : IClassFixture<SqlServerFixture>
{
    private const string TenantACode = "TenantA";
    private const string TenantBCode = "TenantB";
    private const string UnknownTenantCode = "UnknownTenant";

    private readonly SqlServerFixture _fixture;
    private readonly IIntegrationEventMapperRegistry _emptyRegistry;

    public DbInitializerSeedProviderTests(SqlServerFixture fixture)
    {
        _fixture = fixture;
        _emptyRegistry = new IntegrationEventMapperRegistry(
            new IDomainEventToIntegrationEventMapper[] { new OrderCreatedDomainEventMapper() });
    }

    [Theory]
    [InlineData(TenantACode, false, true)]
    [InlineData(TenantBCode, false, true)]
    public void Initialize_WhenNoProviderRowsExist_SeedsBothProvidersAsInactive(
        string tenantCode, bool expectedRazorpay3DS, bool expectedOpenPay3DS)
    {
        using var seedContext = CreateContext();
        ResetTenantGraph(seedContext, TenantACode, TenantBCode, UnknownTenantCode);
        var tenantIds = SeedBothBaselineTenants(seedContext);
        var tenantId = GetTenantId(tenantIds, tenantCode);

        DbInitializer.Initialize(
            seedContext,
            configuration: null,
            applyMigrations: false,
            integrationEventMapperRegistry: _emptyRegistry);

        var providers = seedContext.PaymentProviders
            .IgnoreQueryFilters()
            .Where(pp => pp.TenantId == tenantId)
            .ToList();

        providers.Should().HaveCount(2, $"DbInitializer seeds both OpenPay and Razorpay for every tenant ({tenantCode})");
        var rzp = providers.Single(p => p.ProviderType == PaymentProviderTypes.Razorpay);
        var opy = providers.Single(p => p.ProviderType == PaymentProviderTypes.OpenPay);
        opy.Use3DSecure.Should().Be(expectedOpenPay3DS, $"{tenantCode} OpenPay Use3DSecure should match seed-data dictionary default");
        rzp.Use3DSecure.Should().Be(expectedRazorpay3DS, $"{tenantCode} Razorpay Use3DSecure should match seed-data dictionary default");
        providers.Should().OnlyContain(
            provider => !provider.IsActive,
            $"new provider rows must be seeded IsActive=false — active provider is resolved from Tenant Registry (Tenant.PaymentProviderCode), not DbInitializer ({tenantCode})");
    }

    [Theory]
    [InlineData(TenantACode)]
    [InlineData(TenantBCode)]
    public void Initialize_WhenProvidersAlreadyExist_PreservesDatabaseSelectedActiveState(
        string tenantCode)
    {
        using var seedContext = CreateContext();
        ResetTenantGraph(seedContext, TenantACode, TenantBCode, UnknownTenantCode);
        var tenantIds = SeedBothBaselineTenants(seedContext);
        var tenantId = GetTenantId(tenantIds, tenantCode);

        seedContext.PaymentProviders.AddRange(
            new PaymentProvider
            {
                Name = "OpenPay",
                APIUrl = "https://sandbox-api.openpay.mx/v1",
                IsActive = true,
                IsProduction = false,
                ProviderType = PaymentProviderTypes.OpenPay,
                Use3DSecure = true,
                TenantId = tenantId,
                CreatedBy = 1,
                CreatedDate = DateTime.UtcNow
            },
            new PaymentProvider
            {
                Name = "Razorpay",
                APIUrl = "https://api.razorpay.com/v1",
                IsActive = false,
                IsProduction = false,
                ProviderType = PaymentProviderTypes.Razorpay,
                Use3DSecure = false,
                TenantId = tenantId,
                CreatedBy = 1,
                CreatedDate = DateTime.UtcNow
            });
        seedContext.SaveChanges();

        DbInitializer.Initialize(seedContext, null, false, _emptyRegistry);

        var providers = seedContext.PaymentProviders.IgnoreQueryFilters().Where(pp => pp.TenantId == tenantId).ToList();
        providers.Single(pp => pp.ProviderType == PaymentProviderTypes.Razorpay).IsActive.Should().BeFalse($"startup seeding must preserve the runtime-selected inactive state for {tenantCode}");
        providers.Single(pp => pp.ProviderType == PaymentProviderTypes.OpenPay).IsActive.Should().BeTrue($"startup seeding must preserve the runtime-selected active state for {tenantCode}");
    }

    [Theory]
    [InlineData(TenantACode, PaymentProviderTypes.Razorpay)]
    [InlineData(TenantBCode, PaymentProviderTypes.Razorpay)]
    public void Initialize_WhenActiveProviderAlreadyExists_AddsMissingProviderInactive(
        string tenantCode, string activeProviderType)
    {
        using var seedContext = CreateContext();
        ResetTenantGraph(seedContext, TenantACode, TenantBCode, UnknownTenantCode);
        var tenantIds = SeedBothBaselineTenants(seedContext);
        var tenantId = GetTenantId(tenantIds, tenantCode);

        seedContext.PaymentProviders.Add(new PaymentProvider
        {
            Name = activeProviderType,
            APIUrl = activeProviderType == PaymentProviderTypes.OpenPay
                ? "https://sandbox-api.openpay.mx/v1"
                : "https://api.razorpay.com/v1",
            IsActive = true,
            IsProduction = false,
            ProviderType = activeProviderType,
            Use3DSecure = activeProviderType == PaymentProviderTypes.OpenPay,
            TenantId = tenantId,
            CreatedBy = 1,
            CreatedDate = DateTime.UtcNow
        });
        seedContext.SaveChanges();

        DbInitializer.Initialize(seedContext, null, false, _emptyRegistry);

        var providers = seedContext.PaymentProviders.IgnoreQueryFilters().Where(pp => pp.TenantId == tenantId).ToList();
        providers.Should().HaveCount(2, $"DbInitializer should backfill the missing provider for {tenantCode}");
        providers.Count(pp => pp.IsActive).Should().Be(1, "adding a missing provider must not introduce dual-active state");
        providers.Single(pp => pp.ProviderType == activeProviderType).IsActive.Should().BeTrue();
        providers.Single(pp => pp.ProviderType != activeProviderType).IsActive.Should().BeFalse();
    }

    [Fact]
    public void Initialize_AlwaysSeedsBothProvidersAsInactiveRegardlessOfTenantState()
    {
        using var seedContext = CreateContext();
        ResetTenantGraph(seedContext, TenantACode, TenantBCode, UnknownTenantCode);

        var tenantIds = SeedBothBaselineTenants(seedContext);
        SeedStubSampleData(seedContext, tenantIds.TenantAId);
        SeedStubSampleData(seedContext, tenantIds.TenantBId);

        var unknownTenantId = SeedTenant(seedContext, UnknownTenantCode);

        DbInitializer.Initialize(seedContext, null, false, _emptyRegistry);

        foreach (var tenantId in new[] { tenantIds.TenantAId, tenantIds.TenantBId })
        {
            var providers = seedContext.PaymentProviders.IgnoreQueryFilters().Where(pp => pp.TenantId == tenantId).ToList();
            providers.Should().HaveCount(2, $"DbInitializer seeds both providers for TenantId={tenantId}");
            providers.Should().OnlyContain(pp => !pp.IsActive, $"all seeded providers must be inactive — routing authority is Tenant Registry (TenantId={tenantId})");
        }

        seedContext.PaymentProviders.IgnoreQueryFilters().Where(pp => pp.TenantId == unknownTenantId).Should().BeEmpty("DbInitializer only seeds providers for StartupSeedTenantCodes");
    }

    [Fact]
    public void Initialize_WithConfiguration_BackfillsProviderRuntimeFields()
    {
        using var seedContext = CreateContext();
        ResetTenantGraph(seedContext, TenantACode, TenantBCode, UnknownTenantCode);
        var tenantIds = SeedBothBaselineTenants(seedContext);

        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["OpenPay:MerchantId"] = "mt_seed_openpay",
                ["OpenPay:PublicKey"] = "pk_seed_openpay",
                ["OpenPay:PrivateKey"] = "sk_seed_openpay",
                ["OpenPay:IsProduction"] = "true",
                ["Razorpay:MerchantId"] = "rzp_test_seed",
                ["Razorpay:PrivateKey"] = "rzp_seed_private_key",
                ["Razorpay:IsProduction"] = "false"
            })
            .Build();

        DbInitializer.Initialize(seedContext, configuration, false, _emptyRegistry);

        var tenantAProviders = seedContext.PaymentProviders.IgnoreQueryFilters().Where(pp => pp.TenantId == tenantIds.TenantAId).ToList();
        tenantAProviders.Single(pp => pp.ProviderType == PaymentProviderTypes.OpenPay)
            .Should().Match<PaymentProvider>(provider =>
                provider.MerchantId == "mt_seed_openpay"
                && provider.PublicKey == "pk_seed_openpay"
                && provider.PrivateKeyConfigurationKey == "PaymentProviders:TenantA:OpenPay:PrivateKey"
                && provider.IsProduction
                && provider.Use3DSecure);

        tenantAProviders.Single(pp => pp.ProviderType == PaymentProviderTypes.Razorpay)
            .Should().Match<PaymentProvider>(provider =>
                provider.MerchantId == "rzp_test_seed"
                && provider.PrivateKeyConfigurationKey == "PaymentProviders:TenantA:Razorpay:PrivateKey"
                && !provider.IsProduction
                && !provider.Use3DSecure);
    }

    private OrderProcessingSystemDbContext CreateContext()
    {
        var options = new DbContextOptionsBuilder<OrderProcessingSystemDbContext>()
            .UseSqlServer(_fixture.ConnectionString)
            .Options;

        return new OrderProcessingSystemDbContext(options, new NoTenantProvider(), _emptyRegistry);
    }

    private static (int TenantAId, int TenantBId) SeedBothBaselineTenants(OrderProcessingSystemDbContext context)
    {
        var tenantAId = SeedTenant(context, TenantACode);
        var tenantBId = SeedTenant(context, TenantBCode);

        var tenantIds = new[] { tenantAId, tenantBId };

        // Clear the full dependent payment graph first so SQL Server does not reject
        // provider cleanup when existing BillingCustomers still point at PaymentMethods.
        var cardTransactions = context.CardTransactions
            .IgnoreQueryFilters()
            .Where(transaction => tenantIds.Contains(transaction.TenantId))
            .ToList();
        if (cardTransactions.Count > 0)
        {
            context.CardTransactions.RemoveRange(cardTransactions);
            context.SaveChanges();
        }

        var billingCustomerKeyInfos = context.BillingCustomerKeyInfos
            .IgnoreQueryFilters()
            .Where(keyInfo => tenantIds.Contains(keyInfo.TenantId))
            .ToList();
        if (billingCustomerKeyInfos.Count > 0)
        {
            context.BillingCustomerKeyInfos.RemoveRange(billingCustomerKeyInfos);
            context.SaveChanges();
        }

        var billingCustomers = context.BillingCustomers
            .IgnoreQueryFilters()
            .Where(customer => tenantIds.Contains(customer.TenantId))
            .ToList();
        if (billingCustomers.Count > 0)
        {
            context.BillingCustomers.RemoveRange(billingCustomers);
            context.SaveChanges();
        }

        var payinLogs = context.PayinLogs
            .IgnoreQueryFilters()
            .Where(log => tenantIds.Contains(log.TenantId))
            .ToList();
        if (payinLogs.Count > 0)
        {
            context.PayinLogs.RemoveRange(payinLogs);
            context.SaveChanges();
        }

        var existingPaymentMethods = context.PaymentMethods
            .IgnoreQueryFilters()
            .Where(method => tenantIds.Contains(method.TenantId))
            .ToList();
        if (existingPaymentMethods.Count > 0)
        {
            context.PaymentMethods.RemoveRange(existingPaymentMethods);
            context.SaveChanges();
        }

        var existingProviders = context.PaymentProviders
            .IgnoreQueryFilters()
            .Where(provider => tenantIds.Contains(provider.TenantId))
            .ToList();
        if (existingProviders.Count > 0)
        {
            context.PaymentProviders.RemoveRange(existingProviders);
            context.SaveChanges();
        }

        return (tenantAId, tenantBId);
    }

    private static void ResetTenantGraph(OrderProcessingSystemDbContext context, params string[] tenantCodes)
    {
        var tenantIds = context.Tenants
            .IgnoreQueryFilters()
            .Where(tenant => tenantCodes.Contains(tenant.Code))
            .Select(tenant => tenant.Id)
            .ToList();

        if (tenantIds.Count == 0)
        {
            return;
        }

        var tenantIdList = string.Join(", ", tenantIds);

        // Use set-based SQL so cleanup can remove historical rows whose enum
        // string values no longer materialize through the current EF model.
        context.Database.ExecuteSqlRaw($"""
            DELETE FROM [payments].[PaymentAttemptHistories] WHERE [TenantId] IN ({tenantIdList});
            DELETE FROM [payments].[TransactionStatusHistories] WHERE [TenantId] IN ({tenantIdList});
            DELETE FROM [payments].[PayinLogDetails] WHERE [TenantId] IN ({tenantIdList});
            DELETE FROM [payments].[CardTransactions] WHERE [TenantId] IN ({tenantIdList});
            DELETE FROM [payments].[PaymentAttempts] WHERE [TenantId] IN ({tenantIdList});
            DELETE FROM [payments].[BillingCustomerKeyInfos] WHERE [TenantId] IN ({tenantIdList});
            DELETE FROM [payments].[BillingCustomers] WHERE [TenantId] IN ({tenantIdList});
            DELETE FROM [payments].[PayinLogs] WHERE [TenantId] IN ({tenantIdList});
            DELETE FROM [payments].[PaymentMethods] WHERE [TenantId] IN ({tenantIdList});
            DELETE FROM [payments].[PaymentProviders] WHERE [TenantId] IN ({tenantIdList});
            DELETE FROM [orders].[OrderProducts] WHERE [TenantId] IN ({tenantIdList});
            DELETE FROM [orders].[Orders] WHERE [TenantId] IN ({tenantIdList});
            DELETE FROM [inventory].[Products] WHERE [TenantId] IN ({tenantIdList});
            DELETE FROM [orders].[Customers] WHERE [TenantId] IN ({tenantIdList});
            DELETE FROM [notifications].[InboxMessages] WHERE [TenantId] IN ({tenantIdList});
            DELETE FROM [notifications].[OutboxMessages] WHERE [TenantId] IN ({tenantIdList});
            DELETE FROM [notifications].[AuditLogs] WHERE [TenantId] IN ({tenantIdList});
            DELETE FROM [dbo].[Tenants] WHERE [Id] IN ({tenantIdList});
            """);
    }

    private static int SeedTenant(OrderProcessingSystemDbContext context, string tenantCode)
    {
        var existing = context.Tenants.SingleOrDefault(t => t.Code == tenantCode);
        if (existing is not null)
        {
            return existing.Id;
        }

        var tenant = new Tenant
        {
            ExternalId = $"ext-{tenantCode.ToUpperInvariant()}",
            Code = tenantCode,
            Name = $"Test {tenantCode}",
            Status = "Active",
            TenantTier = "SharedPool",
            CreatedBy = 1,
            CreatedDate = DateTime.UtcNow
        };

        context.Tenants.Add(tenant);
        context.SaveChanges();
        return tenant.Id;
    }

    private static int GetTenantId((int TenantAId, int TenantBId) tenantIds, string tenantCode)
        => tenantCode == TenantACode ? tenantIds.TenantAId : tenantIds.TenantBId;

    private static void SeedStubSampleData(OrderProcessingSystemDbContext context, int tenantId)
    {
        context.Customers.Add(new Customer
        {
            Name = "Stub Customer",
            Email = $"stub-{tenantId}@test.test",
            TenantId = tenantId,
            CreatedBy = 1,
            CreatedDate = DateTime.UtcNow
        });
        context.SaveChanges();

        var customerId = context.Customers.IgnoreQueryFilters().Where(c => c.TenantId == tenantId).Select(c => c.CustomerId).First();

        context.Products.Add(new Product
        {
            Name = "Stub Product",
            Description = "Stub",
            Price = 1m,
            TenantId = tenantId,
            CreatedBy = 1,
            CreatedDate = DateTime.UtcNow
        });
        context.SaveChanges();

        var productId = context.Products.IgnoreQueryFilters().Where(p => p.TenantId == tenantId).Select(p => p.ProductId).First();

        context.Database.ExecuteSqlInterpolated($"""
            INSERT INTO [orders].[Orders] (CustomerId, TenantId, CreatedBy, CreatedDate, OrderDate, Status, TotalPrice)
            VALUES ({customerId.Value}, {tenantId}, 1, {DateTime.UtcNow}, {DateTime.UtcNow}, {"Pending"}, {0m})
            """);
        context.SaveChanges();
    }

    private sealed class NoTenantProvider : ITenantProvider
    {
        public bool HasTenantContext => false;
        public int TenantId => 0;
        public string TenantCode => string.Empty;
        public string TenantExternalId => string.Empty;
        public string? ConnectionString => null;
        public bool IsSharedPool => true;
    }
}
