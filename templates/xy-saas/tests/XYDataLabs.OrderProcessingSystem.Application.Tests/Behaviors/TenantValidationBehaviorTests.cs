using FluentAssertions;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Application.CQRS.Behaviors;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Application.Tests.Behaviors;

public class TenantValidationBehaviorTests
{
    [Fact]
    public async Task HandleAsync_WithValidTenantContext_CallsNext()
    {
        var tenantProvider = new Mock<ITenantProvider>();
        tenantProvider.SetupGet(x => x.HasTenantContext).Returns(true);
        tenantProvider.SetupGet(x => x.TenantId).Returns(42);
        tenantProvider.SetupGet(x => x.TenantCode).Returns("TenantA");

        var sut = new TenantValidationBehavior<TestQuery, Result<string>>(
            tenantProvider.Object,
            NullLogger<TenantValidationBehavior<TestQuery, Result<string>>>.Instance);

        var nextCalled = false;

        var result = await sut.HandleAsync(new TestQuery(), () =>
        {
            nextCalled = true;
            return Task.FromResult(Result<string>.Success("ok"));
        });

        nextCalled.Should().BeTrue();
        result.IsSuccess.Should().BeTrue();
        result.Value.Should().Be("ok");
    }

    [Fact]
    public async Task HandleAsync_WithoutTenantContext_ThrowsTenantContextRequiredException()
    {
        var tenantProvider = new Mock<ITenantProvider>();
        tenantProvider.SetupGet(x => x.HasTenantContext).Returns(false);

        var sut = new TenantValidationBehavior<TestQuery, Result<string>>(
            tenantProvider.Object,
            NullLogger<TenantValidationBehavior<TestQuery, Result<string>>>.Instance);

        var action = async () => await sut.HandleAsync(new TestQuery(), () => Task.FromResult(Result<string>.Success("ok")));

        var exception = await action.Should().ThrowAsync<TenantContextRequiredException>();
        exception.Which.RequestName.Should().Be(nameof(TestQuery));
    }

    [Fact]
    public async Task HandleAsync_TenantAgnosticRequest_SkipsTenantValidation()
    {
        var tenantProvider = new Mock<ITenantProvider>();
        tenantProvider.SetupGet(x => x.HasTenantContext).Returns(false);

        var sut = new TenantValidationBehavior<BootstrapQuery, Result<string>>(
            tenantProvider.Object,
            NullLogger<TenantValidationBehavior<BootstrapQuery, Result<string>>>.Instance);

        var result = await sut.HandleAsync(new BootstrapQuery(), () => Task.FromResult(Result<string>.Success("bootstrap")));

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().Be("bootstrap");
    }

    private sealed record TestQuery : IQuery<Result<string>>;

    private sealed record BootstrapQuery : IQuery<Result<string>>, ITenantAgnosticRequest;
}