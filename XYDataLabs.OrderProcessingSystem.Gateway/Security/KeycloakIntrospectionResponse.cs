using System.Text.Json.Serialization;
using System.Text.Json;

namespace XYDataLabs.OrderProcessingSystem.Gateway.Security;

internal sealed record KeycloakIntrospectionResponse(
    [property: JsonPropertyName("active")]
    bool Active,
    [property: JsonPropertyName("sub")]
    string? Subject,
    [property: JsonPropertyName("preferred_username")]
    string? PreferredUsername,
    [property: JsonPropertyName("email")]
    string? Email,
    [property: JsonPropertyName("tenant_code")]
    string? TenantCode,
    [property: JsonPropertyName("aud")]
    JsonElement Audience,
    [property: JsonPropertyName("realm_access")]
    KeycloakRealmAccess? RealmAccess);

internal sealed record KeycloakRealmAccess(
    [property: JsonPropertyName("roles")]
    IReadOnlyCollection<string>? Roles);
