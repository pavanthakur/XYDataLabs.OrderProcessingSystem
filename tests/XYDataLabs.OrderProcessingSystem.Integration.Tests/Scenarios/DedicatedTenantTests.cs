using System.Net;
using FluentAssertions;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Domain.Entities;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;
using Xunit;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

[Collection("SqlServer")]
[Trait("Category", "Integration")]
public sealed class DedicatedTenantTests : IAsyncLifetime
{
    private readonly SqlServerFixture _fixture;

    /// <summary>Single-DB factory — used for middleware/status tests that don't need routing.</summary>
    private IntegrationTestWebAppFactory _sharedFactory = null!;

    /// <summary>Routing-aware factory — routes Dedicated tenants to a separate physical DB.</summary>
    private IntegrationTestWebAppFactory _routingFactory = null!;

    public DedicatedTenantTests(SqlServerFixture fixture)
    {
        _fixture = fixture;
    }

    public async Task InitializeAsync()
    {
        _sharedFactory = new IntegrationTestWebAppFactory(_fixture.ConnectionString);
        _ = _sharedFactory.CreateClient();

        // Run migrations on the dedicated database so EF schema is present.
        var dedicatedOptions = new DbContextOptionsBuilder<OrderProcessingSystemDbContext>()
            .UseSqlServer(_fixture.DedicatedDbConnectionString)
            .Options;

        await using var dedicatedContext = new OrderProcessingSystemDbContext(dedicatedOptions);
        await dedicatedContext.Database.MigrateAsync();

        _routingFactory = new IntegrationTestWebAppFactory(
            _fixture.ConnectionString, _fixture.DedicatedDbConnectionString);
        _ = _routingFactory.CreateClient();
    }

    public async Task DisposeAsync()
    {
        await _routingFactory.DisposeAsync();
        await _sharedFactory.DisposeAsync();
    }

    // ──────────────────────────────────────── Middleware / status tests ──

    [Fact]
    public async Task DedicatedTenant_WithoutConnectionString_ReturnsBadRequest()
    {
        // Dedicated tenant with NULL connection string → resolver cannot route → 400.
        var tenant = await IntegrationTestData.CreateDedicatedTenantAsync(
            _sharedFactory, connectionString: null, status: "Active");

        using var client = _sharedFactory.CreateTenantClient(tenant.TenantCode);
        var response = await client.GetAsync("/health");

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task DedicatedTenant_Unprovisioned_Suspended_ReturnsBadRequest()
    {
        // Unprovisioned (null CS) + Suspended → unresolvable takes priority → 400.
        var tenant = await IntegrationTestData.CreateDedicatedTenantAsync(
            _sharedFactory, connectionString: null, status: "Suspended");

        using var client = _sharedFactory.CreateTenantClient(tenant.TenantCode);
        var response = await client.GetAsync("/health");

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task DedicatedTenant_Provisioned_Suspended_ReturnsForbidden()
    {
        // Provisioned with a real CS + Suspended → status check fires → 403.
        var tenant = await IntegrationTestData.CreateDedicatedTenantAsync(
            _sharedFactory, connectionString: _fixture.DedicatedDbConnectionString, status: "Suspended");

        using var client = _sharedFactory.CreateTenantClient(tenant.TenantCode);
        var response = await client.GetAsync("/health");

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task DedicatedTenant_Provisioned_Decommissioned_ReturnsForbidden()
    {
        var tenant = await IntegrationTestData.CreateDedicatedTenantAsync(
            _sharedFactory, connectionString: _fixture.DedicatedDbConnectionString, status: "Decommissioned");

        using var client = _sharedFactory.CreateTenantClient(tenant.TenantCode);
        var response = await client.GetAsync("/health");

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task DedicatedTenant_Provisioned_Active_ResolvesSuccessfully()
    {
        // Provisioned + Active → resolves, routed to dedicated DB → successful API response.
        var tenant = await IntegrationTestData.CreateDedicatedTenantAsync(
            _routingFactory, connectionString: _fixture.DedicatedDbConnectionString, status: "Active");

        // Ensure the tenant row exists in the dedicated DB for FK integrity
        await SeedTenantRowInDedicatedDbAsync(tenant);

        // Use an API endpoint (not /health) to exercise the full tenant middleware + DbContext routing.
        using var client = _routingFactory.CreateTenantClient(tenant.TenantCode);
        var response = await client.GetAsync("/api/v1/customer/GetAllCustomers");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task SharedPoolTenant_StillWorks_AlongsideDedicatedTenants()
    {
        // Verifies SharedPool tenants are unaffected by dedicated tenant registration.
        var sharedTenant = await IntegrationTestData.CreateTenantAsync(_routingFactory);
        var dedicatedTenant = await IntegrationTestData.CreateDedicatedTenantAsync(
            _routingFactory, connectionString: _fixture.DedicatedDbConnectionString);

        await SeedTenantRowInDedicatedDbAsync(dedicatedTenant);

        // Use an API endpoint (not /health) to exercise the full tenant middleware + DbContext routing.
        using var sharedClient = _routingFactory.CreateTenantClient(sharedTenant.TenantCode);
        using var dedicatedClient = _routingFactory.CreateTenantClient(dedicatedTenant.TenantCode);

        var sharedResponse = await sharedClient.GetAsync("/api/v1/customer/GetAllCustomers");
        var dedicatedResponse = await dedicatedClient.GetAsync("/api/v1/customer/GetAllCustomers");

        sharedResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        dedicatedResponse.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    // ──────────────────────────────────────── Physical DB isolation tests ──

    [Fact]
    public async Task DedicatedTenant_Data_Is_Physically_Isolated_From_SharedPool()
    {
        // Seed a SharedPool tenant in the shared DB.
        var sharedTenant = await IntegrationTestData.CreateTenantAsync(_routingFactory);
        var sharedSeed = await IntegrationTestData.SeedTenantIsolationAsync(
            _routingFactory, sharedTenant.TenantId, "shared-iso");

        // Seed a Dedicated tenant — routing factory sends writes to the dedicated DB.
        var dedicatedTenant = await IntegrationTestData.CreateDedicatedTenantAsync(
            _routingFactory, connectionString: _fixture.DedicatedDbConnectionString);

        await SeedTenantRowInDedicatedDbAsync(dedicatedTenant);

        await _routingFactory.ExecuteTenantDbContextAsync(
            dedicatedTenant.ToTenantContext(),
            async dbContext =>
            {
                var customer = new Customer
                {
                    Name = "Dedicated-Isolation Customer",
                    Email = "dedicated-iso@test.com",
                    TenantId = dedicatedTenant.TenantId,
                    CreatedBy = 1,
                    CreatedDate = DateTime.UtcNow
                };
                dbContext.Customers.Add(customer);
                await dbContext.SaveChangesAsync();
                return customer;
            });

        // Verify: dedicated tenant's data exists in dedicated DB via direct SQL.
        var dedicatedCustomerCount = await CountCustomersByEmailAsync(
            _fixture.DedicatedDbConnectionString, "dedicated-iso@test.com");
        dedicatedCustomerCount.Should().Be(1, because: "the customer was routed to the dedicated DB");

        // Verify: shared pool tenant's data is NOT in the dedicated DB.
        var sharedInDedicated = await CountCustomersByEmailAsync(
            _fixture.DedicatedDbConnectionString, sharedSeed.CustomerEmail);
        sharedInDedicated.Should().Be(0, because: "shared-pool data must not leak into the dedicated DB");
    }

    [Fact]
    public async Task DedicatedTenant_Data_Not_Visible_Via_Direct_SharedPool_Query()
    {
        var dedicatedTenant = await IntegrationTestData.CreateDedicatedTenantAsync(
            _routingFactory, connectionString: _fixture.DedicatedDbConnectionString);

        await SeedTenantRowInDedicatedDbAsync(dedicatedTenant);

        // Write to dedicated DB through routing factory.
        await _routingFactory.ExecuteTenantDbContextAsync(
            dedicatedTenant.ToTenantContext(),
            async dbContext =>
            {
                dbContext.Customers.Add(new Customer
                {
                    Name = "Dedicated-Only Customer",
                    Email = "dedicated-only@test.com",
                    TenantId = dedicatedTenant.TenantId,
                    CreatedBy = 1,
                    CreatedDate = DateTime.UtcNow
                });
                await dbContext.SaveChangesAsync();
                return true;
            });

        // Query shared DB directly — the dedicated tenant's data must not be there.
        var countInShared = await CountCustomersByEmailAsync(
            _fixture.ConnectionString, "dedicated-only@test.com");
        countInShared.Should().Be(0, because: "dedicated tenant data must not exist in the shared-pool database");
    }

    [Fact]
    public async Task SharedPool_Data_Not_Visible_Via_Direct_DedicatedDb_Query()
    {
        var sharedTenant = await IntegrationTestData.CreateTenantAsync(_routingFactory);
        var sharedSeed = await IntegrationTestData.SeedTenantIsolationAsync(
            _routingFactory, sharedTenant.TenantId, "shared-only");

        // The shared tenant's data should be in the shared DB only.
        var countInShared = await CountCustomersByEmailAsync(
            _fixture.ConnectionString, sharedSeed.CustomerEmail);
        countInShared.Should().Be(1, because: "shared-pool tenant data lives in the shared DB");

        var countInDedicated = await CountCustomersByEmailAsync(
            _fixture.DedicatedDbConnectionString, sharedSeed.CustomerEmail);
        countInDedicated.Should().Be(0, because: "shared-pool data must not appear in the dedicated tenant database");
    }

    [Fact]
    public async Task DedicatedTenant_AuditLogs_Are_Written_To_Dedicated_Database()
    {
        var dedicatedTenant = await IntegrationTestData.CreateDedicatedTenantAsync(
            _routingFactory, connectionString: _fixture.DedicatedDbConnectionString);

        await SeedTenantRowInDedicatedDbAsync(dedicatedTenant);

        var entityId = await _routingFactory.ExecuteTenantDbContextAsync(
            dedicatedTenant.ToTenantContext(),
            async dbContext =>
            {
                var customer = new Customer
                {
                    Name = "Dedicated Audit Customer",
                    Email = $"dedicated-audit-{Guid.NewGuid():N}@test.com",
                    TenantId = dedicatedTenant.TenantId,
                    CreatedBy = 1,
                    CreatedDate = DateTime.UtcNow
                };

                dbContext.Customers.Add(customer);
                await dbContext.SaveChangesAsync();
                return $"CustomerId={customer.CustomerId}";
            });

        var dedicatedAuditCount = await CountAuditLogsAsync(
            _fixture.DedicatedDbConnectionString,
            "Customer",
            entityId,
            "Created");

        var sharedAuditCount = await CountAuditLogsAsync(
            _fixture.ConnectionString,
            "Customer",
            entityId,
            "Created");

        dedicatedAuditCount.Should().Be(1, because: "dedicated tenant audit rows must be written to the dedicated database");
        sharedAuditCount.Should().Be(0, because: "dedicated tenant audit rows must not leak into the shared-pool database");
    }

    // ──────────────────────────────────────── Helpers ──

    /// <summary>
    /// Copies the tenant registry row to the dedicated database so that FK constraints
    /// on tenant-owned entities (e.g. Customer.TenantId → Tenants.Id) are satisfied.
    /// Uses IDENTITY_INSERT to match the same Id as in the shared (registry) DB.
    /// </summary>
    private async Task SeedTenantRowInDedicatedDbAsync(TestTenantContext tenant)
    {
        using var connection = new SqlConnection(_fixture.DedicatedDbConnectionString);
        await connection.OpenAsync();

        // BannedSymbols.txt bans SqlCommand(string) — use parameterless ctor.
        using var command = new SqlCommand();
        command.Connection = connection;
        command.CommandText = @"
            IF NOT EXISTS (SELECT 1 FROM Tenants WHERE Id = @Id)
            BEGIN
                SET IDENTITY_INSERT Tenants ON;
                INSERT INTO Tenants (Id, ExternalId, Code, Name, Status, TenantTier, CreatedBy, CreatedDate)
                VALUES (@Id, @ExternalId, @Code, @Name, @Status, @TenantTier, 1, GETUTCDATE());
                SET IDENTITY_INSERT Tenants OFF;
            END";

        command.Parameters.AddWithValue("@Id", tenant.TenantId);
        command.Parameters.AddWithValue("@ExternalId", tenant.TenantExternalId);
        command.Parameters.AddWithValue("@Code", tenant.TenantCode);
        command.Parameters.AddWithValue("@Name", tenant.TenantName);
        command.Parameters.AddWithValue("@Status", tenant.TenantStatus);
        command.Parameters.AddWithValue("@TenantTier", TenantTierConstants.Dedicated);

        await command.ExecuteNonQueryAsync();
    }

    /// <summary>
    /// Counts customer rows by email via parameterized SQL.
    /// Used to verify physical isolation without going through EF query filters.
    /// </summary>
    private static async Task<int> CountCustomersByEmailAsync(string connectionString, string email)
    {
        const string sql = "SELECT COUNT(*) FROM [Customers] WHERE Email = @Email";

        using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync();

        // BannedSymbols.txt bans SqlCommand(string) — use parameterless ctor.
        using var command = new SqlCommand();
        command.Connection = connection;
        command.CommandText = sql;
        command.Parameters.AddWithValue("@Email", email);

        var result = await command.ExecuteScalarAsync();
        return Convert.ToInt32(result, System.Globalization.CultureInfo.InvariantCulture);
    }

    private static async Task<int> CountAuditLogsAsync(string connectionString, string entityName, string entityId, string operation)
    {
        const string sql = @"
            SELECT COUNT(*)
            FROM [AuditLogs]
            WHERE [EntityName] = @EntityName
              AND [EntityId] = @EntityId
              AND [Operation] = @Operation";

        using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync();

        using var command = new SqlCommand();
        command.Connection = connection;
        command.CommandText = sql;
        command.Parameters.AddWithValue("@EntityName", entityName);
        command.Parameters.AddWithValue("@EntityId", entityId);
        command.Parameters.AddWithValue("@Operation", operation);

        var result = await command.ExecuteScalarAsync();
        return Convert.ToInt32(result, System.Globalization.CultureInfo.InvariantCulture);
    }
}
