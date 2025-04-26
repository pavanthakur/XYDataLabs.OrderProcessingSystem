using XYDataLabs.OpenPayAdapter.Configuration;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Serilog;

namespace XYDataLabs.OpenPayAdapter
{
    public static class ServiceCollectionExtensions
    {
        public static IServiceCollection AddOpenPayAdapter(
            this IServiceCollection services,
            IConfiguration configuration)
        {
            services.Configure<OpenPayConfig>(
                configuration.GetSection("OpenPay")
            );

            // Register HttpClient
            services.AddHttpClient<IOpenPayAdapterService, OpenPayAdapterService>();

            // Register Serilog if not already registered
            if (!services.Any(s => s.ServiceType == typeof(ILogger)))
            {
                var logger = new LoggerConfiguration()
                    .MinimumLevel.Debug()
                    .WriteTo.Console(
                        outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj}{NewLine}{Exception}")
                    .CreateLogger();

                services.AddSingleton<ILogger>(logger);
            }

            return services;
        }
    }
}
