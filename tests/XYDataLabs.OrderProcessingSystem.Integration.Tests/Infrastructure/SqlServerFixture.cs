using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using System.Text.RegularExpressions;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using Xunit;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure;

public sealed class SqlServerFixture : IAsyncLifetime
{
    private readonly string _connectionString;
    private readonly string _sharedDatabaseName;
    private readonly string _dedicatedDatabaseName;
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
        if (builder.DataSource.Contains(".database.windows.net", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("Integration tests must never target Azure SQL.");
        }

        _sharedDatabaseName = builder.InitialCatalog;
        if (!Regex.IsMatch(_sharedDatabaseName, "^OrderProcessingSystem_Integration_[0-9a-f]{32}$", RegexOptions.CultureInvariant))
        {
            throw new InvalidOperationException("Integration tests require a unique run-owned OrderProcessingSystem_Integration_<guid> database.");
        }

        _dedicatedDatabaseName = $"{_sharedDatabaseName}_TenantC";
        _connectionString = builder.ConnectionString;
    }

    public string ConnectionString => _connectionString;

    public string DedicatedDbConnectionString => _dedicatedConnectionString;

    public async Task InitializeAsync()
    {
        await AssertRunOwnedDatabasePairExistsAsync();
        await EnsureSharedDatabaseSchemaAsync();
        _dedicatedConnectionString = new SqlConnectionStringBuilder(ConnectionString)
        {
            InitialCatalog = _dedicatedDatabaseName
        }.ConnectionString;
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

        var password = sqlPassword.Split('=', 2)[1].Trim().Trim('"', '\'');
        if (string.IsNullOrWhiteSpace(password))
        {
            return null;
        }

        var hostPortSetting = Environment.GetEnvironmentVariable("LOCAL_SQL_HOST_PORT")
            ?? File.ReadLines(envFilePath)
                .Concat(File.Exists(envFilePath + ".example")
                    ? File.ReadLines(envFilePath + ".example")
                    : Array.Empty<string>())
                .FirstOrDefault(line => line.StartsWith("LOCAL_SQL_HOST_PORT=", StringComparison.OrdinalIgnoreCase))?
                .Split('=', 2)[1].Trim().Trim('"', '\'')
            ?? "14330";
        if (!int.TryParse(hostPortSetting, System.Globalization.NumberStyles.None,
            System.Globalization.CultureInfo.InvariantCulture, out var hostPort) || hostPort is < 1 or > 65535)
        {
            throw new InvalidOperationException("LOCAL_SQL_HOST_PORT must be an integer from 1 to 65535.");
        }

        var connection = new SqlConnectionStringBuilder
        {
            DataSource = $"tcp:127.0.0.1,{hostPort}",
            InitialCatalog = $"OrderProcessingSystem_Integration_{Guid.NewGuid():N}",
            UserID = "sa",
            Password = password,
            TrustServerCertificate = true,
            Encrypt = false,
            MultipleActiveResultSets = false
        };
        return connection.ConnectionString;
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

    private async Task AssertRunOwnedDatabasePairExistsAsync()
    {
        var builder = new SqlConnectionStringBuilder(ConnectionString)
        {
            InitialCatalog = "master"
        };

        await using var connection = new SqlConnection(builder.ConnectionString);
        await connection.OpenAsync();

        await using var command = new SqlCommand();
        command.Connection = connection;
        command.CommandText = "SELECT CASE WHEN DB_ID(@shared) IS NOT NULL AND DB_ID(@dedicated) IS NOT NULL THEN 1 ELSE 0 END;";
        command.Parameters.AddWithValue("@shared", _sharedDatabaseName);
        command.Parameters.AddWithValue("@dedicated", _dedicatedDatabaseName);
        if (Convert.ToInt32(await command.ExecuteScalarAsync(), System.Globalization.CultureInfo.InvariantCulture) != 1)
        {
            throw new InvalidOperationException("The run-owned shared/dedicated integration databases must be created by the guarded runner before tests start.");
        }
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
