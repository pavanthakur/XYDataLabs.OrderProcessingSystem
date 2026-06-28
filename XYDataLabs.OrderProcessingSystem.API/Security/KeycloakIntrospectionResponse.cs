namespace XYDataLabs.OrderProcessingSystem.API.Security;

internal sealed record KeycloakIntrospectionResponse(
    bool Active,
    string? Subject,
    string? PreferredUsername,
    string? Email);
