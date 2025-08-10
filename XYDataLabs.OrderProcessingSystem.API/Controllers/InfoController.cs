using Microsoft.AspNetCore.Mvc;
using XYDataLabs.OrderProcessingSystem.Utilities;

namespace XYDataLabs.OrderProcessingSystem.API.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class InfoController : ControllerBase
    {
        private readonly ILogger<InfoController> _logger;

        public InfoController(ILogger<InfoController> logger)
        {
            _logger = logger;
        }

        /// <summary>
        /// Gets the current environment and deployment information
        /// </summary>
        /// <returns>Environment and deployment information</returns>
        [HttpGet("environment")]
        public IActionResult GetEnvironmentInfo()
        {
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

            // Log environment info request (business event)
            _logger.LogInformation("Environment info requested for {Environment} environment", environmentName);

            var environmentInfo = new
            {
                Environment = environmentName.ToUpper(),
                OriginalEnvironment = environment,
                IsDocker = isDocker,
                DeploymentType = isDocker ? "Docker Container" : "Local Process",
                MachineName = Environment.MachineName,
                Platform = Environment.OSVersion.Platform.ToString(),
                Framework = Environment.Version.ToString(),
                Timestamp = DateTime.UtcNow
            };

            return Ok(environmentInfo);
        }
    }
}
