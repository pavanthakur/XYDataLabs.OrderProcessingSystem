using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure
{
    public class IntegrationTestWebAppFactory : WebApplicationFactory<Program>
    {
        public const string TenantHeaderName = "X-Tenant-Code";
        private readonly string _connectionString;

        public IntegrationTestWebAppFactory(string connectionString)
        {
            _connectionString = connectionString;
        }

        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            ArgumentNullException.ThrowIfNull(builder);

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

        public HttpClient CreateTenantClient(string tenantCode)
        {
            var client = CreateClient();
            client.DefaultRequestHeaders.Add(TenantHeaderName, tenantCode);
            return client;
        }

        public async Task ExecuteDbContextAsync(Func<OrderProcessingSystemDbContext, Task> action)
        {
            ArgumentNullException.ThrowIfNull(action);

            using var scope = Services.CreateScope();
            var dbContext = scope.ServiceProvider.GetRequiredService<OrderProcessingSystemDbContext>();
            await action(dbContext);
        }

        public async Task<TResult> ExecuteDbContextAsync<TResult>(Func<OrderProcessingSystemDbContext, Task<TResult>> action)
        {
            ArgumentNullException.ThrowIfNull(action);

            using var scope = Services.CreateScope();
            var dbContext = scope.ServiceProvider.GetRequiredService<OrderProcessingSystemDbContext>();
            return await action(dbContext);
        }

        public async Task<TResult> ExecuteTenantDbContextAsync<TResult>(TenantContext tenantContext, Func<OrderProcessingSystemDbContext, Task<TResult>> action)
        {
            ArgumentNullException.ThrowIfNull(tenantContext);
            ArgumentNullException.ThrowIfNull(action);

            using var scope = Services.CreateScope();
            var httpContextAccessor = scope.ServiceProvider.GetRequiredService<IHttpContextAccessor>();
            var httpContext = new DefaultHttpContext();
            httpContext.Items["TenantContext"] = tenantContext;
            httpContextAccessor.HttpContext = httpContext;

            try
            {
                var dbContext = scope.ServiceProvider.GetRequiredService<OrderProcessingSystemDbContext>();
                return await action(dbContext);
            }
            finally
            {
                httpContextAccessor.HttpContext = null;
            }
        }
    }
}
