using System.Net;
using System.Text.Encodings.Web;
using FluentAssertions;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using XYDataLabs.OrderProcessingSystem.ServiceDefaults;
using Xunit;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Configuration;

public sealed class ServiceReadinessAuthorizationTests
{
    [Fact]
    public async Task AnonymousReadiness_IsAvailable_WithoutWeakeningApplicationAuthorization()
    {
        // Other startup fixtures temporarily change the process content root.
        // This independent in-memory host must not inherit a deleted temp path.
        var builder=WebApplication.CreateBuilder(new WebApplicationOptions { ContentRootPath=AppContext.BaseDirectory });
        builder.WebHost.UseTestServer();
        builder.Services.AddHealthChecks();
        builder.Services.AddAuthentication("fixture").AddScheme<AuthenticationSchemeOptions,AnonymousHandler>("fixture",_=>{});
        builder.Services.AddAuthorization(options=>options.FallbackPolicy=new Microsoft.AspNetCore.Authorization.AuthorizationPolicyBuilder().RequireAuthenticatedUser().Build());
        await using var app=builder.Build();
        app.UseAuthentication(); app.UseAuthorization();
        app.MapDefaultEndpoints();
        app.MapGet("/private",()=>"private");
        await app.StartAsync();
        var client=app.GetTestClient();
        (await client.GetAsync("/health/ready")).StatusCode.Should().Be(HttpStatusCode.OK);
        (await client.GetAsync("/private")).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    private sealed class AnonymousHandler(IOptionsMonitor<AuthenticationSchemeOptions> options,ILoggerFactory logger,UrlEncoder encoder)
        : AuthenticationHandler<AuthenticationSchemeOptions>(options,logger,encoder)
    {
        protected override Task<AuthenticateResult> HandleAuthenticateAsync()=>Task.FromResult(AuthenticateResult.NoResult());
    }
}
