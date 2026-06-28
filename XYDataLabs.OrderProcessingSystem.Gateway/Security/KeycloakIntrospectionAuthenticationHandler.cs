using System.Net.Http.Json;
using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;

namespace XYDataLabs.OrderProcessingSystem.Gateway.Security;

internal sealed class KeycloakIntrospectionAuthenticationHandler : AuthenticationHandler<AuthenticationSchemeOptions>
{
    public KeycloakIntrospectionAuthenticationHandler(
        Microsoft.Extensions.Options.IOptionsMonitor<AuthenticationSchemeOptions> options,
        Microsoft.Extensions.Logging.ILoggerFactory logger,
        System.Text.Encodings.Web.UrlEncoder encoder,
        IHttpClientFactory httpClientFactory,
        IConfiguration configuration)
        : base(options, logger, encoder)
    {
        _httpClientFactory = httpClientFactory;
        _configuration = configuration;
    }

    private readonly IHttpClientFactory _httpClientFactory;
    private readonly IConfiguration _configuration;

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!Request.Headers.TryGetValue("Authorization", out var authHeader) || Microsoft.Extensions.Primitives.StringValues.IsNullOrEmpty(authHeader))
        {
            return Task.FromResult(AuthenticateResult.NoResult());
        }

        var rawHeader = authHeader.ToString().Trim();
        const string bearerPrefix = "Bearer ";
        if (!rawHeader.StartsWith(bearerPrefix, StringComparison.OrdinalIgnoreCase))
        {
            return Task.FromResult(AuthenticateResult.NoResult());
        }

        var token = rawHeader[bearerPrefix.Length..].Trim();
        if (string.IsNullOrWhiteSpace(token))
        {
            return Task.FromResult(AuthenticateResult.Fail("Missing bearer token."));
        }

        var identityProviderSection = _configuration.GetSection("IdentityProvider");
        var authority = identityProviderSection.GetValue<string>("Authority")?.Trim().TrimEnd('/');
        var clientId = identityProviderSection.GetValue<string>("ClientId")?.Trim();
        var clientSecret = identityProviderSection.GetValue<string>("ClientSecret")?.Trim();

        if (string.IsNullOrWhiteSpace(authority) ||
            string.IsNullOrWhiteSpace(clientId) ||
            string.IsNullOrWhiteSpace(clientSecret))
        {
            return Task.FromResult(AuthenticateResult.Fail("Identity provider configuration is incomplete."));
        }

        return ValidateTokenAsync(authority, clientId, clientSecret, token);
    }

    private async Task<AuthenticateResult> ValidateTokenAsync(string authority, string clientId, string clientSecret, string token)
    {
        try
        {
            var client = _httpClientFactory.CreateClient(nameof(KeycloakIntrospectionAuthenticationHandler));
            using var request = new HttpRequestMessage(HttpMethod.Post, $"{authority}/protocol/openid-connect/token/introspect")
            {
                Content = new FormUrlEncodedContent(new Dictionary<string, string>
                {
                    ["token"] = token,
                    ["client_id"] = clientId,
                    ["client_secret"] = clientSecret
                })
            };

            using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, Context.RequestAborted);
            if (!response.IsSuccessStatusCode)
            {
                return AuthenticateResult.Fail($"Token introspection failed with HTTP {(int)response.StatusCode}.");
            }

            var payload = await response.Content.ReadFromJsonAsync<KeycloakIntrospectionResponse>(cancellationToken: Context.RequestAborted);
            if (payload is null || !payload.Active)
            {
                return AuthenticateResult.Fail("Token is not active.");
            }

            var claims = new List<Claim>
            {
                new(ClaimTypes.NameIdentifier, payload.Subject ?? "keycloak-user"),
                new(ClaimTypes.Name, payload.PreferredUsername ?? payload.Subject ?? "keycloak-user"),
                new("token_type", "keycloak-introspection")
            };

            if (!string.IsNullOrWhiteSpace(payload.PreferredUsername))
            {
                claims.Add(new Claim("preferred_username", payload.PreferredUsername));
            }

            if (!string.IsNullOrWhiteSpace(payload.Email))
            {
                claims.Add(new Claim(ClaimTypes.Email, payload.Email));
            }

            var identity = new ClaimsIdentity(claims, Scheme.Name);
            var principal = new ClaimsPrincipal(identity);
            var ticket = new AuthenticationTicket(principal, Scheme.Name);
            return AuthenticateResult.Success(ticket);
        }
        catch (Exception ex)
        {
            return AuthenticateResult.Fail(ex);
        }
    }
}
