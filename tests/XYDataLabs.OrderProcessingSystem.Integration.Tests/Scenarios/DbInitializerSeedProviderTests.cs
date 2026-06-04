using FluentAssertions;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using XYDataLabs.OrderProcessingSystem.Application.Events;
using XYDataLabs.OrderProcessingSystem.Application.Features.Orders.Events;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.Infrastructure.SeedData;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

/// <summary>
/// Validates that <see cref="DbInitializer"/> preserves database-selected providers and falls back
/// to a generic seed default only when a tenant has no active provider row yet.
/// These tests run against an in-memory SQLite database so they are fast and require no container.
/// </summary>
[Trait("Category", "Integration")]
public sealed class DbInitializerSeedProviderTests : IDisposable
{
    // Mirrors DbInitializer.StartupSeedTenantCodes — both tenants must be present before Initialize() runs.
    private const int TenantAId = 1001;
    private const int TenantBId = 1002;
    private const int UnknownTenantId = 9999;

    private readonly SqliteConnection _connection;
    private readonly IIntegrationEventMapperRegistry _emptyRegistry;

    public DbInitializerSeedProviderTests()
    {
        _connection = new SqliteConnection("Data Source=:memory:");
        _connection.Open();

        _emptyRegistry = new IntegrationEventMapperRegistry(
            new IDomainEventToIntegrationEventMapper[] { new OrderCreatedDomainEventMapper() });

        using var context = CreateContext();
        context.Database.EnsureCreated();
    }

    public void Dispose() => _connection.Dispose();

    [Theory]
    [InlineData("TenantA", TenantAId, false, true)]  // TenantA: Razorpay 3DS off (Checkout JS popup, SAQ A), OpenPay on
    [InlineData("TenantB", TenantBId, true,  true)]  // TenantB: both providers 3DS on
    public void Initialize_WhenNoProviderRowsExist_SeedsBothProvidersAsInactive(
        string tenantCode, int tenantId, bool expectedRazorpay3DS, bool expectedOpenPay3DS)
    {
        // Phase 8.6: active provider is authoritative from Tenant.PaymentProviderCode (Tenant Registry).
        // DbInitializer seeds both providers with IsActive=false for every tenant on a fresh database.
        // Use3DSecure is determined by the seed-data dictionary in DbInitializer (DB is source of truth at runtime).
        using var seedContext = CreateContext();
        SeedBothBaselineTenants(seedContext);

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
        opy.Use3DSecure.Should().Be(expectedOpenPay3DS,
            $"{tenantCode} OpenPay Use3DSecure should match seed-data dictionary default");
        rzp.Use3DSecure.Should().Be(expectedRazorpay3DS,
            $"{tenantCode} Razorpay Use3DSecure should match seed-data dictionary default");
        providers.Should().OnlyContain(
            provider => !provider.IsActive,
            $"new provider rows must be seeded IsActive=false — active provider is resolved from Tenant Registry (Tenant.PaymentProviderCode), not DbInitializer ({tenantCode})");
    }

    [Theory]
    [InlineData("TenantA", TenantAId)]
    [InlineData("TenantB", TenantBId)]
    public void Initialize_WhenProvidersAlreadyExist_PreservesDatabaseSelectedActiveState(
        string tenantCode, int tenantId)
    {
        using var seedContext = CreateContext();
        SeedBothBaselineTenants(seedContext);

        // Pre-seed both providers with wrong IsActive state (inverted).
        seedContext.PaymentProviders.AddRange(
            new PaymentProvider
            {
                Name = "OpenPay",
                APIUrl = "https://sandbox-api.openpay.mx/v1",
                IsActive = true,   // wrong: TenantA/B should have OpenPay inactive
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
                IsActive = false,  // wrong: TenantA/B should have Razorpay active
                IsProduction = false,
                ProviderType = PaymentProviderTypes.Razorpay,
                Use3DSecure = false,
                TenantId = tenantId,
                CreatedBy = 1,
                CreatedDate = DateTime.UtcNow
            });
        seedContext.SaveChanges();

        DbInitializer.Initialize(
            seedContext,
            configuration: null,
            applyMigrations: false,
            integrationEventMapperRegistry: _emptyRegistry);

        var providers = seedContext.PaymentProviders
            .IgnoreQueryFilters()
            .Where(pp => pp.TenantId == tenantId)
            .ToList();

        providers.Single(pp => pp.ProviderType == PaymentProviderTypes.Razorpay).IsActive
            .Should().BeFalse($"startup seeding must preserve the runtime-selected inactive state for {tenantCode}");

        providers.Single(pp => pp.ProviderType == PaymentProviderTypes.OpenPay).IsActive
            .Should().BeTrue($"startup seeding must preserve the runtime-selected active state for {tenantCode}");
    }

    [Theory]
    [InlineData("TenantA", TenantAId, PaymentProviderTypes.Razorpay)]
    [InlineData("TenantB", TenantBId, PaymentProviderTypes.Razorpay)]
    public void Initialize_WhenActiveProviderAlreadyExists_AddsMissingProviderInactive(
        string tenantCode, int tenantId, string activeProviderType)
    {
        using var seedContext = CreateContext();
        SeedBothBaselineTenants(seedContext);

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

        DbInitializer.Initialize(
            seedContext,
            configuration: null,
            applyMigrations: false,
            integrationEventMapperRegistry: _emptyRegistry);

        var providers = seedContext.PaymentProviders
            .IgnoreQueryFilters()
            .Where(pp => pp.TenantId == tenantId)
            .ToList();

        providers.Should().HaveCount(2, $"DbInitializer should backfill the missing provider for {tenantCode}");
        providers.Count(pp => pp.IsActive).Should().Be(1, "adding a missing provider must not introduce dual-active state");
        providers.Single(pp => pp.ProviderType == activeProviderType).IsActive.Should().BeTrue();
        providers.Single(pp => pp.ProviderType != activeProviderType).IsActive.Should().BeFalse();
    }

    [Fact]
    public void Initialize_AlwaysSeedsBothProvidersAsInactiveRegardlessOfTenantState()
    {
        // Phase 8.6: DbInitializer no longer resolves an active provider.
        // All StartupSeedTenantCodes tenants should have both providers seeded as inactive,
        // regardless of whether provider rows previously existed.
        using var seedContext = CreateContext();

        SeedTenant(seedContext, TenantAId, "TenantA");
        SeedTenant(seedContext, TenantBId, "TenantB");
        seedContext.SaveChanges();
        SeedStubSampleData(seedContext, TenantAId);
        SeedStubSampleData(seedContext, TenantBId);

        SeedTenant(seedContext, UnknownTenantId, "UnknownTenant");
        seedContext.SaveChanges();

        DbInitializer.Initialize(
            seedContext,
            configuration: null,
            applyMigrations: false,
            integrationEventMapperRegistry: _emptyRegistry);

        foreach (var tenantId in new[] { TenantAId, TenantBId })
        {
            var providers = seedContext.PaymentProviders
                .IgnoreQueryFilters()
                .Where(pp => pp.TenantId == tenantId)
                .ToList();

            providers.Should().HaveCount(2, $"DbInitializer seeds both providers for TenantId={tenantId}");
            providers.Should().OnlyContain(
                pp => !pp.IsActive,
                $"all seeded providers must be inactive — routing authority is Tenant Registry (TenantId={tenantId})");
        }

        // UnknownTenant (outside StartupSeedTenantCodes) should have no providers seeded.
        seedContext.PaymentProviders
            .IgnoreQueryFilters()
            .Where(pp => pp.TenantId == UnknownTenantId)
            .Should().BeEmpty("DbInitializer only seeds providers for StartupSeedTenantCodes");
    }

    [Fact]
    public void Initialize_WithConfiguration_BackfillsProviderRuntimeFields()
    {
        using var seedContext = CreateContext();
        SeedBothBaselineTenants(seedContext);

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

        DbInitializer.Initialize(
            seedContext,
            configuration: configuration,
            applyMigrations: false,
            integrationEventMapperRegistry: _emptyRegistry);

        var tenantAProviders = seedContext.PaymentProviders
            .IgnoreQueryFilters()
            .Where(pp => pp.TenantId == TenantAId)
            .ToList();

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

    // ── Helpers ──────────────────────────────────────────────────────────────

    private OrderProcessingSystemDbContext CreateContext()
    {
        var options = new DbContextOptionsBuilder<OrderProcessingSystemDbContext>()
            .UseSqlite(_connection)
            .Options;

        // HasTenantContext=false: EF global query filter short-circuits to true so all rows are visible.
        // This mirrors how DbInitializer is called at startup (no active HTTP context / no tenant scope).
        return new SqliteOrderProcessingSystemDbContext(options, new NoTenantProvider(), _emptyRegistry);
    }

    private static void SeedBothBaselineTenants(OrderProcessingSystemDbContext context)
    {
        SeedTenant(context, TenantAId, "TenantA");
        SeedTenant(context, TenantBId, "TenantB");
        context.SaveChanges();

        // Pre-populate stub sample data so SeedTenantSampleData() skips those paths.
        // Avoids SQLite-incompatible SysId sequence behaviour in SeedOrders.
        SeedStubSampleData(context, TenantAId);
        SeedStubSampleData(context, TenantBId);
    }

    private static void SeedTenant(
        OrderProcessingSystemDbContext context,
        int tenantId,
        string tenantCode)
    {
        if (context.Tenants.Any(t => t.Id == tenantId))
            return;

        context.Tenants.Add(new Tenant
        {
            Id = tenantId,
            ExternalId = $"ext-{tenantCode.ToUpperInvariant()}",
            Code = tenantCode,
            Name = $"Test {tenantCode}",
            Status = "Active",
            TenantTier = "SharedPool",
            CreatedBy = 1,
            CreatedDate = DateTime.UtcNow
        });
    }

    /// <summary>
    /// Inserts one stub Customer, Product, and Order per tenant so DbInitializer's
    /// <c>if (!context.X.Any(...))</c> guards skip sample-data seeding.
    /// This avoids SQLite-incompatible sequence/domain-event behaviour in <c>SeedOrders</c>.
    /// </summary>
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

        var customerId = context.Customers
            .IgnoreQueryFilters()
            .Where(c => c.TenantId == tenantId)
            .Select(c => c.CustomerId)
            .First();

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

        var productId = context.Products
            .IgnoreQueryFilters()
            .Where(p => p.TenantId == tenantId)
            .Select(p => p.ProductId)
            .First();

        // Insert an Order row directly to satisfy the "any orders?" guard without triggering domain events.
        // RowVersion is required NOT NULL in the SQLite schema (even with ValueGeneratedNever override).
        context.Database.ExecuteSqlRaw(
            $"INSERT INTO Orders (CustomerId, TenantId, CreatedBy, CreatedDate, OrderDate, Status, TotalPrice, RowVersion) VALUES ({customerId.Value}, {tenantId}, 1, datetime('now'), datetime('now'), 'Pending', 0, X'0000000000000001')");
        context.SaveChanges();
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

            // SQLite does not support rowversion — disable optimistic concurrency for these tests.
            modelBuilder.Entity<Order>()
                .Property(o => o.RowVersion)
                .IsConcurrencyToken()
                .ValueGeneratedNever();
        }
    }

    /// <summary>
    /// Tenant provider with no active tenant context. EF global query filter short-circuits to true
    /// (all rows visible), matching the startup context in which DbInitializer runs.
    /// </summary>
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
