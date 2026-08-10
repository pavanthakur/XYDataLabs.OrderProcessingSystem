using System.Security.Claims;
using FluentAssertions;
using Microsoft.AspNetCore.Http;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Middleware;

public sealed class TenantClaimConsistencyMiddlewareTests
{
    [Fact]
    public async Task InvokeAsync_WithMatchingAuthenticatedTenant_ContinuesPipeline()
    {
        var nextCalled = false;
        var middleware = new TenantClaimConsistencyMiddleware(_ =>
        {
            nextCalled = true;
            return Task.CompletedTask;
        });
        var context = CreateAuthenticatedContext("TenantA", "TenantA");

        await middleware.InvokeAsync(context);

        nextCalled.Should().BeTrue();
        context.Response.StatusCode.Should().Be(StatusCodes.Status200OK);
    }

    [Theory]
    [InlineData("TenantA", "TenantB")]
    [InlineData("TenantA", null)]
    [InlineData(null, "TenantA")]
    public async Task InvokeAsync_WithInvalidAuthenticatedTenant_ReturnsForbidden(
        string? tenantClaim,
        string? tenantHeader)
    {
        var nextCalled = false;
        var middleware = new TenantClaimConsistencyMiddleware(_ =>
        {
            nextCalled = true;
            return Task.CompletedTask;
        });
        var context = CreateAuthenticatedContext(tenantClaim, tenantHeader);
        context.Response.Body = new MemoryStream();

        await middleware.InvokeAsync(context);

        nextCalled.Should().BeFalse();
        context.Response.StatusCode.Should().Be(StatusCodes.Status403Forbidden);
    }

    [Fact]
    public async Task InvokeAsync_WithAnonymousRequest_LeavesAuthenticationDecisionToEndpoint()
    {
        var nextCalled = false;
        var middleware = new TenantClaimConsistencyMiddleware(_ =>
        {
            nextCalled = true;
            return Task.CompletedTask;
        });
        var context = new DefaultHttpContext();

        await middleware.InvokeAsync(context);

        nextCalled.Should().BeTrue();
    }

    [Fact]
    public async Task InvokeAsync_TenantRegistryBootstrapRequest_BypassesClaimConsistencyCheck()
    {
        var nextCalled = false;
        var middleware = new TenantClaimConsistencyMiddleware(_ =>
        {
            nextCalled = true;
            return Task.CompletedTask;
        });
        var context = CreateAuthenticatedContext("TenantA", null);
        context.Request.Path = "/api/v1/info/tenant-registry";

        await middleware.InvokeAsync(context);

        nextCalled.Should().BeTrue();
        context.Response.StatusCode.Should().Be(StatusCodes.Status200OK);
    }

    private static DefaultHttpContext CreateAuthenticatedContext(
        string? tenantClaim,
        string? tenantHeader)
    {
        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, "local-test-user")
        };
        if (!string.IsNullOrWhiteSpace(tenantClaim))
        {
            claims.Add(new Claim(
                TenantClaimConsistencyMiddleware.TenantClaimType,
                tenantClaim));
        }

        var context = new DefaultHttpContext
        {
            User = new ClaimsPrincipal(new ClaimsIdentity(claims, "test"))
        };
        if (!string.IsNullOrWhiteSpace(tenantHeader))
        {
            context.Request.Headers[TenantMiddleware.TenantHeaderName] = tenantHeader;
        }

        return context;
    }
}
