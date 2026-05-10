using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Serilog;
using XYDataLabs.OrderProcessingSystem.PaymentGateway.Configuration;

namespace XYDataLabs.OrderProcessingSystem.PaymentGateway
{
    public static class ServiceCollectionExtensions
    {
        public static IServiceCollection AddPaymentGateway(
            this IServiceCollection services,
            IConfiguration configuration)
        {
            services.AddSingleton<IValidateOptions<PaymentGatewayOptions>, PaymentGatewayOptionsValidator>();
            services.AddOptions<PaymentGatewayOptions>()
                .Bind(configuration.GetSection("PaymentGateway"))
                .ValidateOnStart();

            services.PostConfigure<PaymentGatewayOptions>(config =>
            {
                if (!string.IsNullOrWhiteSpace(config.RedirectUrl)
                    && Uri.TryCreate(config.RedirectUrl, UriKind.Absolute, out _))
                {
                    return; // Already set via user-secrets, Key Vault, or env var
                }

                var useHttps = string.Equals(
                    configuration["USE_HTTPS"], "true", StringComparison.OrdinalIgnoreCase);
                var profile = useHttps ? "https" : "http";
                var host = configuration[$"ApiSettings:API:{profile}:Host"] ?? "localhost";
                var portStr = configuration[$"ApiSettings:API:{profile}:Port"];
                var scheme = useHttps ? "https" : "http";

                if (int.TryParse(portStr, out var port) && port > 0)
                {
                    config.RedirectUrl = $"{scheme}://{host}:{port}/payment/callback";
                }
            });

            services.AddSingleton<IPaymentGatewayService, DefaultPaymentGatewayService>();

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
