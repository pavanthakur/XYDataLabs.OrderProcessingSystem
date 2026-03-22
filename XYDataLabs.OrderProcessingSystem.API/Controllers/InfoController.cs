using Asp.Versioning;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using System.Globalization;
using XYDataLabs.OrderProcessingSystem.SharedKernel;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Configuration;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;

namespace XYDataLabs.OrderProcessingSystem.API.Controllers
{
    [ApiVersion("1.0")]
    [ApiController]
    [Route("api/v{version:apiVersion}/[controller]")]
    public class InfoController : ControllerBase
    {
        private readonly ILogger<InfoController> _logger;
        private readonly TenantConfigurationOptions _tenantConfigurationOptions;
        private readonly TimeProvider _timeProvider;

        public InfoController(
            ILogger<InfoController> logger,
            IOptions<TenantConfigurationOptions> tenantConfigurationOptions,
            TimeProvider timeProvider)
        {
            _logger = logger;
            _tenantConfigurationOptions = tenantConfigurationOptions.Value;
            _timeProvider = timeProvider;
        }

        /// <summary>
        /// Gets the current environment and deployment information
        /// </summary>
        /// <returns>Environment and deployment information</returns>
        [HttpGet("environment")]
        [ProducesResponseType(StatusCodes.Status200OK)]
        public IActionResult GetEnvironmentInfo()
        {
            var environment = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "Production";
            var isDocker = string.Equals(
                Environment.GetEnvironmentVariable("DOTNET_RUNNING_IN_CONTAINER"),
                "true",
                StringComparison.Ordinal);
            
            // Map .NET environment names to our simplified profile names
            var environmentName = environment switch
            {
                "Development" => Constants.Environments.Dev,
                "Staging" => Constants.Environments.Staging, 
                "Production" => Constants.Environments.Production,
                _ => Constants.Environments.Dev // Default to dev for any other environment
            };

            // Log environment info request (business event)
            _logger.LogInformation("Environment info requested for {Environment} environment", environmentName);

            var environmentInfo = new
            {
                Environment = environmentName.ToUpper(CultureInfo.InvariantCulture),
                OriginalEnvironment = environment,
                IsDocker = isDocker,
                DeploymentType = isDocker ? "Docker Container" : "Local Process",
                MachineName = Environment.MachineName,
                Platform = Environment.OSVersion.Platform.ToString(),
                Framework = Environment.Version.ToString(),
                Timestamp = _timeProvider.GetUtcNow().UtcDateTime
            };

            return Ok(environmentInfo);
        }

        /// <summary>
        /// Gets non-sensitive runtime configuration required for UI bootstrap.
        /// </summary>
        /// <returns>Active tenant bootstrap data owned by the API configuration.</returns>
        [HttpGet("runtime-configuration")]
        [ProducesResponseType(StatusCodes.Status200OK)]
        [ProducesResponseType(StatusCodes.Status500InternalServerError)]
        public IActionResult GetRuntimeConfiguration()
        {
            var activeTenantCode = _tenantConfigurationOptions.ActiveTenantCode.Trim();

            if (string.IsNullOrWhiteSpace(activeTenantCode))
            {
                _logger.LogError(
                    "Runtime configuration request failed because configuration key {ConfigurationKey} is missing or empty",
                    Constants.Configuration.ActiveTenantCode);

                return Problem(
                    detail: $"Configuration key '{Constants.Configuration.ActiveTenantCode}' is required.",
                    statusCode: StatusCodes.Status500InternalServerError,
                    title: "Active tenant configuration is missing.");
            }

            _logger.LogInformation(
                "Runtime configuration requested with active tenant code {TenantCode}",
                activeTenantCode);

            return Ok(new
            {
                ActiveTenantCode = activeTenantCode,
                TenantHeaderName = TenantMiddleware.TenantHeaderName
            });
        }
    }
}
