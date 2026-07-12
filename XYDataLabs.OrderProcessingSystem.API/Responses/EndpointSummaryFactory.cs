namespace XYDataLabs.OrderProcessingSystem.API.Responses;

public static class EndpointSummaryFactory
{
    private static readonly string[] LocalRoutes =
    [
        "orders.localhost:5080 -> http://localhost:5010",
        "inventory.localhost:5080 -> http://localhost:5011",
        "notifications.localhost:5080 -> http://localhost:5012",
        "ui.localhost:5080 -> http://localhost:5173",
        "localhost:5080/api/{**catch-all} -> http://localhost:5010",
        "localhost:5080/inventory/{**catch-all} -> http://localhost:5011",
        "localhost:5080/notifications/{**catch-all} -> http://localhost:5012",
        "localhost:5080/app/{**catch-all} -> http://localhost:5173"
    ];

    public static IReadOnlyDictionary<string, object?> BuildHealthSummary(string acceptedHost)
    {
        return new Dictionary<string, object?>(StringComparer.Ordinal)
        {
            ["service"] = "XYDataLabs.OrderProcessingSystem.Gateway",
            ["status"] = "healthy",
            ["acceptedHost"] = acceptedHost,
            ["summary"] = $"Accepted host: {acceptedHost}",
            ["routes"] = LocalRoutes
        };
    }

    public static IReadOnlyDictionary<string, object?> BuildSwaggerUnavailableSummary(
        string environmentName,
        string acceptedHost,
        string swaggerAvailableAt)
    {
        return new Dictionary<string, object?>(StringComparer.Ordinal)
        {
            ["message"] = "Swagger UI is not available in the Production environment.",
            ["reason"] = "API documentation is intentionally disabled in production. Use the dev or staging environment to explore the API.",
            ["environment"] = environmentName,
            ["acceptedHost"] = acceptedHost,
            ["summary"] = $"Accepted host: {acceptedHost}",
            ["swaggerAvailableAt"] = swaggerAvailableAt
        };
    }
}
