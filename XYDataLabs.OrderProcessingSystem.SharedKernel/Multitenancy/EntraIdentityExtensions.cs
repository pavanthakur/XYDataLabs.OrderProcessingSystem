using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;

namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

public static class EntraIdentityExtensions
{
    /// <summary>Overrides the local scheme only when Entra is explicitly selected.</summary>
    public static void AddConfiguredEntraIdentity(this IServiceCollection services, IConfiguration configuration)
    {
        var section = configuration.GetSection("IdentityProvider");
        if (!section.GetValue("Enabled", false)) return;
        var mode = section["Mode"] ?? "KeycloakLocal";
        if (mode == "KeycloakLocal") return;
        if (mode != "Entra") throw new InvalidOperationException("Unsupported IdentityProvider:Mode.");
        var authority = Required(section, "Authority").TrimEnd('/');
        var audience = Required(section, "Audience");
        var scope = Required(section, "RequiredScope");
        var tenantClaim = Required(section, "TenantClaimType");
        if (!Uri.TryCreate(authority, UriKind.Absolute, out var uri) || uri.Scheme != "https"
            || uri.Host != "login.microsoftonline.com"
            || !Guid.TryParse(uri.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault(), out _)
            || !uri.AbsolutePath.EndsWith("/v2.0", StringComparison.Ordinal))
            throw new InvalidOperationException("Entra authority must be a tenant-specific HTTPS v2.0 authority.");
        if (tenantClaim == "tid" || tenantClaim == "roles" || tenantClaim == "sub" || tenantClaim == "oid")
            throw new InvalidOperationException("Application tenant claim must not be a directory or identity claim.");
        services.AddAuthentication(options =>
        {
            options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
            options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
        }).AddJwtBearer(options =>
        {
            options.Authority = authority;
            options.Audience = audience;
            options.RequireHttpsMetadata = true;
            options.MapInboundClaims = false;
            options.TokenValidationParameters = new TokenValidationParameters
            {
                ValidateIssuer = true, ValidIssuer = authority,
                ValidateAudience = true, ValidAudience = audience,
                ValidateLifetime = true, ValidateIssuerSigningKey = true,
                RequireSignedTokens = true, RequireExpirationTime = true,
                NameClaimType = "preferred_username", RoleClaimType = "roles",
                ClockSkew = TimeSpan.FromMinutes(1)
            };
            options.Events = new JwtBearerEvents
            {
                OnTokenValidated = context =>
                {
                    if (!NormalizeValidatedPrincipal(context.Principal!, tenantClaim, scope))
                        context.Fail("A delegated API scope and valid application tenant assignment are required.");
                    return Task.CompletedTask;
                }
            };
        });
    }

    // Invoked only after JWT validation; never use on browser-supplied identity data.
    public static bool NormalizeValidatedPrincipal(ClaimsPrincipal user, string tenantClaimType, string requiredScope)
    {
        if (user.Identity is not ClaimsIdentity identity || !identity.IsAuthenticated
            || !user.FindAll("scp").SelectMany(c => c.Value.Split(' ', StringSplitOptions.RemoveEmptyEntries))
                .Contains(requiredScope, StringComparer.Ordinal)) return false;
        var values = user.FindAll(tenantClaimType).Select(c => c.Value.Trim()).Where(v => v.Length > 0).Distinct().ToArray();
        // Never trust an unrelated tenant_code claim when a different mapped claim was configured.
        foreach (var claim in identity.FindAll(TenantAccessPolicy.TenantClaimType).ToArray()) identity.RemoveClaim(claim);
        if (values.Length > 1) return false;
        if (values.Length == 1) identity.AddClaim(new Claim(TenantAccessPolicy.TenantClaimType, values[0]));
        return TenantAccessPolicy.IsPlatformAdmin(user) || values.Length == 1;
    }

    private static string Required(IConfiguration section, string key) =>
        !string.IsNullOrWhiteSpace(section[key]) && !section[key]!.Contains("__", StringComparison.Ordinal)
            ? section[key]!.Trim() : throw new InvalidOperationException($"IdentityProvider:{key} is required for Entra.");
}
