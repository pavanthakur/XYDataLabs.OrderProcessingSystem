using System.Diagnostics;
using Microsoft.Extensions.Logging;

namespace XYDataLabs.OrderProcessingSystem.Application.CQRS.Behaviors;

/// <summary>
/// Pipeline behavior that logs request type, duration, and success/failure.
/// </summary>
public sealed class LoggingBehavior<TRequest, TResult> : IPipelineBehavior<TRequest, TResult>
    where TRequest : notnull
{
    private readonly ILogger<LoggingBehavior<TRequest, TResult>> _logger;

    public LoggingBehavior(ILogger<LoggingBehavior<TRequest, TResult>> logger) => _logger = logger;

    public async Task<TResult> HandleAsync(TRequest request, Func<Task<TResult>> next, CancellationToken cancellationToken = default)
    {
        var requestName = typeof(TRequest).Name;
        _logger.LogInformation("[CQRS] Handling {Request}", requestName);

        var sw = Stopwatch.StartNew();
        try
        {
            var result = await next();
            sw.Stop();
            _logger.LogInformation("[CQRS] Handled {Request} in {ElapsedMs}ms", requestName, sw.ElapsedMilliseconds);
            return result;
        }
        catch (Exception ex)
        {
            sw.Stop();
            _logger.LogError(ex, "[CQRS] Failed {Request} after {ElapsedMs}ms", requestName, sw.ElapsedMilliseconds);
            throw;
        }
    }
}
