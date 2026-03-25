using Microsoft.Data.SqlClient;
using Testcontainers.MsSql;
using Xunit;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure
{
    public class SqlServerFixture : IAsyncLifetime
    {
        private const string DedicatedDatabaseName = "DedicatedTenantDb";

        private readonly MsSqlContainer _container = new MsSqlBuilder()
            .WithImage("mcr.microsoft.com/mssql/server:2022-latest")
            .Build();

        /// <summary>
        /// Connection string to the default (shared pool) database.
        /// </summary>
        public string ConnectionString => _container.GetConnectionString();

        /// <summary>
        /// Connection string to a second database on the same SQL Server instance,
        /// used to test Dedicated-tier tenant physical DB isolation.
        /// </summary>
        public string DedicatedDbConnectionString { get; private set; } = string.Empty;

        public async Task InitializeAsync()
        {
            await _container.StartAsync();
            DedicatedDbConnectionString = await CreateDedicatedDatabaseAsync();
        }

        public async Task DisposeAsync()
        {
            await _container.DisposeAsync();
        }

        private async Task<string> CreateDedicatedDatabaseAsync()
        {
            var builder = new SqlConnectionStringBuilder(_container.GetConnectionString())
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

            return new SqlConnectionStringBuilder(_container.GetConnectionString())
            {
                InitialCatalog = DedicatedDatabaseName
            }.ConnectionString;
        }
    }

    [CollectionDefinition("SqlServer")]
    public class SqlServerCollection : ICollectionFixture<SqlServerFixture>
    {
    }
}
