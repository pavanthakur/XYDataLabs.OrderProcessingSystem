using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using Xunit;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;

public sealed class SqlServerFixture : IAsyncLifetime
{
    private const string DedicatedDatabaseName = "DedicatedTenantDb";
    private readonly string _connectionString;
    private string _dedicatedConnectionString = string.Empty;

    public SqlServerFixture()
    {
        var connectionString = Environment.GetEnvironmentVariable("ORDERPROCESSING_TEST_CONNECTION_STRING");
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            connectionString = BuildLocalConnectionStringFromEnvFile()
                ?? throw new InvalidOperationException(
                    "ORDERPROCESSING_TEST_CONNECTION_STRING must be set for local integration tests.");
        }

        var builder = new SqlConnectionStringBuilder(connectionString)
        {
            TrustServerCertificate = true,
            Encrypt = false,
            MultipleActiveResultSets = false
        };
        _connectionString = builder.ConnectionString;
    }

    public string ConnectionString => _connectionString;

    public string DedicatedDbConnectionString => _dedicatedConnectionString;

    public async Task InitializeAsync()
    {
        await EnsureSharedDatabaseSchemaAsync();
        _dedicatedConnectionString = await CreateDedicatedDatabaseAsync();
    }

    public Task DisposeAsync() => Task.CompletedTask;

    private static string? BuildLocalConnectionStringFromEnvFile()
    {
        var envFilePath = FindEnvLocalFilePath();
        if (envFilePath is null)
        {
            return null;
        }

        var sqlPassword = File.ReadLines(envFilePath)
            .FirstOrDefault(line => line.StartsWith("LOCAL_SQL_PASSWORD=", StringComparison.OrdinalIgnoreCase));

        if (string.IsNullOrWhiteSpace(sqlPassword))
        {
            return null;
        }

        var password = sqlPassword.Split('=', 2)[1].Trim();
        if (string.IsNullOrWhiteSpace(password))
        {
            return null;
        }

        return new SqlConnectionStringBuilder
        {
            DataSource = "localhost,1433",
            InitialCatalog = $"OrderProcessingSystem_Integration_{DateTime.UtcNow:yyyyMMdd-HHmmss}",
            UserID = "sa",
            Password = password,
            TrustServerCertificate = true,
            Encrypt = false,
            MultipleActiveResultSets = false
        }.ConnectionString;
    }

    private static string? FindEnvLocalFilePath()
    {
        var searchRoots = new[]
        {
            AppContext.BaseDirectory,
            Directory.GetCurrentDirectory()
        };

        foreach (var root in searchRoots)
        {
            var current = new DirectoryInfo(root);
            while (current is not null)
            {
                var candidate = Path.Combine(current.FullName, "Resources", "Docker", ".env.local");
                if (File.Exists(candidate))
                {
                    return candidate;
                }

                current = current.Parent;
            }
        }

        return null;
    }

    private async Task<string> CreateDedicatedDatabaseAsync()
    {
        var builder = new SqlConnectionStringBuilder(ConnectionString)
        {
            InitialCatalog = "master"
        };

        await using var connection = new SqlConnection(builder.ConnectionString);
        await connection.OpenAsync();

        await using var command = new SqlCommand();
        command.Connection = connection;
        command.CommandText = $"IF DB_ID('{DedicatedDatabaseName}') IS NULL CREATE DATABASE [{DedicatedDatabaseName}]";
        await command.ExecuteNonQueryAsync();

        return new SqlConnectionStringBuilder(ConnectionString)
        {
            InitialCatalog = DedicatedDatabaseName
        }.ConnectionString;
    }

    private async Task EnsureSharedDatabaseSchemaAsync()
    {
        var options = new DbContextOptionsBuilder<OrderProcessingSystemDbContext>()
            .UseSqlServer(ConnectionString)
            .Options;

        await using var context = new OrderProcessingSystemDbContext(options);
        await context.Database.MigrateAsync();
    }
}

[CollectionDefinition("SqlServer")]
public sealed class SqlServerCollection : ICollectionFixture<SqlServerFixture>;
