using FluentAssertions;
using Microsoft.AspNetCore.Http;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Configuration;

public class HeaderTenantProviderTests
{
    private const string TenantContextItemKey = "TenantContext";

    [Fact]
    public void ResolveTenantContext_ShouldUseScopedAccessor_WhenHttpContextIsMissing()
    {
        var httpContextAccessor = new HttpContextAccessor();
        var tenantContextAccessor = new ScopedTenantContextAccessor
        {
            Current = new TenantContext(42, "tenant-a", "ext-tenant-a", "Tenant A", "Active", null, true)
        };

        var provider = new HeaderTenantProvider(httpContextAccessor, tenantContextAccessor);

        provider.HasTenantContext.Should().BeTrue();
        provider.TenantId.Should().Be(42);
        provider.TenantCode.Should().Be("tenant-a");
        provider.TenantExternalId.Should().Be("ext-tenant-a");
        provider.IsSharedPool.Should().BeTrue();
    }

    [Fact]
    public void ResolveTenantContext_ShouldFallBackToHttpContext_WhenScopedAccessorIsEmpty()
    {
        var httpContext = new DefaultHttpContext();
        httpContext.Items[TenantContextItemKey] = new TenantContext(7, "tenant-b", "ext-tenant-b", "Tenant B", "Active", "Server=db;", false);

        var httpContextAccessor = new HttpContextAccessor { HttpContext = httpContext };
        var provider = new HeaderTenantProvider(httpContextAccessor, new ScopedTenantContextAccessor());

        provider.HasTenantContext.Should().BeTrue();
        provider.TenantId.Should().Be(7);
        provider.TenantCode.Should().Be("tenant-b");
        provider.ConnectionString.Should().Be("Server=db;");
        provider.IsSharedPool.Should().BeFalse();
    }
}