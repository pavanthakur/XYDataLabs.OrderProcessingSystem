using System.Text.Json;
using FluentAssertions;
using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Extensions.Logging;
using Moq;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.CQRS.Behaviors;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Tests.Behaviors;

public class CachingBehaviorTests
{
    private readonly Mock<IDistributedCache> _mockCache = new();
    private readonly Mock<ILogger<CachingBehavior<TestCacheableQuery, Result<string>>>> _mockLogger = new();
    private readonly Mock<ITenantProvider> _mockTenantProvider = new();

    private CachingBehavior<TestCacheableQuery, Result<string>> CreateSut()
    {
        _mockTenantProvider.Setup(p => p.HasTenantContext).Returns(false);
        return new(_mockCache.Object, _mockLogger.Object, _mockTenantProvider.Object);
    }

    [Fact]
    public async Task HandleAsync_CacheMiss_CallsNextAndStoresResult()
    {
        // Arrange
        var sut = CreateSut();
        var query = new TestCacheableQuery("test-key");
        var expected = Result<string>.Success("hello");

        _mockCache
            .Setup(c => c.GetAsync(query.CacheKey, It.IsAny<CancellationToken>()))
            .ReturnsAsync((byte[]?)null);

        // Act
        var result = await sut.HandleAsync(query, () => Task.FromResult(expected));

        // Assert
        result.Should().BeEquivalentTo(expected);
        _mockCache.Verify(c => c.SetAsync(
            query.CacheKey,
            It.IsAny<byte[]>(),
            It.IsAny<DistributedCacheEntryOptions>(),
            It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task HandleAsync_CacheHit_ReturnsCachedAndSkipsNext()
    {
        // Arrange
        var sut = CreateSut();
        var query = new TestCacheableQuery("test-key");
        var cached = Result<string>.Success("cached-value");
        var serialized = JsonSerializer.Serialize(cached);
        var bytes = System.Text.Encoding.UTF8.GetBytes(serialized);

        _mockCache
            .Setup(c => c.GetAsync(query.CacheKey, It.IsAny<CancellationToken>()))
            .ReturnsAsync(bytes);

        var nextCalled = false;

        // Act
        var result = await sut.HandleAsync(query, () =>
        {
            nextCalled = true;
            return Task.FromResult(Result<string>.Success("should-not-reach"));
        });

        // Assert
        result.Value.Should().Be("cached-value");
        nextCalled.Should().BeFalse();
    }

    [Fact]
    public async Task HandleAsync_NonCacheableRequest_PassesThrough()
    {
        // Arrange
        var cache = new Mock<IDistributedCache>();
        var logger = new Mock<ILogger<CachingBehavior<NonCacheableQuery, Result<string>>>>();
        var tenantProvider = new Mock<ITenantProvider>();
        tenantProvider.Setup(p => p.HasTenantContext).Returns(false);
        var sut = new CachingBehavior<NonCacheableQuery, Result<string>>(cache.Object, logger.Object, tenantProvider.Object);
        var query = new NonCacheableQuery();
        var expected = Result<string>.Success("direct");

        // Act
        var result = await sut.HandleAsync(query, () => Task.FromResult(expected));

        // Assert
        result.Should().BeEquivalentTo(expected);
        cache.Verify(c => c.GetAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task HandleAsync_WithTenantContext_UsesTenantScopedCacheKey()
    {
        // Arrange
        _mockTenantProvider.Setup(p => p.HasTenantContext).Returns(true);
        _mockTenantProvider.Setup(p => p.TenantCode).Returns("TenantA");
        var sut = new CachingBehavior<TestCacheableQuery, Result<string>>(
            _mockCache.Object, _mockLogger.Object, _mockTenantProvider.Object);

        var query = new TestCacheableQuery("customers:all");
        var expected = Result<string>.Success("tenant-a-data");
        var expectedKey = "tenant:TenantA:customers:all";

        _mockCache
            .Setup(c => c.GetAsync(expectedKey, It.IsAny<CancellationToken>()))
            .ReturnsAsync((byte[]?)null);

        // Act
        var result = await sut.HandleAsync(query, () => Task.FromResult(expected));

        // Assert
        result.Should().BeEquivalentTo(expected);
        _mockCache.Verify(c => c.SetAsync(
            expectedKey,
            It.IsAny<byte[]>(),
            It.IsAny<DistributedCacheEntryOptions>(),
            It.IsAny<CancellationToken>()), Times.Once);
    }

    // Test doubles
    public sealed record TestCacheableQuery(string Key) : IQuery<Result<string>>, ICacheable
    {
        public string CacheKey => Key;
        public TimeSpan? Expiration => TimeSpan.FromMinutes(1);
    }

    public sealed record NonCacheableQuery : IQuery<Result<string>>;
}
