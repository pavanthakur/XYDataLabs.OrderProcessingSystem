using Asp.Versioning;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using System.Globalization;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
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
        private const string ActiveTenantStatus = "Active";
        private readonly ILogger<InfoController> _logger;
        private readonly IAppDbContext _appDbContext;
        private readonly TenantConfigurationOptions _tenantConfigurationOptions;
        private readonly TimeProvider _timeProvider;

        public InfoController(
            ILogger<InfoController> logger,
            IAppDbContext appDbContext,
            IOptions<TenantConfigurationOptions> tenantConfigurationOptions,
            TimeProvider timeProvider)
        {
            ArgumentNullException.ThrowIfNull(logger);
            ArgumentNullException.ThrowIfNull(appDbContext);
            ArgumentNullException.ThrowIfNull(tenantConfigurationOptions);
            ArgumentNullException.ThrowIfNull(timeProvider);

            _logger = logger;
            _appDbContext = appDbContext;
            _tenantConfigurationOptions = tenantConfigurationOptions.Value;
            _timeProvider = timeProvider;
        }

        /// <summary>
        /// Gets the current environment and deployment information
        /// </summary>
        /// <returns>Environment and deployment information</returns>
        [HttpGet("environment")]
        [ProducesResponseType<object>(StatusCodes.Status200OK)]
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
        [ProducesResponseType<RuntimeConfigurationResponse>(StatusCodes.Status200OK)]
        [ProducesResponseType(StatusCodes.Status500InternalServerError)]
        public async Task<IActionResult> GetRuntimeConfiguration(CancellationToken cancellationToken)
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

            var availableTenants = await _appDbContext.Tenants
                .AsNoTracking()
                .Where(tenant => tenant.Status == ActiveTenantStatus)
                .OrderBy(tenant => tenant.Name)
                .ThenBy(tenant => tenant.Code)
                .Select(tenant => new AvailableTenantConfiguration(
                    tenant.Id,
                    tenant.Code,
                    tenant.Name))
                .ToListAsync(cancellationToken);

            if (availableTenants.Count == 0)
            {
                _logger.LogError("Runtime configuration request failed because no active tenants were found in the database");

                return Problem(
                    detail: "No active tenants are available for runtime bootstrap.",
                    statusCode: StatusCodes.Status500InternalServerError,
                    title: "Runtime tenant configuration is unavailable.");
            }

            var requestedTenantCode = HttpContext?.Request?.Headers[TenantMiddleware.TenantHeaderName].FirstOrDefault()?.Trim();
            var resolvedTenantCode = ResolveTenantCode(requestedTenantCode, activeTenantCode, availableTenants);

            _logger.LogInformation(
                "Runtime configuration requested with resolved tenant code {TenantCode}, configured tenant code {ConfiguredTenantCode}, requested tenant code {RequestedTenantCode}, and {TenantCount} active tenants",
                resolvedTenantCode,
                activeTenantCode,
                string.IsNullOrWhiteSpace(requestedTenantCode) ? "none" : requestedTenantCode,
                availableTenants.Count);

            return Ok(new RuntimeConfigurationResponse(
                resolvedTenantCode,
                activeTenantCode,
                TenantMiddleware.TenantHeaderName,
                availableTenants));
        }

        private string ResolveTenantCode(
            string? requestedTenantCode,
            string configuredTenantCode,
            IReadOnlyList<AvailableTenantConfiguration> availableTenants)
        {
            if (TryMatchTenantCode(requestedTenantCode, availableTenants, out var requestedMatch))
            {
                return requestedMatch;
            }

            if (TryMatchTenantCode(configuredTenantCode, availableTenants, out var configuredMatch))
            {
                return configuredMatch;
            }

            var fallbackTenantCode = availableTenants[0].TenantCode;
            _logger.LogWarning(
                "Configured active tenant code {ConfiguredTenantCode} is not an active tenant in the database. Falling back to {FallbackTenantCode}",
                configuredTenantCode,
                fallbackTenantCode);

            return fallbackTenantCode;
        }

        private static bool TryMatchTenantCode(
            string? candidateTenantCode,
            IEnumerable<AvailableTenantConfiguration> availableTenants,
            out string matchedTenantCode)
        {
            var match = availableTenants.FirstOrDefault(tenant =>
                string.Equals(tenant.TenantCode, candidateTenantCode, StringComparison.OrdinalIgnoreCase));

            if (match is null)
            {
                matchedTenantCode = string.Empty;
                return false;
            }

            matchedTenantCode = match.TenantCode;
            return true;
        }

        private sealed record RuntimeConfigurationResponse(
            string ActiveTenantCode,
            string ConfiguredActiveTenantCode,
            string TenantHeaderName,
            IReadOnlyList<AvailableTenantConfiguration> AvailableTenants);

        private sealed record AvailableTenantConfiguration(
            int TenantId,
            string TenantCode,
            string TenantName);
    }
}
