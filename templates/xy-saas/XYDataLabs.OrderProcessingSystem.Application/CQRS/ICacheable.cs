namespace XYDataLabs.OrderProcessingSystem.Application.CQRS;

public interface ICacheable
{
    string CacheKey { get; }
    TimeSpan? Expiration => null;
}
