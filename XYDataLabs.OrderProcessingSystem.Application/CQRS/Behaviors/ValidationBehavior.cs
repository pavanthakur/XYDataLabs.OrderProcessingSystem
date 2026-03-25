using FluentValidation;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.CQRS.Behaviors;

/// <summary>
/// Pipeline behavior that runs FluentValidation validators before the handler.
/// Short-circuits with Result&lt;T&gt;.Failure if validation fails.
/// Only activates when TResult is a Result&lt;T&gt;.
/// </summary>
public sealed class ValidationBehavior<TRequest, TResult> : IPipelineBehavior<TRequest, TResult>
    where TRequest : notnull
{
    private readonly IEnumerable<IValidator<TRequest>> _validators;

    public ValidationBehavior(IEnumerable<IValidator<TRequest>> validators) => _validators = validators;

    public async Task<TResult> HandleAsync(TRequest request, Func<Task<TResult>> next, CancellationToken cancellationToken = default)
    {
        if (!_validators.Any())
            return await next();

        var context = new ValidationContext<TRequest>(request);
        var results = await Task.WhenAll(_validators.Select(v => v.ValidateAsync(context, cancellationToken)));
        var failures = results.SelectMany(r => r.Errors).Where(f => f is not null).ToList();

        if (failures.Count == 0)
            return await next();

        // If TResult is Result<T>, return a typed failure; otherwise throw
        var resultType = typeof(TResult);
        if (resultType.IsGenericType && resultType.GetGenericTypeDefinition() == typeof(Result<>))
        {
            var innerType = resultType.GetGenericArguments()[0];
            var errorDescription = string.Join("; ", failures.Select(f => f.ErrorMessage));
            var error = Error.Create("Validation", errorDescription);
            var failureMethod = resultType.GetMethod(nameof(Result<object>.Failure))!;
            return (TResult)failureMethod.Invoke(null, [error])!;
        }

        throw new ValidationException(failures);
    }
}
