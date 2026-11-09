using System.Security.Claims;
using FluentAssertions;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Middleware;

public sealed class EntraTenantClaimsTests
{
    [Theory]
    [InlineData("tenant-user", "extn.applicationTenantCode", "CustomTenant", "access_as_user", true)]
    [InlineData("tenant-user", "extn.applicationTenantCode", "", "access_as_user", false)]
    [InlineData("platform-admin", "extn.applicationTenantCode", "", "access_as_user", true)]
    [InlineData("platform-admin", "extn.applicationTenantCode", "", "", false)]
    [InlineData("tenant-admin", "extn.applicationTenantCode", "", "access_as_user", false)]
    public void ValidatedEntraClaims_AreNormalizedWithoutUsingDirectoryTenant(string role, string type, string tenant, string scope, bool accepted)
    {
        var identity = new ClaimsIdentity(new[] { new Claim("roles", role), new Claim("tid", "TenantA"),
            new Claim("scp", scope), new Claim(type, tenant), new Claim("tenant_code", "ForgedUnmappedTenant") }, "validated-jwt", "preferred_username", "roles");
        var user = new ClaimsPrincipal(identity);
        EntraIdentityExtensions.NormalizeValidatedPrincipal(user, type, "access_as_user").Should().Be(accepted);
        if (accepted || !string.IsNullOrEmpty(scope)) TenantAccessPolicy.AssignedTenant(user).Should().Be(string.IsNullOrEmpty(tenant) ? null : tenant);
        if (accepted) TenantAccessPolicy.CanAccess(user, "CustomTenant").Should().BeTrue();
    }

    [Theory]
    [InlineData("http://localhost:8081", "extn.applicationTenantCode")]
    [InlineData("https://login.microsoftonline.com/common/v2.0", "extn.applicationTenantCode")]
    [InlineData("https://login.microsoftonline.com/11111111-1111-1111-1111-111111111111/v2.0", "tid")]
    public void InvalidEntraConfiguration_FailsClosed(string authority, string tenantClaim)
    {
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["IdentityProvider:Enabled"]="true", ["IdentityProvider:Mode"]="Entra", ["IdentityProvider:Authority"]=authority,
            ["IdentityProvider:Audience"]="test-api", ["IdentityProvider:RequiredScope"]="access_as_user", ["IdentityProvider:TenantClaimType"]=tenantClaim
        }).Build();
        var act = () => new ServiceCollection().AddConfiguredEntraIdentity(configuration);
        act.Should().Throw<InvalidOperationException>();
    }
}
