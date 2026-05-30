using XYDataLabs.OpenPayAdapter.Configuration;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Openpay;
using Polly;
using Polly.CircuitBreaker;
using Polly.Retry;
using Serilog;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

namespace XYDataLabs.OpenPayAdapter
{
    public static class ServiceCollectionExtensions
    {
        private static bool LooksLikePrivateKey(string? value) =>
            !string.IsNullOrWhiteSpace(value) && value.StartsWith("sk_", StringComparison.OrdinalIgnoreCase);

        private static bool LooksLikeMerchantId(string? value) =>
            !string.IsNullOrWhiteSpace(value)
            && !LooksLikePrivateKey(value)
            && value.All(ch => char.IsLetterOrDigit(ch))
            && value.Length >= 10;

        public static IServiceCollection AddOpenPayAdapter(
            this IServiceCollection services,
            IConfiguration configuration)
        {
            services.AddSingleton<IValidateOptions<OpenPayConfig>, OpenPayConfigValidator>();
            services.AddOptions<OpenPayConfig>()
                .Bind(configuration.GetSection("OpenPay"))
                .ValidateOnStart();

            // When RedirectUrl is not explicitly configured (e.g. Docker), build it
            // dynamically from ApiSettings:API using the active profile's host and port.
            services.PostConfigure<OpenPayConfig>(config =>
            {
                // The Openpay SDK constructor order is (api_key, merchant_id, production).
                // Some legacy sources stored these values under the opposite names; normalize
                // them once at binding time so runtime behavior stays correct while the source
                // of truth is being cleaned up.
                if (LooksLikePrivateKey(config.MerchantId) && LooksLikeMerchantId(config.PrivateKey))
                {
                    Console.WriteLine("[WARN] OpenPay configuration appears to have MerchantId and PrivateKey reversed. Normalizing values for backward compatibility.");
                    (config.MerchantId, config.PrivateKey) = (config.PrivateKey, config.MerchantId);
                }

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

            // Sync the auto-resolved redirect URL to PaymentGatewayRequestDefaults so that
            // the ValidateOnStart check succeeds when config ships RedirectUrl blank and
            // relies on the same dynamic fallback from ApiSettings.
            services.PostConfigure<PaymentGatewayRequestDefaults>(defaults =>
            {
                if (!string.IsNullOrWhiteSpace(defaults.RedirectUrl)
                    && Uri.TryCreate(defaults.RedirectUrl, UriKind.Absolute, out _))
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
                    defaults.RedirectUrl = $"{scheme}://{host}:{port}/payment/callback";
                }
            });

            // Resilience pipeline for OpenPay SDK calls:
            //   • Retry 3×, exponential backoff + jitter (1s base) on OpenpayException / TimeoutException
            //   • Circuit breaker: open after 5 failures in 30 s; stays open 30 s
            // Note: per-instance state only — distributed CB would require Redis (out of scope).
            services.AddResiliencePipeline("openpay", pipelineBuilder =>
            {
                pipelineBuilder
                    .AddRetry(new RetryStrategyOptions
                    {
                        MaxRetryAttempts = 3,
                        BackoffType = DelayBackoffType.Exponential,
                        UseJitter = true,
                        Delay = TimeSpan.FromSeconds(1),
                        ShouldHandle = new PredicateBuilder()
                            .Handle<OpenpayException>()
                            .Handle<TimeoutException>()
                    })
                    .AddCircuitBreaker(new CircuitBreakerStrategyOptions
                    {
                        FailureRatio = 0.5,
                        MinimumThroughput = 5,
                        SamplingDuration = TimeSpan.FromSeconds(30),
                        BreakDuration = TimeSpan.FromSeconds(30),
                        ShouldHandle = new PredicateBuilder()
                            .Handle<OpenpayException>()
                            .Handle<TimeoutException>()
                    });
            });

            // Register OpenPay as keyed provider — the unkeyed IPaymentProviderGateway
            // factory in Application StartupHelper resolves the correct provider per tenant.
            services.AddHttpClient<IOpenPayAdapterService, OpenPayAdapterService>();
            services.AddKeyedScoped<IPaymentProviderGateway, OpenPayPaymentGateway>(PaymentProviderTypes.OpenPay);
            services.AddKeyedScoped<IPaymentProviderAdapter, OpenPayAdapterService>(PaymentProviderTypes.OpenPay);

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
