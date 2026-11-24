using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Security.Cryptography;
using FluentAssertions;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Middleware;

public sealed class EntraBearerValidationTests
{
    [Theory]
    [InlineData("valid", HttpStatusCode.OK)]
    [InlineData("wrong-audience", HttpStatusCode.Unauthorized)]
    [InlineData("wrong-issuer", HttpStatusCode.Unauthorized)]
    [InlineData("wrong-signature", HttpStatusCode.Unauthorized)]
    [InlineData("expired", HttpStatusCode.Unauthorized)]
    [InlineData("missing-scope", HttpStatusCode.Unauthorized)]
    [InlineData("missing-tenant", HttpStatusCode.Unauthorized)]
    [InlineData("admin-without-tenant", HttpStatusCode.OK)]
    public async Task BearerPipeline_ValidatesTokensBeforeApplyingTenantPolicy(string scenario, HttpStatusCode expected)
    {
        const string authority = "https://login.microsoftonline.com/11111111-1111-1111-1111-111111111111/v2.0";
        using var rsa = RSA.Create(2048);
        using var otherRsa = RSA.Create(2048);
        var key = new RsaSecurityKey(rsa) { KeyId = "fixture-key" };
        var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?> {
            ["IdentityProvider:Enabled"]="true", ["IdentityProvider:Mode"]="Entra", ["IdentityProvider:Authority"]=authority,
            ["IdentityProvider:Audience"]="fixture-api", ["IdentityProvider:RequiredScope"]="access_as_user", ["IdentityProvider:TenantClaimType"]="extn.applicationTenantCode"
        }).Build();
        using var server = new TestServer(new WebHostBuilder().ConfigureServices(services => {
            services.AddLogging();
            services.AddConfiguredEntraIdentity(config);
            services.Configure<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme, options => {
                // Static discovery and a fixture key: these tests make no calls to Azure.
                options.Configuration = new OpenIdConnectConfiguration { Issuer = authority };
                options.Configuration.SigningKeys.Add(key);
            });
        }).Configure(app => {
            app.UseAuthentication();
            app.Run(async context => {
                context.Response.StatusCode = context.User.Identity?.IsAuthenticated == true
                    && TenantAccessPolicy.CanAccess(context.User, "CustomTenant") ? 200 : 401;
                await Task.CompletedTask;
            });
        }));
        var claims = new List<Claim> { new("sub", "fixture-user"), new("tid", "not-the-application-tenant") };
        if (scenario != "missing-scope") claims.Add(new("scp", "access_as_user"));
        if (scenario is not "missing-tenant" and not "admin-without-tenant") claims.Add(new("extn.applicationTenantCode", "CustomTenant"));
        if (scenario == "admin-without-tenant") claims.Add(new("roles", "platform-admin"));
        var token = new JwtSecurityToken(issuer: scenario == "wrong-issuer" ? "https://wrong.example.test" : authority,
            audience: scenario == "wrong-audience" ? "different-api" : "fixture-api", claims: claims,
            notBefore: DateTime.UtcNow.AddHours(-2), expires: scenario == "expired" ? DateTime.UtcNow.AddHours(-1) : DateTime.UtcNow.AddMinutes(5),
            signingCredentials: new SigningCredentials(scenario == "wrong-signature" ? new RsaSecurityKey(otherRsa) {KeyId="fixture-key"} : key, SecurityAlgorithms.RsaSha256));
        using var client = server.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", new JwtSecurityTokenHandler().WriteToken(token));
        using var response = await client.GetAsync("/");
        response.StatusCode.Should().Be(expected);
    }
}
