using FluentAssertions;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using System.Diagnostics.CodeAnalysis;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Scenarios;

[Collection("SqlServer")]
[Trait("Category", "Integration")]
public sealed class OrderMigrationTests
{
    private const string MigrationBeforeOrderRefactor = "20260405122636_AddAuditLog";
    private readonly SqlServerFixture _fixture;

    public OrderMigrationTests(SqlServerFixture fixture)
    {
        _fixture = fixture;
    }

    [Fact]
    public async Task OrderStatusMigration_Should_Backfill_From_IsFulfilled_Without_Data_Loss()
    {
        var databaseName = $"OrderMigration_{Guid.NewGuid():N}";
        var databaseConnectionString = await CreateDatabaseAsync(databaseName);

        try
        {
            var options = new DbContextOptionsBuilder<OrderProcessingSystemDbContext>()
                .UseSqlServer(databaseConnectionString)
                .Options;

            await using (var context = new OrderProcessingSystemDbContext(options))
            {
                var migrator = context.Database.GetService<IMigrator>();
                await migrator.MigrateAsync(MigrationBeforeOrderRefactor);
            }

            var orderIds = await SeedLegacyOrdersAsync(databaseConnectionString);

            await using (var context = new OrderProcessingSystemDbContext(options))
            {
                var migrator = context.Database.GetService<IMigrator>();
                await migrator.MigrateAsync();
            }

            var migratedOrders = await ReadMigratedOrdersAsync(databaseConnectionString, orderIds);

            migratedOrders.Should().HaveCount(2);
            migratedOrders[0].Status.Should().Be("Created");
            migratedOrders[1].Status.Should().Be("Delivered");
            migratedOrders.All(order => order.RowVersionLength == 8).Should().BeTrue();
        }
        finally
        {
            await DropDatabaseAsync(databaseName);
        }
    }

    [SuppressMessage(
        "Security",
        "CA2100:Review SQL queries for security vulnerabilities",
        Justification = "The database name is generated inside the test and used only as a quoted SQL identifier on an isolated Testcontainers SQL Server instance.")]
    private async Task<string> CreateDatabaseAsync(string databaseName)
    {
        var masterConnectionString = BuildConnectionString("master");

        await using var connection = new SqlConnection(masterConnectionString);
        await connection.OpenAsync();

        await using var command = new SqlCommand();
        command.Connection = connection;
        command.CommandText = $"CREATE DATABASE [{databaseName}]";
        await command.ExecuteNonQueryAsync();

        return BuildConnectionString(databaseName);
    }

    [SuppressMessage(
        "Security",
        "CA2100:Review SQL queries for security vulnerabilities",
        Justification = "The database name is generated inside the test and used only as a quoted SQL identifier on an isolated Testcontainers SQL Server instance.")]
    private async Task DropDatabaseAsync(string databaseName)
    {
        var masterConnectionString = BuildConnectionString("master");

        await using var connection = new SqlConnection(masterConnectionString);
        await connection.OpenAsync();

        await using var command = new SqlCommand();
        command.Connection = connection;
        command.CommandText = $@"
IF DB_ID('{databaseName}') IS NOT NULL
BEGIN
    ALTER DATABASE [{databaseName}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [{databaseName}];
END";

        await command.ExecuteNonQueryAsync();
    }

    private async Task<int[]> SeedLegacyOrdersAsync(string connectionString)
    {
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync();

        const string sql = @"
DECLARE @tenantId int = (SELECT TOP (1) [Id] FROM [Tenants] WHERE [Code] = 'TenantA');

INSERT INTO [Customers] ([Name], [Email], [TenantId], [CreatedBy], [CreatedDate])
VALUES (N'Migration Customer', N'migration-customer@test.com', @tenantId, 1, SYSUTCDATETIME());

DECLARE @customerId int = SCOPE_IDENTITY();

INSERT INTO [Orders] ([OrderDate], [CustomerId], [TotalPrice], [IsFulfilled], [TenantId], [CreatedBy], [CreatedDate])
VALUES
    (SYSUTCDATETIME(), @customerId, 10.00, 0, @tenantId, 1, SYSUTCDATETIME()),
    (SYSUTCDATETIME(), @customerId, 20.00, 1, @tenantId, 1, SYSUTCDATETIME());

SELECT CAST([OrderId] AS int)
FROM [Orders]
WHERE [CustomerId] = @customerId
ORDER BY [OrderId];";

        await using var command = new SqlCommand(sql, connection);
        var orderIds = new List<int>();

        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            orderIds.Add(reader.GetInt32(0));
        }

        return orderIds.ToArray();
    }

    private static async Task<List<MigratedOrderRow>> ReadMigratedOrdersAsync(string connectionString, IReadOnlyList<int> orderIds)
    {
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync();

        const string sql = @"
SELECT [OrderId], [Status], DATALENGTH([RowVersion])
FROM [Orders]
WHERE [OrderId] IN (@firstOrderId, @secondOrderId)
ORDER BY [OrderId];";

        await using var command = new SqlCommand(sql, connection);
        command.Parameters.AddWithValue("@firstOrderId", orderIds[0]);
        command.Parameters.AddWithValue("@secondOrderId", orderIds[1]);

        var rows = new List<MigratedOrderRow>();
        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            rows.Add(new MigratedOrderRow(
                reader.GetInt32(0),
                reader.GetString(1),
                reader.GetInt32(2)));
        }

        return rows;
    }

    private string BuildConnectionString(string databaseName)
    {
        var builder = new SqlConnectionStringBuilder(_fixture.ConnectionString)
        {
            InitialCatalog = databaseName
        };

        return builder.ConnectionString;
    }

    private sealed record MigratedOrderRow(int OrderId, string Status, int RowVersionLength);
}