namespace XYDataLabs.OrderProcessingSystem.API.Middleware;

public sealed class SecurityHeadersMiddleware
{
    private const string NoSniffValue = "nosniff";
    private const string DenyValue = "DENY";
    private readonly RequestDelegate _next;

    public SecurityHeadersMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    public Task InvokeAsync(HttpContext context)
    {
        context.Response.OnStarting(() =>
        {
            context.Response.Headers.TryAdd("X-Content-Type-Options", NoSniffValue);
            context.Response.Headers.TryAdd("X-Frame-Options", DenyValue);
            return Task.CompletedTask;
        });

        return _next(context);
    }
}