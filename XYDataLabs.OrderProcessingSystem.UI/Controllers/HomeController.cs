using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using XYDataLabs.OrderProcessingSystem.Utilities;
using System;

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
            // Determine environment and Docker context
            var environment = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "Production";
            var isDocker = Environment.GetEnvironmentVariable("DOTNET_RUNNING_IN_CONTAINER") == "true";

            // Map .NET environment names to our simplified profile names
            var environmentName = environment switch
            {
                "Development" => Constants.Environments.Dev,
                "Staging" => Constants.Environments.Uat, 
                "Production" => Constants.Environments.Production,
                _ => Constants.Environments.Dev // Default to dev for any other environment
            };

            // Log home page access (business event)
            _logger.LogInformation("User accessed home page in {Environment} environment", environmentName);

            // Load shared settings and get API base URL
            var builder = new ConfigurationBuilder();
            bool useHttps;
            XYDataLabs.OrderProcessingSystem.Utilities.ApiSettings apiSettings;
            var apiSection = SharedSettingsLoader.AddAndBindSettings(
                services: null, // Now allowed
                builder: builder,
                environmentName: environmentName,
                isDocker: isDocker,
                groupSelector: s => s.API,
                apiSettings: out apiSettings,
                useHttps: out useHttps
            );
            var scheme = useHttps ? "https" : "http";
            var apiBaseUrl = $"{scheme}://{apiSection.Host}:{apiSection.Port}";
            ViewData["ApiBaseUrl"] = apiBaseUrl;

            // Pass environment information to the view
            ViewData["Environment"] = environmentName.ToUpper();
            ViewData["EnvironmentColor"] = environmentName switch
            {
                "dev" => "success",      // Green for development
                "uat" => "warning",      // Yellow for UAT
                "prod" => "danger",      // Red for production
                _ => "secondary"         // Gray for unknown
            };
            ViewData["IsDocker"] = isDocker;

            _logger.LogInformation("Rendering home page with API base URL: {ApiBaseUrl}", apiBaseUrl);

            return View();
        }
    }
}