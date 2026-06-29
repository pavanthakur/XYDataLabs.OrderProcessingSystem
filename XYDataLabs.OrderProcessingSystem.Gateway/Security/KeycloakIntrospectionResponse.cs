namespace XYDataLabs.OrderProcessingSystem.Gateway.Security;

internal sealed record KeycloakIntrospectionResponse(
    bool Active,
    string? Subject,
    string? PreferredUsername,
    string? Email);
