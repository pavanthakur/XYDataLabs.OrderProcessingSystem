using Microsoft.AspNetCore.Mvc;

namespace XYDataLabs.OrderProcessingSystem.API.Controllers;

[ApiController]
public sealed class PaymentCallbackController : ControllerBase
{
    private const string PaymentCallbackPath = "/payment/callback";
    private const string PaymentCallbackResultPath = "/payments/callback";

    private readonly IConfiguration _configuration;
    private readonly ILogger<PaymentCallbackController> _logger;

    public PaymentCallbackController(IConfiguration configuration, ILogger<PaymentCallbackController> logger)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentNullException.ThrowIfNull(logger);

        _configuration = configuration;
        _logger = logger;
    }

    [HttpGet(PaymentCallbackPath)]
    public IActionResult RedirectToClientCallback()
    {
        var parameters = Request.Query.ToDictionary(
            item => item.Key,
            item => item.Value.ToString(),
            StringComparer.OrdinalIgnoreCase);
        var paymentId = GetFirstValue(parameters, "id", "transaction_id", "payment_id") ?? "none";
        var callbackStatus = GetFirstValue(parameters, "status", "transaction_status", "operation_status") ?? "unknown";
        var tenantCode = GetFirstValue(parameters, "tenantCode") ?? "none";

        if (!TryResolveFrontendBaseUrl(out var frontendBaseUrl))
        {
            _logger.LogError(
                "Payment callback received for payment {PaymentId} and tenant {TenantCode}, but no frontend callback base URL could be resolved",
                paymentId,
                tenantCode);

            return Problem(
                detail: "The frontend callback URL is not configured.",
                statusCode: StatusCodes.Status500InternalServerError,
                title: "Payment callback redirect is unavailable.");
        }

        var redirectUrl = BuildFrontendCallbackUrl(frontendBaseUrl, Request.QueryString);

        _logger.LogInformation(
            "Payment callback received for payment {PaymentId} with raw status {Status} for tenant {TenantCode}. Redirecting browser to {RedirectUrl}",
            paymentId,
            callbackStatus,
            tenantCode,
            redirectUrl);

        return Redirect(redirectUrl);
    }

    private bool TryResolveFrontendBaseUrl(out string frontendBaseUrl)
    {
        var configuredBaseUrl = _configuration["Frontend:WebBaseUrl"]?.Trim();
        if (Uri.TryCreate(configuredBaseUrl, UriKind.Absolute, out var configuredUri))
        {
            frontendBaseUrl = configuredUri.ToString().TrimEnd('/');
            return true;
        }

        var azureSiteName = Environment.GetEnvironmentVariable("WEBSITE_SITE_NAME");
        if (!string.IsNullOrWhiteSpace(azureSiteName))
        {
            var uiSiteName = azureSiteName!.Replace("-api-", "-ui-");
            if (!string.Equals(uiSiteName, azureSiteName, StringComparison.Ordinal))
            {
                frontendBaseUrl = $"https://{uiSiteName}.azurewebsites.net";
                return true;
            }
        }

        var useHttps = string.Equals(_configuration["USE_HTTPS"], "true", StringComparison.OrdinalIgnoreCase);
        var profile = useHttps ? "https" : "http";
        var host = _configuration[$"ApiSettings:UI:{profile}:Host"] ?? "localhost";
        var portValue = _configuration[$"ApiSettings:UI:{profile}:Port"];
        var scheme = useHttps ? "https" : "http";

        if (int.TryParse(portValue, out var port) && port > 0)
        {
            frontendBaseUrl = $"{scheme}://{host}:{port}";
            return true;
        }

        frontendBaseUrl = string.Empty;
        return false;
    }

    private static string BuildFrontendCallbackUrl(string frontendBaseUrl, QueryString queryString)
    {
        var frontendUri = new Uri(frontendBaseUrl, UriKind.Absolute);
        var builder = new UriBuilder(frontendUri)
        {
            Path = CombinePath(frontendUri.AbsolutePath, PaymentCallbackResultPath),
            Query = queryString.HasValue ? queryString.Value![1..] : string.Empty
        };

        return builder.Uri.ToString();
    }

    private static string CombinePath(string basePath, string relativePath)
    {
        var normalizedBasePath = string.IsNullOrWhiteSpace(basePath) || basePath == "/"
            ? string.Empty
            : basePath.TrimEnd('/');
        var normalizedRelativePath = relativePath.TrimStart('/');

        return $"{normalizedBasePath}/{normalizedRelativePath}";
    }

    private static string? GetFirstValue(IReadOnlyDictionary<string, string> parameters, params string[] keys)
    {
        foreach (var key in keys)
        {
            if (parameters.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value))
            {
                return value;
            }
        }

        return null;
    }
}