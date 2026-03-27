using XYDataLabs.OpenPayAdapter.Configuration;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Openpay;
using Polly;
using Polly.CircuitBreaker;
using Polly.Retry;
using Serilog;

namespace XYDataLabs.OpenPayAdapter
{
    public static class ServiceCollectionExtensions
    {
        public static IServiceCollection AddOpenPayAdapter(
            this IServiceCollection services,
            IConfiguration configuration)
        {
            services.AddSingleton<IValidateOptions<OpenPayConfig>, OpenPayConfigValidator>();
            services.AddOptions<OpenPayConfig>()
                .Bind(configuration.GetSection("OpenPay"))
                .ValidateOnStart();

            // When RedirectUrl is not explicitly configured (e.g. Docker), build it
            // dynamically from ApiSettings:UI using the active profile's host and port.
            services.PostConfigure<OpenPayConfig>(config =>
            {
                if (!string.IsNullOrWhiteSpace(config.RedirectUrl)
                    && Uri.TryCreate(config.RedirectUrl, UriKind.Absolute, out _))
                {
                    return; // Already set via user-secrets, Key Vault, or env var
                }

                var useHttps = string.Equals(
                    configuration["USE_HTTPS"], "true", StringComparison.OrdinalIgnoreCase);
                var profile = useHttps ? "https" : "http";
                var host = configuration[$"ApiSettings:UI:{profile}:Host"] ?? "localhost";
                var portStr = configuration[$"ApiSettings:UI:{profile}:Port"];
                var scheme = useHttps ? "https" : "http";

                if (int.TryParse(portStr, out var port) && port > 0)
                {
                    config.RedirectUrl = $"{scheme}://{host}:{port}/payment/callback";
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
