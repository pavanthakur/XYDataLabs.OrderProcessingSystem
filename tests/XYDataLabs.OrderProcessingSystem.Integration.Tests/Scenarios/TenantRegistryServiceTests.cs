using FluentAssertions;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Multitenancy;
using XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

#pragma warning disable CA2100

[Collection("SqlServer")]
[Trait("Category", "Integration")]
public sealed class TenantRegistryServiceTests : IAsyncLifetime
{
    private readonly SqlServerFixture _fixture;
    private string _databaseName = string.Empty;
    private string _connectionString = string.Empty;

    public TenantRegistryServiceTests(SqlServerFixture fixture)
    {
        _fixture = fixture;
    }

    public async Task InitializeAsync()
    {
        _databaseName = $"TenantRegistry_{Guid.NewGuid():N}";
        _connectionString = await CreateDatabaseAsync(_databaseName);
        await using var ctx = CreateContext();
        await ctx.Database.EnsureCreatedAsync();

        await ctx.Database.ExecuteSqlRawAsync(
            """
            SET IDENTITY_INSERT [Tenants] ON;
            INSERT INTO [Tenants] ([Id], [ExternalId], [Code], [Name], [Status], [TenantTier], [PaymentProviderCode], [CreatedBy], [CreatedDate])
            VALUES
                (1, 'ext-TENANTA', 'TenantA', 'Tenant A', 'Active', 'SharedPool', 'Razorpay', 1, SYSUTCDATETIME()),
                (2, 'ext-TENANTB', 'TenantB', 'Tenant B', 'Active', 'SharedPool', 'Razorpay', 1, SYSUTCDATETIME()),
                (3, 'ext-TENANTC', 'TenantC', 'Tenant C', 'Active', 'Dedicated', 'OpenPay', 1, SYSUTCDATETIME()),
                (4, 'ext-NOPROVIDER', 'TenantNoProvider', 'Tenant No Provider', 'Active', 'SharedPool', NULL, 1, SYSUTCDATETIME());
            SET IDENTITY_INSERT [Tenants] OFF;
            """);
    }

    public async Task DisposeAsync()
    {
        await DropDatabaseAsync(_databaseName);
    }

    [Theory]
    [InlineData("TenantA", "Razorpay")]
    [InlineData("TenantB", "Razorpay")]
    [InlineData("TenantC", "OpenPay")]
    public void FindByCode_KnownTenant_ReturnsEntryWithCorrectPaymentProviderCode(string tenantCode, string expectedProviderCode)
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
        svc.FindByCode("DoesNotExist").Should().BeNull();
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void FindByCode_NullOrWhitespace_ReturnsNullWithoutThrowing(string? tenantCode)
    {
        using var svc = CreateService();
        Action act = () => svc.FindByCode(tenantCode!);
        act.Should().NotThrow();
        svc.FindByCode(tenantCode!).Should().BeNull();
    }

    [Theory]
    [InlineData("TenantA", 1, "Tenant A", "SharedPool")]
    [InlineData("TenantC", 3, "Tenant C", "Dedicated")]
    public void FindByCode_MapsAllRegistryEntryFields(string tenantCode, int expectedId, string expectedName, string expectedTier)
    {
        using var svc = CreateService();
        var entry = svc.FindByCode(tenantCode);

        entry.Should().NotBeNull();
        entry!.TenantId.Should().Be(expectedId);
        entry.TenantCode.Should().Be(tenantCode);
        entry.TenantName.Should().Be(expectedName);
        entry.TenantTier.Should().Be(expectedTier);
    }

    [Theory]
    [InlineData("TenantA", "Razorpay")]
    [InlineData("TenantC", "OpenPay")]
    public async Task FindByCodeAsync_KnownTenant_ReturnsEntryWithCorrectPaymentProviderCode(string tenantCode, string expectedProviderCode)
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
        (await svc.FindByCodeAsync("DoesNotExist")).Should().BeNull();
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    public async Task FindByCodeAsync_NullOrEmpty_ReturnsNullWithoutThrowing(string? tenantCode)
    {
        using var svc = CreateService();
        (await svc.FindByCodeAsync(tenantCode!)).Should().BeNull();
    }

    private TenantRegistryDbContext CreateContext()
    {
        var options = new DbContextOptionsBuilder<TenantRegistryDbContext>()
            .UseSqlServer(_connectionString)
            .Options;
        return new TenantRegistryDbContext(options);
    }

    private ServiceWrapper CreateService()
    {
        var ctx = CreateContext();
        return new ServiceWrapper(new TenantRegistryService(ctx), ctx);
    }

    private async Task<string> CreateDatabaseAsync(string databaseName)
    {
        var master = new SqlConnectionStringBuilder(_fixture.ConnectionString) { InitialCatalog = "master" }.ConnectionString;
        await using var connection = new SqlConnection(master);
        await connection.OpenAsync();
        await using var command = new SqlCommand($"CREATE DATABASE [{databaseName}]", connection);
        await command.ExecuteNonQueryAsync();
        return new SqlConnectionStringBuilder(_fixture.ConnectionString) { InitialCatalog = databaseName }.ConnectionString;
    }

    private async Task DropDatabaseAsync(string databaseName)
    {
        var master = new SqlConnectionStringBuilder(_fixture.ConnectionString) { InitialCatalog = "master" }.ConnectionString;
        await using var connection = new SqlConnection(master);
        await connection.OpenAsync();
        await using var command = new SqlCommand($@"
IF DB_ID('{databaseName}') IS NOT NULL
BEGIN
    ALTER DATABASE [{databaseName}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [{databaseName}];
END", connection);
        await command.ExecuteNonQueryAsync();
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
        public Task<TenantRegistryEntry?> FindByCodeAsync(string tenantCode, CancellationToken ct = default) => _svc.FindByCodeAsync(tenantCode, ct);
        public void Dispose() => _ctx.Dispose();
    }
}
