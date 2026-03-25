using Microsoft.AspNetCore.Mvc;
using XYDataLabs.OrderProcessingSystem.SharedKernel;
using System;
using XYDataLabs.OrderProcessingSystem.UI.Models;

namespace XYDataLabs.OrderProcessingSystem.UI.Controllers
{
    public class HomeController : Controller
    {
        private readonly ILogger<HomeController> _logger;

        public HomeController(ILogger<HomeController> logger)
        {
            _logger = logger;
        }

        public IActionResult Index()
        {
            var (environmentName, isDocker) = ResolveExecutionContext();

            // Log home page access (business event)
            _logger.LogInformation("User accessed home page in {Environment} environment", environmentName);
            PopulateCommonViewData(environmentName, isDocker);

            _logger.LogInformation("Rendering home page with API base URL: {ApiBaseUrl}", ViewData["ApiBaseUrl"]);

            return View();
        }

        [HttpGet("/payment/callback")]
        public IActionResult PaymentCallback()
        {
            var (environmentName, isDocker) = ResolveExecutionContext();
            PopulateCommonViewData(environmentName, isDocker);

            var parameters = Request.Query.ToDictionary(
                item => item.Key,
                item => item.Value.ToString(),
                StringComparer.OrdinalIgnoreCase);
            var attemptOrderId = GetFirstValue(parameters, "order_id", "orderId");
            var tenantCode = GetFirstValue(parameters, "tenantCode");

            var model = new PaymentCallbackViewModel
            {
                PaymentId = GetFirstValue(parameters, "id", "transaction_id", "payment_id"),
                Status = GetFirstValue(parameters, "status", "transaction_status", "operation_status") ?? "unknown",
                ErrorMessage = GetFirstValue(parameters, "error_message", "error", "message", "description"),
                Parameters = parameters
            };

            ViewData["AttemptOrderId"] = attemptOrderId;
            ViewData["TenantCode"] = tenantCode;

            _logger.LogInformation(
                "OpenPay callback received with raw status {Status} for payment {PaymentId} and attempt order {AttemptOrderId}",
                model.Status,
                model.PaymentId,
                attemptOrderId);

            return View(model);
        }

        private void PopulateCommonViewData(string environmentName, bool isDocker)
        {
            var apiBaseUrl = ResolveApiBaseUrl(environmentName, isDocker);

            ViewData["ApiBaseUrl"] = apiBaseUrl;
            ViewData["Environment"] = environmentName.ToUpperInvariant();
            ViewData["IsDevelopment"] = string.Equals(environmentName, Constants.Environments.Dev, StringComparison.Ordinal);
            ViewData["EnvironmentColor"] = environmentName switch
            {
                Constants.Environments.Dev => "success",
                Constants.Environments.Staging => "warning",
                Constants.Environments.Production => "danger",
                _ => "secondary"
            };
            ViewData["IsDocker"] = isDocker;
        }

        private string ResolveApiBaseUrl(string environmentName, bool isDocker)
        {
            var azureSiteName = Environment.GetEnvironmentVariable("WEBSITE_SITE_NAME");
            var isAzure = !string.IsNullOrWhiteSpace(azureSiteName);
            var apiBaseUrlEnv = Environment.GetEnvironmentVariable("API_BASE_URL");

            if (!string.IsNullOrWhiteSpace(apiBaseUrlEnv))
            {
                var apiBaseUrl = apiBaseUrlEnv.TrimEnd('/');
                _logger.LogInformation("Using API_BASE_URL from environment variable: {ApiBaseUrl}", apiBaseUrl);
                return apiBaseUrl;
            }

            if (isAzure)
            {
                var apiSiteName = azureSiteName!.Replace("-ui-", "-api-");
                if (!string.Equals(apiSiteName, azureSiteName, StringComparison.Ordinal))
                {
                    var apiBaseUrl = $"https://{apiSiteName}.azurewebsites.net";
                    _logger.LogInformation("Using derived Azure API URL: {ApiBaseUrl}", apiBaseUrl);
                    return apiBaseUrl;
                }

                _logger.LogWarning("Could not derive API site name from UI site name '{UiSiteName}'. Using fallback.", azureSiteName);
                return $"https://{azureSiteName}-api.azurewebsites.net";
            }

            var builder = new ConfigurationBuilder();
            bool useHttps;
            ApiSettings apiSettings;
            var apiSection = SharedSettingsLoader.AddAndBindSettings(
                services: null,
                builder: builder,
                environmentName: environmentName,
                isDocker: isDocker,
                groupSelector: s => s.API,
                apiSettings: out apiSettings,
                useHttps: out useHttps);

            var scheme = useHttps ? "https" : "http";
            return $"{scheme}://{apiSection.Host}:{apiSection.Port}";
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
    }
}