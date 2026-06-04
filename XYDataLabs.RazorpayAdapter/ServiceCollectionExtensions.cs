using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Polly;
using Polly.CircuitBreaker;
using Polly.Retry;
using Razorpay.Api.Errors;
using Serilog;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;
using XYDataLabs.RazorpayAdapter.Configuration;

namespace XYDataLabs.RazorpayAdapter;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddRazorpayAdapter(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        services.AddSingleton<IValidateOptions<RazorpayConfig>, RazorpayConfigValidator>();
        services.AddOptions<RazorpayConfig>()
            .Bind(configuration.GetSection("Razorpay"));
            //.ValidateOnStart();

        // Resilience pipeline for Razorpay SDK calls:
        //   • Retry 3×, exponential backoff + jitter (1s base) on ServerError / TimeoutException
        //   • Circuit breaker: open after 5 failures in 30 s; stays open 30 s
        services.AddResiliencePipeline("razorpay", pipelineBuilder =>
        {
            pipelineBuilder
                .AddRetry(new RetryStrategyOptions
                {
                    MaxRetryAttempts = 3,
                    BackoffType = DelayBackoffType.Exponential,
                    UseJitter = true,
                    Delay = TimeSpan.FromSeconds(1),
                    ShouldHandle = new PredicateBuilder()
                        .Handle<ServerError>()
                        .Handle<TimeoutException>()
                })
                .AddCircuitBreaker(new CircuitBreakerStrategyOptions
                {
                    FailureRatio = 0.5,
                    MinimumThroughput = 5,
                    SamplingDuration = TimeSpan.FromSeconds(30),
                    BreakDuration = TimeSpan.FromSeconds(30),
                    ShouldHandle = new PredicateBuilder()
                        .Handle<ServerError>()
                        .Handle<TimeoutException>()
                });
        });

        services.AddScoped<IRazorpayAdapterService, RazorpayAdapterService>();
        services.AddKeyedScoped<IPaymentProviderGateway, RazorpayPaymentGateway>(PaymentProviderTypes.Razorpay);
        services.AddKeyedScoped<IPaymentProviderAdapter, RazorpayAdapterService>(PaymentProviderTypes.Razorpay);

        // Named HttpClient for Razorpay S2S JSON v2 API calls.
        // Authorization header is set per-request in RazorpayAdapterService (tenant-scoped credentials).
        services.AddHttpClient("razorpay-s2s", client =>
        {
            client.Timeout = TimeSpan.FromSeconds(30);
        });

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
