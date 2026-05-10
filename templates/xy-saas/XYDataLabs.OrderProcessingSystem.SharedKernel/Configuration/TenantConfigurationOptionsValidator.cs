using Microsoft.Extensions.Options;

namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Configuration;

public sealed class TenantConfigurationOptionsValidator : IValidateOptions<TenantConfigurationOptions>
{
    public ValidateOptionsResult Validate(string? name, TenantConfigurationOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);

        var failures = new List<string>();

        if (string.IsNullOrWhiteSpace(options.ActiveTenantCode))
        {
            failures.Add($"{Constants.Configuration.ActiveTenantCode} is required.");
        }

        if (!options.UiSelectorEnabled && options.UiTenantOverrideEnabled)
        {
            failures.Add(
                $"{Constants.Configuration.UiTenantOverrideEnabled} cannot be true when {Constants.Configuration.UiSelectorEnabled} is false.");
        }

        return failures.Count > 0
            ? ValidateOptionsResult.Fail(failures)
            : ValidateOptionsResult.Success;
    }
}