namespace XYDataLabs.OrderProcessingSystem.Application.CQRS;

/// <summary>
/// Cross-cutting pipeline behavior that wraps handler execution.
/// Behaviors are chained in registration order: outermost runs first.
/// </summary>
public interface IPipelineBehavior<in TRequest, TResult>
{
    Task<TResult> HandleAsync(TRequest request, Func<Task<TResult>> next, CancellationToken cancellationToken = default);
}
