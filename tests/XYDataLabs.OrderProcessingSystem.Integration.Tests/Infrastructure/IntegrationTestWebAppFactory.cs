using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Infrastructure.DataContext;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.Integration.Tests.Infrastructure
{
    public class IntegrationTestWebAppFactory : WebApplicationFactory<Program>
    {
        public const string TenantHeaderName = "X-Tenant-Code";
        private readonly string _connectionString;
        private readonly string? _dedicatedConnectionString;

        /// <summary>
        /// Creates a factory where all DbContexts use the same connection string.
        /// Existing tests use this constructor — no behavior change.
        /// </summary>
        public IntegrationTestWebAppFactory(string connectionString)
            : this(connectionString, dedicatedConnectionString: null)
        {
        }

        /// <summary>
        /// Creates a factory with routing-aware DbContext registration.
        /// When <paramref name="dedicatedConnectionString"/> is non-null, the
        /// <see cref="OrderProcessingSystemDbContext"/> is registered with the real
        /// per-tenant connection-string routing logic (mirroring StartupHelper),
        /// using <paramref name="connectionString"/> as the shared-pool default and
        /// ITenantProvider.ConnectionString for dedicated tenants.
        /// </summary>
        public IntegrationTestWebAppFactory(string connectionString, string? dedicatedConnectionString)
        {
            _connectionString = connectionString;
            _dedicatedConnectionString = dedicatedConnectionString;
        }

        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            ArgumentNullException.ThrowIfNull(builder);

            builder.UseEnvironment("Development");

            builder.ConfigureServices(services =>
            {
                // ── Remove existing business DbContext ──
                RemoveService<DbContextOptions<OrderProcessingSystemDbContext>>(services);
                RemoveService<OrderProcessingSystemDbContext>(services);

                // ── Remove existing TenantRegistryDbContext (tenant resolution) ──
                RemoveService<DbContextOptions<TenantRegistryDbContext>>(services);
                RemoveService<TenantRegistryDbContext>(services);

                if (_dedicatedConnectionString is null)
                {
                    // Single-DB mode: all queries go to the same Testcontainers DB.
                    // This is the existing behavior — no routing, no breaking change.
                    services.AddDbContext<OrderProcessingSystemDbContext>(options =>
                        options.UseSqlServer(_connectionString));
                }
                else
                {
                    // Routing-aware mode: mirrors StartupHelper.InjectInfrastructureDependencies().
                    // SharedPool tenants → _connectionString (shared DB).
                    // Dedicated tenants → ITenantProvider.ConnectionString (dedicated DB).
                    services.AddDbContext<OrderProcessingSystemDbContext>((sp, options) =>
                    {
                        var tenantProvider = sp.GetService<ITenantProvider>();

                        var resolvedConnectionString = tenantProvider is not null
                            && tenantProvider.HasTenantContext
                            && !tenantProvider.IsSharedPool
                            && !string.IsNullOrWhiteSpace(tenantProvider.ConnectionString)
                                ? tenantProvider.ConnectionString
                                : _connectionString;

                        options.UseSqlServer(resolvedConnectionString);
                    });
                }

                // TenantRegistryDbContext always uses the shared (admin) connection string
                services.AddDbContext<TenantRegistryDbContext>(options =>
                    options.UseSqlServer(_connectionString));

                // Forward IAppDbContext to the EF-registered concrete context
                RemoveService<IAppDbContext>(services);
                services.AddScoped<IAppDbContext>(sp =>
                    sp.GetRequiredService<OrderProcessingSystemDbContext>());
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

        private static void RemoveService<T>(IServiceCollection services)
        {
            var descriptor = services.SingleOrDefault(d => d.ServiceType == typeof(T));
            if (descriptor != null)
                services.Remove(descriptor);
        }
    }
}
