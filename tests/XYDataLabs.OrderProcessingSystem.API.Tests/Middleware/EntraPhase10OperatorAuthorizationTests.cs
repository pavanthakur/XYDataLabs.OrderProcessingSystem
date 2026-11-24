using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Security.Cryptography;
using FluentAssertions;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Middleware;

public sealed class EntraPhase10OperatorAuthorizationTests
{
    [Theory]
    [InlineData("phase10-operator", HttpStatusCode.NoContent)]
    [InlineData("platform-admin", HttpStatusCode.Forbidden)]
    [InlineData("tenant-user", HttpStatusCode.Forbidden)]
    public async Task EntraBearerPipeline_RequiresTheExplicitPhase10OperatorRole(
        string role,
        HttpStatusCode expectedStatus)
    {
        const string authority = "https://login.microsoftonline.com/11111111-1111-1111-1111-111111111111/v2.0";
        using var rsa = RSA.Create(2048);
        var key = new RsaSecurityKey(rsa) { KeyId = "phase10-operator-fixture-key" };
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["IdentityProvider:Enabled"] = "true",
            ["IdentityProvider:Mode"] = "Entra",
            ["IdentityProvider:Authority"] = authority,
            ["IdentityProvider:Audience"] = "fixture-api",
            ["IdentityProvider:RequiredScope"] = "access_as_user",
            ["IdentityProvider:TenantClaimType"] = "extension_4c9b3b4852234de3b572d820e69f6321_applicationTenantCode"
        }).Build();

        using var server = new TestServer(new WebHostBuilder()
            .ConfigureServices(services =>
            {
                services.AddLogging();
                services.AddRouting();
                services.AddConfiguredEntraIdentity(configuration);
                services.AddAuthorization();
                services.Configure<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme, options =>
                {
                    options.Configuration = new OpenIdConnectConfiguration { Issuer = authority };
                    options.Configuration.SigningKeys.Add(key);
                });
            })
            .Configure(app =>
            {
                app.UseRouting();
                app.UseAuthentication();
                app.UseAuthorization();
                app.UseEndpoints(endpoints => endpoints
                    .MapPost("/api/v1/admin/dlq/{quarantineId:guid}/approve", () => Results.NoContent())
                    .RequireAuthorization(new Microsoft.AspNetCore.Authorization.AuthorizeAttribute
                    {
                        Roles = "phase10-operator"
                    }));
            }));

        var token = new JwtSecurityToken(
            issuer: authority,
            audience: "fixture-api",
            claims:
            [
                new Claim("sub", "operator-fixture"),
                new Claim("scp", "access_as_user"),
                new Claim("extension_4c9b3b4852234de3b572d820e69f6321_applicationTenantCode", "TenantA"),
                new Claim("roles", role)
            ],
            notBefore: DateTime.UtcNow.AddMinutes(-1),
            expires: DateTime.UtcNow.AddMinutes(5),
            signingCredentials: new SigningCredentials(key, SecurityAlgorithms.RsaSha256));

        using var client = server.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue(
            "Bearer",
            new JwtSecurityTokenHandler().WriteToken(token));

        using var response = await client.PostAsync(
            $"/api/v1/admin/dlq/{Guid.NewGuid():D}/approve",
            content: null);

        response.StatusCode.Should().Be(expectedStatus);
    }
}
