using Asp.Versioning;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using System.Globalization;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.SharedKernel;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Configuration;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Multitenancy;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Payments;

namespace XYDataLabs.OrderProcessingSystem.Orders.API.Controllers;

[ApiVersion("1.0")]
[ApiController]
[AllowAnonymous]
[Route("api/v{version:apiVersion}/[controller]")]
public sealed class InfoController : ControllerBase
{
    private readonly ILogger<InfoController> _logger;
    private readonly ITenantRegistry _tenantRegistry;
    private readonly ITenantPaymentProviderResolver _paymentProviderResolver;
    private readonly ITenantPaymentProviderConfigurationResolver _paymentProviderConfigurationResolver;
    private readonly TenantConfigurationOptions _tenantConfigurationOptions;
    private readonly TimeProvider _timeProvider;

    public InfoController(
        ILogger<InfoController> logger,
        ITenantRegistry tenantRegistry,
        ITenantPaymentProviderResolver paymentProviderResolver,
        ITenantPaymentProviderConfigurationResolver paymentProviderConfigurationResolver,
        IOptions<TenantConfigurationOptions> tenantConfigurationOptions,
        TimeProvider timeProvider)
    {
        ArgumentNullException.ThrowIfNull(logger);
        ArgumentNullException.ThrowIfNull(tenantRegistry);
        ArgumentNullException.ThrowIfNull(paymentProviderResolver);
        ArgumentNullException.ThrowIfNull(paymentProviderConfigurationResolver);
        ArgumentNullException.ThrowIfNull(tenantConfigurationOptions);
        ArgumentNullException.ThrowIfNull(timeProvider);

        _logger = logger;
        _tenantRegistry = tenantRegistry;
        _paymentProviderResolver = paymentProviderResolver;
        _paymentProviderConfigurationResolver = paymentProviderConfigurationResolver;
        _tenantConfigurationOptions = tenantConfigurationOptions.Value;
        _timeProvider = timeProvider;
    }

    [HttpGet("environment")]
    [ProducesResponseType<object>(StatusCodes.Status200OK)]
    public IActionResult GetEnvironmentInfo()
    {
        var environment = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "Production";
        var isDocker = string.Equals(
            Environment.GetEnvironmentVariable("DOTNET_RUNNING_IN_CONTAINER"),
            "true",
            StringComparison.Ordinal);

        var environmentName = environment switch
        {
            "Development" => Constants.Environments.Dev,
            "Staging" => Constants.Environments.Staging,
            "Production" => Constants.Environments.Production,
            _ => Constants.Environments.Dev
        };

        _logger.LogInformation("Environment info requested for {Environment} environment", environmentName);

        return Ok(new
        {
            Environment = environmentName.ToUpper(CultureInfo.InvariantCulture),
            OriginalEnvironment = environment,
            IsDocker = isDocker,
            DeploymentType = isDocker ? "Docker Container" : "Local Process",
            MachineName = Environment.MachineName,
            Platform = Environment.OSVersion.Platform.ToString(),
            Framework = Environment.Version.ToString(),
            Timestamp = _timeProvider.GetUtcNow().UtcDateTime
        });
    }

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

        var activeTenantsList = await _tenantRegistry.GetActiveTenantsAsync(cancellationToken);
        var availableTenants = activeTenantsList
            .Select(t => new AvailableTenantConfiguration(t.TenantId, t.TenantCode, t.TenantName))
            .ToList();

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

    [HttpGet("payment-configuration")]
    [ProducesResponseType<PaymentConfigurationResponse>(StatusCodes.Status200OK)]
    public IActionResult GetPaymentConfiguration()
    {
        var paymentProvider = _paymentProviderResolver.ResolveCurrentTenantProvider();
        var providerConfiguration = _paymentProviderConfigurationResolver.ResolveCurrentTenantConfiguration();

        return Ok(new PaymentConfigurationResponse(
            paymentProvider.ProviderType,
            paymentProvider.Name,
            ResolveCollectionMode(paymentProvider.ProviderType, paymentProvider.Use3DSecure),
            ResolveBrowserKey(paymentProvider.ProviderType, providerConfiguration),
            ResolveBrowserMerchantId(paymentProvider.ProviderType, providerConfiguration),
            providerConfiguration.IsProduction,
            paymentProvider.Use3DSecure));
    }

    [HttpGet("tenant-registry")]
    [ProducesResponseType<IEnumerable<TenantRegistryResponse>>(StatusCodes.Status200OK)]
    public async Task<IActionResult> GetTenantRegistry(CancellationToken cancellationToken)
    {
        var activeTenants = await _tenantRegistry.GetActiveTenantsAsync(cancellationToken);

        var registry = activeTenants
            .Select(tenant =>
            {
                var entry = _tenantRegistry.FindByCode(tenant.TenantCode);
                return new TenantRegistryResponse(
                    tenant.TenantId,
                    tenant.TenantCode,
                    tenant.TenantName,
                    entry?.TenantTier ?? string.Empty,
                    entry?.PaymentProviderCode);
            })
            .ToList();

        return Ok(registry);
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

    private static string ResolveCollectionMode(string providerType, bool use3DSecure)
    {
        if (string.Equals(providerType, PaymentProviderTypes.Razorpay, StringComparison.OrdinalIgnoreCase))
        {
            return use3DSecure ? "direct_card_form" : "provider_checkout";
        }

        return "direct_card_form";
    }

    private static string? ResolveBrowserKey(
        string providerType,
        PaymentProviderRuntimeConfiguration providerConfiguration)
    {
        if (string.Equals(providerType, PaymentProviderTypes.Razorpay, StringComparison.OrdinalIgnoreCase))
        {
            return providerConfiguration.MerchantId;
        }

        if (string.Equals(providerType, PaymentProviderTypes.OpenPay, StringComparison.OrdinalIgnoreCase))
        {
            return providerConfiguration.PublicKey;
        }

        return null;
    }

    private static string? ResolveBrowserMerchantId(
        string providerType,
        PaymentProviderRuntimeConfiguration providerConfiguration)
    {
        return string.Equals(providerType, PaymentProviderTypes.OpenPay, StringComparison.OrdinalIgnoreCase)
            ? providerConfiguration.MerchantId
            : null;
    }

    private sealed record RuntimeConfigurationResponse(
        string ActiveTenantCode,
        string ConfiguredActiveTenantCode,
        string TenantHeaderName,
        IReadOnlyList<AvailableTenantConfiguration> AvailableTenants);

    private sealed record PaymentConfigurationResponse(
        string ActiveProviderType,
        string ActiveProviderName,
        string CollectionMode,
        string? BrowserKey,
        string? BrowserMerchantId,
        bool IsProduction,
        bool IsThreeDSecure);

    private sealed record TenantRegistryResponse(
        int TenantId,
        string TenantCode,
        string TenantName,
        string TenantTier,
        string? PaymentProviderCode);

    private sealed record AvailableTenantConfiguration(
        int TenantId,
        string TenantCode,
        string TenantName);
}
