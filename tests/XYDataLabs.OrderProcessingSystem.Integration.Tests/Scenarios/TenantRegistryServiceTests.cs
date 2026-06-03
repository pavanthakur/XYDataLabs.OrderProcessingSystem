using FluentAssertions;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Multitenancy;
using Xunit;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

/// <summary>
/// Unit-style tests for <see cref="TenantRegistryService"/> using an in-memory SQLite database.
/// Validates FindByCode / FindByCodeAsync return correct <see cref="TenantRegistryEntry"/> records
/// and handle null/empty/unknown inputs without throwing.
/// </summary>
[Trait("Category", "Integration")]
public sealed class TenantRegistryServiceTests : IDisposable
{
    private readonly SqliteConnection _connection;

    public TenantRegistryServiceTests()
    {
        _connection = new SqliteConnection("Data Source=:memory:");
        _connection.Open();

        using var ctx = CreateContext();
        ctx.Database.EnsureCreated();

        ctx.Tenants.AddRange(
            new Tenant
            {
                Id = 1,
                ExternalId = "ext-TENANTA",
                Code = "TenantA",
                Name = "Tenant A",
                Status = "Active",
                TenantTier = "SharedPool",
                PaymentProviderCode = "Razorpay",
                CreatedBy = 1,
                CreatedDate = DateTime.UtcNow
            },
            new Tenant
            {
                Id = 2,
                ExternalId = "ext-TENANTB",
                Code = "TenantB",
                Name = "Tenant B",
                Status = "Active",
                TenantTier = "SharedPool",
                PaymentProviderCode = "Razorpay",
                CreatedBy = 1,
                CreatedDate = DateTime.UtcNow
            },
            new Tenant
            {
                Id = 3,
                ExternalId = "ext-TENANTC",
                Code = "TenantC",
                Name = "Tenant C",
                Status = "Active",
                TenantTier = "Dedicated",
                PaymentProviderCode = "OpenPay",
                CreatedBy = 1,
                CreatedDate = DateTime.UtcNow
            },
            new Tenant
            {
                Id = 4,
                ExternalId = "ext-NOPROVIDER",
                Code = "TenantNoProvider",
                Name = "Tenant No Provider",
                Status = "Active",
                TenantTier = "SharedPool",
                PaymentProviderCode = null,
                CreatedBy = 1,
                CreatedDate = DateTime.UtcNow
            });
        ctx.SaveChanges();
    }

    public void Dispose() => _connection.Dispose();

    // ── FindByCode ────────────────────────────────────────────────────────────

    [Theory]
    [InlineData("TenantA", "Razorpay")]
    [InlineData("TenantB", "Razorpay")]
    [InlineData("TenantC", "OpenPay")]
    public void FindByCode_KnownTenant_ReturnsEntryWithCorrectPaymentProviderCode(
        string tenantCode, string expectedProviderCode)
    {
        using var svc = CreateService();

        var entry = svc.FindByCode(tenantCode);

        entry.Should().NotBeNull();
        entry!.TenantCode.Should().Be(tenantCode);
        entry.PaymentProviderCode.Should().Be(expectedProviderCode);
    }

    [Fact]
    public void FindByCode_TenantWithNullPaymentProviderCode_ReturnsEntryWithNullProviderCode()
    {
        using var svc = CreateService();

        var entry = svc.FindByCode("TenantNoProvider");

        entry.Should().NotBeNull();
        entry!.PaymentProviderCode.Should().BeNull();
    }

    [Fact]
    public void FindByCode_UnknownTenant_ReturnsNull()
    {
        using var svc = CreateService();

        var entry = svc.FindByCode("DoesNotExist");

        entry.Should().BeNull();
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void FindByCode_NullOrWhitespace_ReturnsNullWithoutThrowing(string? tenantCode)
    {
        using var svc = CreateService();

        var act = () => svc.FindByCode(tenantCode!);

        act.Should().NotThrow();
        act().Should().BeNull();
    }

    [Theory]
    [InlineData("TenantA", 1, "Tenant A", "SharedPool")]
    [InlineData("TenantC", 3, "Tenant C", "Dedicated")]
    public void FindByCode_MapsAllRegistryEntryFields(
        string tenantCode, int expectedId, string expectedName, string expectedTier)
    {
        using var svc = CreateService();

        var entry = svc.FindByCode(tenantCode);

        entry.Should().NotBeNull();
        entry!.TenantId.Should().Be(expectedId);
        entry.TenantCode.Should().Be(tenantCode);
        entry.TenantName.Should().Be(expectedName);
        entry.TenantTier.Should().Be(expectedTier);
    }

    // ── FindByCodeAsync ───────────────────────────────────────────────────────

    [Theory]
    [InlineData("TenantA", "Razorpay")]
    [InlineData("TenantC", "OpenPay")]
    public async Task FindByCodeAsync_KnownTenant_ReturnsEntryWithCorrectPaymentProviderCode(
        string tenantCode, string expectedProviderCode)
    {
        using var svc = CreateService();

        var entry = await svc.FindByCodeAsync(tenantCode);

        entry.Should().NotBeNull();
        entry!.TenantCode.Should().Be(tenantCode);
        entry.PaymentProviderCode.Should().Be(expectedProviderCode);
    }

    [Fact]
    public async Task FindByCodeAsync_UnknownTenant_ReturnsNull()
    {
        using var svc = CreateService();

        var entry = await svc.FindByCodeAsync("DoesNotExist");

        entry.Should().BeNull();
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    public async Task FindByCodeAsync_NullOrEmpty_ReturnsNullWithoutThrowing(string? tenantCode)
    {
        using var svc = CreateService();

        var entry = await svc.FindByCodeAsync(tenantCode!);

        entry.Should().BeNull();
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private TenantRegistryDbContext CreateContext()
    {
        var options = new DbContextOptionsBuilder<TenantRegistryDbContext>()
            .UseSqlite(_connection)
            .Options;
        return new TenantRegistryDbContext(options);
    }

    private ServiceWrapper CreateService()
    {
        var ctx = CreateContext();
        return new ServiceWrapper(new TenantRegistryService(ctx), ctx);
    }

    private sealed class ServiceWrapper : IDisposable
    {
        private readonly TenantRegistryDbContext _ctx;
        private readonly TenantRegistryService _svc;

        public ServiceWrapper(TenantRegistryService svc, TenantRegistryDbContext ctx)
        {
            _svc = svc;
            _ctx = ctx;
        }

        public TenantRegistryEntry? FindByCode(string tenantCode) => _svc.FindByCode(tenantCode);
        public Task<TenantRegistryEntry?> FindByCodeAsync(string tenantCode, CancellationToken ct = default)
            => _svc.FindByCodeAsync(tenantCode, ct);

        public void Dispose() => _ctx.Dispose();
    }
}
