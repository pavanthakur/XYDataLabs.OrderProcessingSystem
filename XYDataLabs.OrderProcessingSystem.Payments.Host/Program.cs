using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.RateLimiting;
using Asp.Versioning;
using Microsoft.ApplicationInsights;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Extensions.Options;
using XYDataLabs.OpenPayAdapter;
using XYDataLabs.OrderProcessingSystem.Application;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Application.CQRS;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Messaging;
using XYDataLabs.OrderProcessingSystem.Infrastructure.Payments;
using XYDataLabs.OrderProcessingSystem.Orders.Features.Module;
using XYDataLabs.OrderProcessingSystem.Payments.API;
using XYDataLabs.OrderProcessingSystem.Payments.Features;
using XYDataLabs.OrderProcessingSystem.Payments.Features.Module;
using XYDataLabs.OrderProcessingSystem.ServiceDefaults;
using XYDataLabs.OrderProcessingSystem.SharedKernel;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Configuration;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Observability;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;
using XYDataLabs.RazorpayAdapter;

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
builder.AddServiceDefaults("XYDataLabs.OrderProcessingSystem.Payments.Host");
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

builder.AddPhase10ServiceHostInfrastructure(enablePaymentReconciliation: true);
builder.InjectApplicationDependencies();
builder.Services.AddCqrs(typeof(PaymentsModuleRegistration).Assembly);
builder.Services.AddPaymentsModule();
builder.Services.AddOrdersModule();
builder.Services.AddScoped<IPaymentProviderGateway>(serviceProvider =>
{
    var resolver = serviceProvider.GetRequiredService<ITenantPaymentProviderResolver>();
    var providerType = resolver.ResolveCurrentTenantProvider().ProviderType;
    return serviceProvider.GetRequiredKeyedService<IPaymentProviderGateway>(providerType);
});
builder.Services.AddOpenPayAdapter(builder.Configuration);
builder.Services.AddRazorpayAdapter(builder.Configuration);
if (builder.Configuration.GetValue("PaymentProviders:UseDeterministicAdapters", false))
{
    builder.Services.AddKeyedSingleton<IPaymentProviderGateway>(
        PaymentProviderTypes.OpenPay,
        (_, _) => new DeterministicPaymentProviderGateway(PaymentProviderTypes.OpenPay));
    builder.Services.AddKeyedSingleton<IPaymentProviderGateway>(
        PaymentProviderTypes.Razorpay,
        (_, _) => new DeterministicPaymentProviderGateway(PaymentProviderTypes.Razorpay));
}
builder.Services.AddScoped<IPaymentTelemetryTracker>(serviceProvider =>
    new ApplicationInsightsPaymentTelemetryTracker(serviceProvider.GetService<TelemetryClient>()));
builder.Services.AddOptions<PaymentGatewayRequestDefaults>()
    .Bind(builder.Configuration.GetSection("OpenPay"));

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
    options.AddPolicy("payment-per-tenant", httpContext =>
    {
        var tenantCode = httpContext.Request.Headers[TenantMiddleware.TenantHeaderName].FirstOrDefault() ?? "anonymous";
        return RateLimitPartition.GetFixedWindowLimiter(tenantCode, _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 20,
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
    service = "XYDataLabs.OrderProcessingSystem.Payments",
    status = "healthy"
})).AllowAnonymous();

await app.RunAsync();

public partial class Program;

internal sealed class ApplicationInsightsPaymentTelemetryTracker : IPaymentTelemetryTracker
{
    private readonly TelemetryClient? _telemetryClient;

    public ApplicationInsightsPaymentTelemetryTracker(TelemetryClient? telemetryClient)
    {
        _telemetryClient = telemetryClient;
    }

    public void Track(PaymentTelemetryEvent telemetryEvent)
    {
        ArgumentNullException.ThrowIfNull(telemetryEvent);

        if (_telemetryClient is null || string.IsNullOrWhiteSpace(telemetryEvent.EventName))
        {
            return;
        }

        var properties = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["TelemetryCategory"] = "payment-validation",
            ["Application"] = NormalizeValue(telemetryEvent.Application, 16) ?? "API",
        };

        AddProperty(properties, "TenantCode", telemetryEvent.TenantCode, 64);
        AddProperty(properties, "CustomerOrderId", telemetryEvent.CustomerOrderId, 128);
        AddProperty(properties, "AttemptOrderId", telemetryEvent.AttemptOrderId, 128);
        AddProperty(properties, "PaymentId", telemetryEvent.PaymentId, 128);
        AddProperty(properties, "PaymentTraceId", telemetryEvent.PaymentTraceId, 128);
        AddProperty(properties, "ProviderType", telemetryEvent.ProviderType, 64);
        AddProperty(properties, "PaymentStatus", telemetryEvent.PaymentStatus, 64);
        AddProperty(properties, "StatusCategory", telemetryEvent.StatusCategory, 32);
        AddProperty(properties, "StatusSource", telemetryEvent.StatusSource, 32);
        AddProperty(properties, "ThreeDSecureStage", telemetryEvent.ThreeDSecureStage, 64);
        AddProperty(properties, "ClientFlowId", telemetryEvent.ClientFlowId, 64);
        AddProperty(properties, "PagePath", telemetryEvent.PagePath, 256);
        AddProperty(properties, "ErrorCode", telemetryEvent.ErrorCode, 64);
        AddProperty(properties, "ErrorMessage", telemetryEvent.ErrorMessage, 512);
        AddProperty(properties, "ClientTimestampUtc", telemetryEvent.ClientTimestampUtc, 64);
        AddProperty(properties, "Severity", telemetryEvent.Severity, 16);
        AddProperty(properties, "RunPrefix", PaymentTelemetryCorrelation.ResolveRunPrefix(telemetryEvent.CustomerOrderId), 64);
        AddNumber(properties, "HttpStatus", telemetryEvent.HttpStatus);
        AddBoolean(properties, "RemoteStatusConfirmed", telemetryEvent.RemoteStatusConfirmed);
        AddBoolean(properties, "CallbackRecorded", telemetryEvent.CallbackRecorded);
        AddBoolean(properties, "IsThreeDSecureEnabled", telemetryEvent.IsThreeDSecureEnabled);

        _telemetryClient.TrackEvent(telemetryEvent.EventName, properties);
    }

    private static void AddProperty(IDictionary<string, string> properties, string key, string? value, int maxLength)
    {
        var normalized = NormalizeValue(value, maxLength);
        if (!string.IsNullOrWhiteSpace(normalized))
        {
            properties[key] = normalized;
        }
    }

    private static void AddNumber(IDictionary<string, string> properties, string key, int? value)
    {
        if (value.HasValue)
        {
            properties[key] = value.Value.ToString(CultureInfo.InvariantCulture);
        }
    }

    private static void AddBoolean(IDictionary<string, string> properties, string key, bool? value)
    {
        if (value.HasValue)
        {
            properties[key] = value.Value ? "true" : "false";
        }
    }

    private static string? NormalizeValue(string? value, int maxLength)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var trimmed = value.Trim();
        return trimmed.Length <= maxLength ? trimmed : trimmed[..maxLength];
    }
}

internal sealed class KeycloakIntrospectionAuthenticationHandler : AuthenticationHandler<AuthenticationSchemeOptions>
{
    private const string BearerPrefix = "Bearer ";

    private readonly IHttpClientFactory _httpClientFactory;
    private readonly IConfiguration _configuration;

    public KeycloakIntrospectionAuthenticationHandler(
        IOptionsMonitor<AuthenticationSchemeOptions> options,
        ILoggerFactory logger,
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
