using Microsoft.Extensions.Options;

namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Configuration;

public sealed class TenantConfigurationOptionsValidator : IValidateOptions<TenantConfigurationOptions>
{
    public ValidateOptionsResult Validate(string? name, TenantConfigurationOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);

        return string.IsNullOrWhiteSpace(options.ActiveTenantCode)
            ? ValidateOptionsResult.Fail($"{Constants.Configuration.ActiveTenantCode} is required.")
            : ValidateOptionsResult.Success;
    }
}