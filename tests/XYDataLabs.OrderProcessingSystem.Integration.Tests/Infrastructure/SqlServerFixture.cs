using Microsoft.Data.SqlClient;
using Testcontainers.MsSql;
using Xunit;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure
{
    public class SqlServerFixture : IAsyncLifetime
    {
        private const string DedicatedDatabaseName = "DedicatedTenantDb";
        private const string DefaultSqlServerImage = "mcr.microsoft.com/mssql/server:2022-CU14-ubuntu-22.04";
        private static readonly string SqlServerImage = ResolveSqlServerImage();

        private readonly MsSqlContainer? _container;
        private string _connectionString = string.Empty;

        public SqlServerFixture()
        {
            // Allow bypassing Testcontainers entirely if a host/compose SQL instance is provided via env var
            var existingConnectionString = Environment.GetEnvironmentVariable("ORDERPROCESSING_TEST_CONNECTION_STRING");
            if (string.IsNullOrWhiteSpace(existingConnectionString))
            {
                _container = new MsSqlBuilder()
                    .WithImage(SqlServerImage)
                    .Build();
            }
            else
            {
                _connectionString = existingConnectionString;
                Console.WriteLine("Using existing SQL Server for integration tests instead of Testcontainers.");
            }
        }

        /// <summary>
        /// Connection string to the default (shared pool) database.
        /// </summary>
        public string ConnectionString => _container != null ? _container.GetConnectionString() : _connectionString;

        /// <summary>
        /// Connection string to a second database on the same SQL Server instance,
        /// used to test Dedicated-tier tenant physical DB isolation.
        /// </summary>
        public string DedicatedDbConnectionString { get; private set; } = string.Empty;

        public async Task InitializeAsync()
        {
            if (_container != null)
            {
                try
                {
                    await _container.StartAsync();
                }
                catch (Exception ex)
                {
                    throw new InvalidOperationException(
                        $"Failed to start SQL Server testcontainer using image '{SqlServerImage}'. Local machine: pre-pull the image or set ORDERPROCESSING_SQLSERVER_IMAGE in Resources/Docker/.env.local to a reachable local or mirrored tag. CI/CD: set ORDERPROCESSING_SQLSERVER_IMAGE in the workflow or job environment to the approved registry path. Host SQL fallback is intentionally not supported.",
                        ex);
                }
            }

            DedicatedDbConnectionString = await CreateDedicatedDatabaseAsync();
        }

        public async Task DisposeAsync()
        {
            if (_container != null)
            {
                await _container.DisposeAsync();
            }
        }

        private async Task<string> CreateDedicatedDatabaseAsync()
        {
            var builder = new SqlConnectionStringBuilder(ConnectionString)
            {
                InitialCatalog = "master"
            };

            using var connection = new SqlConnection(builder.ConnectionString);
            await connection.OpenAsync();

            // BannedSymbols.txt bans SqlCommand(string) — use parameterless ctor.
            // Database name is a compile-time constant, not user input.
            using var command = new SqlCommand();
            command.Connection = connection;
            command.CommandText = $"IF DB_ID('{DedicatedDatabaseName}') IS NULL CREATE DATABASE [{DedicatedDatabaseName}]";
            await command.ExecuteNonQueryAsync();

            return new SqlConnectionStringBuilder(ConnectionString)
            {
                InitialCatalog = DedicatedDatabaseName
            }.ConnectionString;
        }

        private static string ResolveSqlServerImage()
        {
            var configuredImage = Environment.GetEnvironmentVariable("ORDERPROCESSING_SQLSERVER_IMAGE");
            if (!string.IsNullOrWhiteSpace(configuredImage))
            {
                return configuredImage;
            }

            var dockerSecretsPath = FindDockerSecretsFilePath();
            if (!string.IsNullOrWhiteSpace(dockerSecretsPath))
            {
                foreach (var line in File.ReadLines(dockerSecretsPath))
                {
                    if (!line.StartsWith("ORDERPROCESSING_SQLSERVER_IMAGE=", StringComparison.Ordinal))
                    {
                        continue;
                    }

                    var value = line.Split('=', 2)[1].Trim();
                    if (!string.IsNullOrWhiteSpace(value))
                    {
                        return value;
                    }
                }
            }

            return DefaultSqlServerImage;
        }

        private static string? FindDockerSecretsFilePath()
        {
            var currentDirectory = new DirectoryInfo(Directory.GetCurrentDirectory());
            var fromCurrentDirectory = TryFindDockerSecretsPath(currentDirectory);
            if (!string.IsNullOrWhiteSpace(fromCurrentDirectory))
            {
                return fromCurrentDirectory;
            }

            var baseDirectory = new DirectoryInfo(AppContext.BaseDirectory);
            return TryFindDockerSecretsPath(baseDirectory);
        }

        private static string? TryFindDockerSecretsPath(DirectoryInfo? startingDirectory)
        {
            var directory = startingDirectory;

            while (directory != null)
            {
                var candidate = Path.Combine(directory.FullName, "Resources", "Docker", ".env.local");
                if (File.Exists(candidate))
                {
                    return candidate;
                }

                directory = directory.Parent;
            }

            return null;
        }
    }

    [CollectionDefinition("SqlServer")]
    public class SqlServerCollection : ICollectionFixture<SqlServerFixture>
    {
    }
}
