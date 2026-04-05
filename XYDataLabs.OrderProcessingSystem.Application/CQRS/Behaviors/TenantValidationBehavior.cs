using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.Application.CQRS.Behaviors;

/// <summary>
/// Ensures a valid tenant context exists before request handlers execute.
/// </summary>
public sealed class TenantValidationBehavior<TRequest, TResult> : IPipelineBehavior<TRequest, TResult>
    where TRequest : notnull
{
    private readonly ITenantProvider _tenantProvider;
    private readonly ILogger<TenantValidationBehavior<TRequest, TResult>> _logger;

    public TenantValidationBehavior(
        ITenantProvider tenantProvider,
        ILogger<TenantValidationBehavior<TRequest, TResult>> logger)
    {
        _tenantProvider = tenantProvider;
        _logger = logger;
    }

    public Task<TResult> HandleAsync(TRequest request, Func<Task<TResult>> next, CancellationToken cancellationToken = default)
    {
        if (request is ITenantAgnosticRequest)
            return next();

        if (_tenantProvider.HasTenantContext &&
            _tenantProvider.TenantId > 0 &&
            !string.IsNullOrWhiteSpace(_tenantProvider.TenantCode))
        {
            return next();
        }

        var requestName = typeof(TRequest).Name;

        _logger.LogWarning(
            "[CQRS] Rejected {Request} because no valid tenant context was available.",
            requestName);

        throw new TenantContextRequiredException(requestName);
    }
}