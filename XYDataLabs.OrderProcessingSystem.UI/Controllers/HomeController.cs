using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using XYDataLabs.OrderProcessingSystem.SharedKernel;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Configuration;
using System;

namespace XYDataLabs.OrderProcessingSystem.UI.Controllers
{
    [Route("")]
    public class HomeController : Controller
    {
        private const string PaymentEntryPath = "/payments/new";
        private const string PaymentCallbackResultPath = "/payments/callback";

        private readonly IConfiguration _configuration;
        private readonly ILogger<HomeController> _logger;

        public HomeController(
            IConfiguration configuration,
            ILogger<HomeController> logger)
        {
            ArgumentNullException.ThrowIfNull(configuration);
            ArgumentNullException.ThrowIfNull(logger);
            _logger = logger;
            _configuration = configuration;
        }

        [HttpGet("")]
        public IActionResult Index([FromQuery] string? tenantCode = null)
        {
            var frontendBaseUrl = ResolveFrontendBaseUrl();
            var redirectUrl = BuildFrontendUrl(frontendBaseUrl, PaymentEntryPath, Request.QueryString);

            _logger.LogInformation(
                "Legacy UI payment entry requested for tenant {TenantCode}. Redirecting to {RedirectUrl}",
                string.IsNullOrWhiteSpace(tenantCode) ? "none" : tenantCode,
                redirectUrl);

            return Redirect(redirectUrl);
        }

        [HttpGet("payment/callback")]
        public IActionResult PaymentCallback()
        {
            var parameters = Request.Query.ToDictionary(
                item => item.Key,
                item => item.Value.ToString(),
                StringComparer.OrdinalIgnoreCase);
            var paymentId = GetFirstValue(parameters, "id", "transaction_id", "payment_id") ?? "none";
            var callbackStatus = GetFirstValue(parameters, "status", "transaction_status", "operation_status") ?? "unknown";
            var tenantCode = GetFirstValue(parameters, "tenantCode");
            var frontendBaseUrl = ResolveFrontendBaseUrl();
            var redirectUrl = BuildFrontendUrl(frontendBaseUrl, PaymentCallbackResultPath, Request.QueryString);

            _logger.LogInformation(
                "Legacy UI payment callback received with raw status {Status} for payment {PaymentId} and tenant {TenantCode}. Redirecting to {RedirectUrl}",
                callbackStatus,
                paymentId,
                tenantCode ?? "none",
                redirectUrl);

            return Redirect(redirectUrl);
        }

        private static (string EnvironmentName, bool IsDocker) ResolveExecutionContext()
        {
            var environment = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "Production";
            var isDocker = string.Equals(Environment.GetEnvironmentVariable("DOTNET_RUNNING_IN_CONTAINER"), "true", StringComparison.Ordinal);

            var environmentName = environment switch
            {
                "Development" => Constants.Environments.Dev,
                "Staging" => Constants.Environments.Staging,
                "Production" => Constants.Environments.Production,
                _ => Constants.Environments.Dev
            };

            return (environmentName, isDocker);
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

        private string ResolveFrontendBaseUrl()
        {
            var configuredBaseUrl = _configuration["Frontend:WebBaseUrl"]?.Trim();
            if (Uri.TryCreate(configuredBaseUrl, UriKind.Absolute, out var configuredUri))
            {
                return configuredUri.ToString().TrimEnd('/');
            }

            var requestHost = Request.Host.Value;
            if (!string.IsNullOrWhiteSpace(requestHost))
            {
                return $"{Request.Scheme}://{requestHost}";
            }

            var azureSiteName = Environment.GetEnvironmentVariable("WEBSITE_SITE_NAME");
            if (!string.IsNullOrWhiteSpace(azureSiteName))
            {
                return $"https://{azureSiteName}.azurewebsites.net";
            }

            var (environmentName, isDocker) = ResolveExecutionContext();
            var builder = new ConfigurationBuilder();
            bool useHttps;
            ApiSettings apiSettings;
            var uiSection = SharedSettingsLoader.AddAndBindSettings(
                services: null,
                builder: builder,
                environmentName: environmentName,
                isDocker: isDocker,
                groupSelector: s => s.UI,
                apiSettings: out apiSettings,
                useHttps: out useHttps);

            var scheme = useHttps ? "https" : "http";
            return $"{scheme}://{uiSection.Host}:{uiSection.Port}";
        }

        private static string BuildFrontendUrl(string frontendBaseUrl, string targetPath, QueryString queryString)
        {
            var frontendUri = new Uri(frontendBaseUrl, UriKind.Absolute);
            var builder = new UriBuilder(frontendUri)
            {
                Path = CombinePath(frontendUri.AbsolutePath, targetPath),
                Query = queryString.HasValue ? queryString.Value![1..] : string.Empty
            };

            return builder.Uri.ToString();
        }

        private static string CombinePath(string basePath, string relativePath)
        {
            var normalizedBasePath = string.IsNullOrWhiteSpace(basePath) || string.Equals(basePath, "/", StringComparison.Ordinal)
                ? string.Empty
                : basePath.TrimEnd('/');
            var normalizedRelativePath = relativePath.TrimStart('/');

            return $"{normalizedBasePath}/{normalizedRelativePath}";
        }
    }
}