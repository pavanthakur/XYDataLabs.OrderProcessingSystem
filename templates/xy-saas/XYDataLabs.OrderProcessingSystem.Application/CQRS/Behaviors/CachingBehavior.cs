using System.Text.Json;
using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Extensions.Logging;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.Application.CQRS.Behaviors;

public sealed class CachingBehavior<TRequest, TResult> : IPipelineBehavior<TRequest, TResult>
    where TRequest : notnull
{
    private static readonly TimeSpan DefaultExpiration = TimeSpan.FromMinutes(5);

    private readonly IDistributedCache _cache;
    private readonly ILogger<CachingBehavior<TRequest, TResult>> _logger;
    private readonly ITenantProvider _tenantProvider;

    public CachingBehavior(IDistributedCache cache, ILogger<CachingBehavior<TRequest, TResult>> logger, ITenantProvider tenantProvider)
    {
        _cache = cache;
        _logger = logger;
        _tenantProvider = tenantProvider;
    }

    public async Task<TResult> HandleAsync(TRequest request, Func<Task<TResult>> next, CancellationToken cancellationToken = default)
    {
        if (request is not ICacheable cacheable)
            return await next();

        // Scope the cache key by tenant to prevent cross-tenant data leakage.
        var cacheKey = _tenantProvider.HasTenantContext
            ? $"tenant:{_tenantProvider.TenantCode}:{cacheable.CacheKey}"
            : cacheable.CacheKey;

        var cached = await _cache.GetStringAsync(cacheKey, cancellationToken);

        if (cached is not null)
        {
            _logger.LogDebug("Cache hit for {CacheKey}", cacheKey);
            return JsonSerializer.Deserialize<TResult>(cached)!;
        }

        _logger.LogDebug("Cache miss for {CacheKey}", cacheKey);
        var result = await next();

        var expiration = cacheable.Expiration ?? DefaultExpiration;
        var options = new DistributedCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = expiration
        };

        await _cache.SetStringAsync(cacheKey, JsonSerializer.Serialize(result), options, cancellationToken);

        return result;
    }
}
