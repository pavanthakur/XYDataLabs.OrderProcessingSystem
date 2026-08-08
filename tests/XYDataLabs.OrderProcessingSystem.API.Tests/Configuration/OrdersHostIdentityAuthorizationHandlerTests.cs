using System.Net;
using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Text.Json;
using FluentAssertions;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Moq;
using XYDataLabs.OrderProcessingSystem.Orders.Host;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Configuration;

public sealed class OrdersHostIdentityAuthorizationHandlerTests
{
    private const string SchemeName = "KeycloakLocal";
    private const string Authority = "https://identity.local/realms/order-processing";
    private const string ClientId = "xy-order-processing";
    private const string ClientSecret = "local-secret";
    private const string ExpectedAudience = "xy-order-processing";

    [Fact]
    public async Task MissingBearerToken_ShouldReturnNoResult_AndChallengeWithUnauthorized()
    {
        using var httpClient = CreateThrowingClient(
            "Introspection should not be called when the bearer token is missing.");
        var httpContext = CreateHttpContext();
        var handler = CreateHandler(httpClient, httpContext);

        var result = await handler.AuthenticateAsync();
        await handler.ChallengeAsync(new AuthenticationProperties());

        result.None.Should().BeTrue();
        httpContext.Response.StatusCode.Should().Be(StatusCodes.Status401Unauthorized);
        httpContext.Response.Headers.WWWAuthenticate.ToString().Should().Be("Bearer");
    }

    [Fact]
    public async Task InvalidAudienceBearerToken_ShouldFailAuthentication_AndChallengeWithForbidden()
    {
        using var httpClient = CreateIntrospectionClient(new
        {
            active = true,
            sub = "tenant-user-1",
            preferred_username = "tenant-user",
            tenant_code = "TenantA",
            aud = "wrong-audience",
            realm_access = new { roles = new[] { "tenant-user" } }
        });
        var httpContext = CreateHttpContext("Bearer wrong-audience-token");
        var handler = CreateHandler(httpClient, httpContext);

        var result = await handler.AuthenticateAsync();
        await handler.ChallengeAsync(new AuthenticationProperties());

        result.Succeeded.Should().BeFalse();
        result.Failure.Should().NotBeNull();
        result.Failure!.Message.Should().Contain("audience");
        httpContext.Response.StatusCode.Should().Be(StatusCodes.Status403Forbidden);
        await AssertChallengePayloadAsync(httpContext.Response, "The supplied bearer token is invalid for this protected resource.");
    }

    [Fact]
    public async Task InactiveBearerToken_ShouldFailAuthentication_AndChallengeWithForbidden()
    {
        using var httpClient = CreateIntrospectionClient(new
        {
            active = false
        });
        var httpContext = CreateHttpContext("Bearer expired-token");
        var handler = CreateHandler(httpClient, httpContext);

        var result = await handler.AuthenticateAsync();
        await handler.ChallengeAsync(new AuthenticationProperties());

        result.Succeeded.Should().BeFalse();
        result.Failure.Should().NotBeNull();
        result.Failure!.Message.Should().Contain("not active");
        httpContext.Response.StatusCode.Should().Be(StatusCodes.Status403Forbidden);
        await AssertChallengePayloadAsync(httpContext.Response, "The supplied bearer token is invalid for this protected resource.");
    }

    [Fact]
    public async Task ValidBearerToken_ShouldAuthenticateWithTenantAndRoleClaims()
    {
        using var httpClient = CreateIntrospectionClient(new
        {
            active = true,
            sub = "tenant-admin-1",
            preferred_username = "tenant-admin",
            email = "tenant-admin@example.test",
            tenant_code = "TenantA",
            aud = new[] { ExpectedAudience },
            realm_access = new { roles = new[] { "phase10-operator", "tenant-user" } }
        });
        var httpContext = CreateHttpContext("Bearer valid-token");
        var handler = CreateHandler(httpClient, httpContext);

        var result = await handler.AuthenticateAsync();

        result.Succeeded.Should().BeTrue();
        result.Principal.Should().NotBeNull();
        var principal = result.Principal!;
        principal.FindFirstValue("tenant_code").Should().Be("TenantA");
        principal.IsInRole("phase10-operator").Should().BeTrue();
        principal.FindFirstValue(ClaimTypes.Email).Should().Be("tenant-admin@example.test");
    }

    private static KeycloakIntrospectionAuthenticationHandler CreateHandler(HttpClient httpClient, DefaultHttpContext httpContext)
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["IdentityProvider:Authority"] = Authority,
                ["IdentityProvider:ClientId"] = ClientId,
                ["IdentityProvider:ClientSecret"] = ClientSecret,
                ["IdentityProvider:Audience"] = ExpectedAudience
            })
            .Build();

        var httpClientFactory = new Mock<IHttpClientFactory>();
        httpClientFactory
            .Setup(factory => factory.CreateClient(It.IsAny<string>()))
            .Returns(httpClient);

        var optionsMonitor = new Mock<IOptionsMonitor<AuthenticationSchemeOptions>>();
        optionsMonitor
            .SetupGet(monitor => monitor.CurrentValue)
            .Returns(new AuthenticationSchemeOptions());
        optionsMonitor
            .Setup(monitor => monitor.Get(It.IsAny<string>()))
            .Returns(new AuthenticationSchemeOptions());

        var handler = new KeycloakIntrospectionAuthenticationHandler(
            optionsMonitor.Object,
            NullLoggerFactory.Instance,
            UrlEncoder.Default,
            httpClientFactory.Object,
            configuration);

        var scheme = new AuthenticationScheme(
            SchemeName,
            SchemeName,
            typeof(KeycloakIntrospectionAuthenticationHandler));
        handler.InitializeAsync(scheme, httpContext).GetAwaiter().GetResult();
        return handler;
    }

    private static HttpClient CreateIntrospectionClient(object payload)
    {
        var json = JsonSerializer.Serialize(payload);
        var messageHandler = new StubHttpMessageHandler(_ =>
            new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(json)
            });
        return new HttpClient(messageHandler, disposeHandler: true);
    }

    private static HttpClient CreateThrowingClient(string message)
    {
        var messageHandler = new StubHttpMessageHandler(_ =>
            throw new InvalidOperationException(message));
        return new HttpClient(messageHandler, disposeHandler: true);
    }

    private static DefaultHttpContext CreateHttpContext(string? authorizationHeader = null)
    {
        var context = new DefaultHttpContext();
        context.Response.Body = new MemoryStream();
        if (!string.IsNullOrWhiteSpace(authorizationHeader))
        {
            context.Request.Headers.Authorization = authorizationHeader;
        }

        return context;
    }

    private static async Task AssertChallengePayloadAsync(HttpResponse response, string expectedError)
    {
        response.Body.Position = 0;
        var payload = await JsonSerializer.DeserializeAsync<JsonElement>(response.Body);
        payload.GetProperty("error").GetString().Should().Be(expectedError);
    }

    private sealed class StubHttpMessageHandler(Func<HttpRequestMessage, HttpResponseMessage> responder)
        : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(responder(request));
        }
    }
}
