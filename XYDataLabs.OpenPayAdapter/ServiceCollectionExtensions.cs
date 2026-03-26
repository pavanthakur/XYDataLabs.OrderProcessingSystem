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
