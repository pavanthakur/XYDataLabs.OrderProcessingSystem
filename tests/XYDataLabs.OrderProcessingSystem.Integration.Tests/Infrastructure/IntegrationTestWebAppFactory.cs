using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure
{
    public class IntegrationTestWebAppFactory : WebApplicationFactory<Program>
    {
        private readonly string _connectionString;

        public IntegrationTestWebAppFactory(string connectionString)
        {
            _connectionString = connectionString;
        }

        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.UseEnvironment("Development");

            builder.ConfigureServices(services =>
            {
                // Remove the existing DbContext registration
                var descriptor = services.SingleOrDefault(
                    d => d.ServiceType == typeof(DbContextOptions<OrderProcessingSystemDbContext>));
                if (descriptor != null)
                    services.Remove(descriptor);

                // Remove any DbContext registration
                var dbContextDescriptor = services.SingleOrDefault(
                    d => d.ServiceType == typeof(OrderProcessingSystemDbContext));
                if (dbContextDescriptor != null)
                    services.Remove(dbContextDescriptor);

                // Add DbContext using the Testcontainers connection string
                services.AddDbContext<OrderProcessingSystemDbContext>(options =>
                    options.UseSqlServer(_connectionString));
            });
        }
    }
}
