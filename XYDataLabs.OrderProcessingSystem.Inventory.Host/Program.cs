using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.RateLimiting;
using Asp.Versioning;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Extensions.Options;
using XYDataLabs.OrderProcessingSystem.Application;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;
using XYDataLabs.OrderProcessingSystem.Inventory.API;
using XYDataLabs.OrderProcessingSystem.Inventory.Features.Module;
using XYDataLabs.OrderProcessingSystem.Inventory.Infrastructure.Module;
using XYDataLabs.OrderProcessingSystem.ServiceDefaults;
using XYDataLabs.OrderProcessingSystem.SharedKernel;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Configuration;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

var builder = WebApplication.CreateBuilder(args);

var environmentName = builder.Environment.EnvironmentName switch
{
    "Development" => Constants.Environments.Dev,
    "Staging" => Constants.Environments.Staging,
    "Production" => Constants.Environments.Production,
    _ => Constants.Environments.Dev
};
var isDocker = string.Equals(
    Environment.GetEnvironmentVariable("DOTNET_RUNNING_IN_CONTAINER"),
    "true",
    StringComparison.OrdinalIgnoreCase);

builder.Configuration.LoadSharedSettings(environmentName, isDocker);
builder.AddServiceDefaults("XYDataLabs.OrderProcessingSystem.Inventory.Host");
builder.Services.AddSingleton<IValidateOptions<TenantConfigurationOptions>, TenantConfigurationOptionsValidator>();
builder.Services.AddOptions<TenantConfigurationOptions>()
    .Bind(builder.Configuration.GetSection(TenantConfigurationOptions.SectionName))
    .ValidateOnStart();

builder.Services.AddHttpClient();
var redisConnectionString = builder.Configuration.GetConnectionString("Redis");
if (!string.IsNullOrWhiteSpace(redisConnectionString))
{
    builder.Services.AddStackExchangeRedisCache(options =>
    {
        options.Configuration = redisConnectionString;
        options.InstanceName = "OrderProcessing:";
    });
}
else
{
    builder.Services.AddDistributedMemoryCache();
}

builder.AddPhase10ServiceHostInfrastructure(consumerKind: "Inventory");
builder.InjectApplicationDependencies();
builder.Services.AddCqrs(typeof(InventoryModuleRegistration).Assembly);
builder.Services.AddInventoryModule();
builder.Services.AddInventoryInfrastructure();

builder.Services.AddAuthorization(options =>
{
    options.FallbackPolicy = new AuthorizationPolicyBuilder()
        .RequireAuthenticatedUser()
        .Build();
});

var identityEnabled = builder.Configuration
    .GetSection("IdentityProvider")
    .GetValue("Enabled", false);
if (identityEnabled)
{
    builder.Services
        .AddAuthentication(options =>
        {
            options.DefaultAuthenticateScheme = "KeycloakLocal";
            options.DefaultChallengeScheme = "KeycloakLocal";
        })
        .AddScheme<AuthenticationSchemeOptions, KeycloakIntrospectionAuthenticationHandler>(
            "KeycloakLocal",
            _ => { });
}

builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddPolicy("api-per-tenant", httpContext =>
    {
        var tenantCode = httpContext.Request.Headers[TenantMiddleware.TenantHeaderName].FirstOrDefault() ?? "anonymous";
        return RateLimitPartition.GetFixedWindowLimiter(tenantCode, _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 200,
            Window = TimeSpan.FromMinutes(1),
            QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
            QueueLimit = 0
        });
    });
});

builder.Services
    .AddControllers()
    .AddApplicationPart(AssemblyReference.Assembly);
builder.Services
    .AddApiVersioning(options =>
    {
        options.DefaultApiVersion = new ApiVersion(1, 0);
        options.AssumeDefaultVersionWhenUnspecified = true;
        options.ReportApiVersions = true;
        options.ApiVersionReader = new UrlSegmentApiVersionReader();
    })
    .AddMvc();

var healthChecks = builder.Services.AddHealthChecks();
var connectionString = builder.Configuration.GetConnectionString(Constants.Configuration.OrderProcessingSystemDbConnectionString);
if (!string.IsNullOrWhiteSpace(connectionString))
{
    healthChecks.AddSqlServer(
        connectionString,
        name: "sqlserver",
        tags: ["ready"]);
}

var app = builder.Build();

app.UseExceptionHandler();
if (identityEnabled)
{
    app.UseAuthentication();
}
app.UseAuthorization();
app.UseMiddleware<TenantClaimConsistencyMiddleware>();
app.UseMiddleware<TenantMiddleware>();
app.UseRateLimiter();

app.MapControllers();
app.MapDefaultEndpoints();
app.MapHealthChecks("/health", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("ready", StringComparer.OrdinalIgnoreCase)
}).AllowAnonymous();
app.MapHealthChecks("/health/live", new HealthCheckOptions
{
    Predicate = _ => false
}).AllowAnonymous();
app.MapGet("/", () => Results.Ok(new
{
    service = "XYDataLabs.OrderProcessingSystem.Inventory",
    status = "healthy"
})).AllowAnonymous();

await app.RunAsync();

public partial class Program;

internal sealed class KeycloakIntrospectionAuthenticationHandler : AuthenticationHandler<AuthenticationSchemeOptions>
{
    private const string BearerPrefix = "Bearer ";

    private readonly IHttpClientFactory _httpClientFactory;
    private readonly IConfiguration _configuration;

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

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!Request.Headers.TryGetValue("Authorization", out var authHeader) || Microsoft.Extensions.Primitives.StringValues.IsNullOrEmpty(authHeader))
        {
            return Task.FromResult(AuthenticateResult.NoResult());
        }

        var rawHeader = authHeader.ToString().Trim();
        if (!rawHeader.StartsWith(BearerPrefix, StringComparison.OrdinalIgnoreCase))
        {
            return Task.FromResult(AuthenticateResult.NoResult());
        }

        var token = rawHeader[BearerPrefix.Length..].Trim();
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

    protected override Task HandleChallengeAsync(AuthenticationProperties properties)
    {
        if (HasBearerToken())
        {
            Response.StatusCode = StatusCodes.Status403Forbidden;
            return Response.WriteAsJsonAsync(new
            {
                error = "The supplied bearer token is invalid for this protected resource."
            });
        }

        Response.StatusCode = StatusCodes.Status401Unauthorized;
        Response.Headers.WWWAuthenticate = "Bearer";
        return Task.CompletedTask;
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

            var expectedAudience = _configuration["IdentityProvider:Audience"]?.Trim();
            if (!string.IsNullOrWhiteSpace(expectedAudience)
                && !ContainsAudience(payload.Audience, expectedAudience))
            {
                return AuthenticateResult.Fail("Token audience is invalid.");
            }

            var claims = new List<System.Security.Claims.Claim>
            {
                new(System.Security.Claims.ClaimTypes.NameIdentifier, payload.Subject ?? "keycloak-user"),
                new(System.Security.Claims.ClaimTypes.Name, payload.PreferredUsername ?? payload.Subject ?? "keycloak-user"),
                new("token_type", "keycloak-introspection")
            };

            if (!string.IsNullOrWhiteSpace(payload.PreferredUsername))
            {
                claims.Add(new System.Security.Claims.Claim("preferred_username", payload.PreferredUsername));
            }

            if (!string.IsNullOrWhiteSpace(payload.Email))
            {
                claims.Add(new System.Security.Claims.Claim(System.Security.Claims.ClaimTypes.Email, payload.Email));
            }

            if (!string.IsNullOrWhiteSpace(payload.TenantCode))
            {
                claims.Add(new System.Security.Claims.Claim("tenant_code", payload.TenantCode));
            }

            foreach (var role in payload.RealmAccess?.Roles ?? [])
            {
                if (!string.IsNullOrWhiteSpace(role))
                {
                    claims.Add(new System.Security.Claims.Claim(System.Security.Claims.ClaimTypes.Role, role));
                }
            }

            var identity = new System.Security.Claims.ClaimsIdentity(claims, Scheme.Name);
            var principal = new System.Security.Claims.ClaimsPrincipal(identity);
            var ticket = new AuthenticationTicket(principal, Scheme.Name);
            return AuthenticateResult.Success(ticket);
        }
        catch (Exception ex)
        {
            return AuthenticateResult.Fail(ex);
        }
    }

    private static bool ContainsAudience(JsonElement audienceElement, string expectedAudience)
    {
        return audienceElement.ValueKind switch
        {
            JsonValueKind.String => string.Equals(audienceElement.GetString(), expectedAudience, StringComparison.Ordinal),
            JsonValueKind.Array => audienceElement.EnumerateArray()
                .Where(item => item.ValueKind == JsonValueKind.String)
                .Select(item => item.GetString())
                .Any(audience => string.Equals(audience, expectedAudience, StringComparison.Ordinal)),
            _ => false
        };
    }

    private bool HasBearerToken()
    {
        if (!Request.Headers.TryGetValue("Authorization", out var authHeader)
            || Microsoft.Extensions.Primitives.StringValues.IsNullOrEmpty(authHeader))
        {
            return false;
        }

        return authHeader.ToString().Trim().StartsWith(BearerPrefix, StringComparison.OrdinalIgnoreCase);
    }

    private sealed record KeycloakIntrospectionResponse(
        [property: JsonPropertyName("active")] bool Active,
        [property: JsonPropertyName("sub")] string? Subject,
        [property: JsonPropertyName("preferred_username")] string? PreferredUsername,
        [property: JsonPropertyName("email")] string? Email,
        [property: JsonPropertyName("aud")] JsonElement Audience,
        [property: JsonPropertyName("tenant_code")] string? TenantCode,
        [property: JsonPropertyName("realm_access")] KeycloakRealmAccess? RealmAccess);

    private sealed record KeycloakRealmAccess(
        [property: JsonPropertyName("roles")] string[] Roles);
}
