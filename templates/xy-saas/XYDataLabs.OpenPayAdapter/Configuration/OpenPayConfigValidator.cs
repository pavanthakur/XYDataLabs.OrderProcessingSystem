using Microsoft.Extensions.Options;

namespace XYDataLabs.OpenPayAdapter.Configuration;

public sealed class OpenPayConfigValidator : IValidateOptions<OpenPayConfig>
{
    public ValidateOptionsResult Validate(string? name, OpenPayConfig options)
    {
        ArgumentNullException.ThrowIfNull(options);

        var failures = new List<string>();

        if (string.IsNullOrWhiteSpace(options.MerchantId))
        {
            failures.Add("OpenPay:MerchantId is required.");
        }
        else if (options.MerchantId.StartsWith("set-openpay-", StringComparison.OrdinalIgnoreCase))
        {
            failures.Add("OpenPay:MerchantId contains a placeholder value (matches bootstrap placeholder prefix 'set-openpay-*'). Set a real credential in Azure Key Vault. Note: this check pattern-matches the current placeholder format only — it is not exhaustive.");
        }

        if (string.IsNullOrWhiteSpace(options.PrivateKey))
        {
            failures.Add("OpenPay:PrivateKey is required.");
        }
        else if (options.PrivateKey.StartsWith("set-openpay-", StringComparison.OrdinalIgnoreCase))
        {
            failures.Add("OpenPay:PrivateKey contains a placeholder value (matches bootstrap placeholder prefix 'set-openpay-*'). Set a real credential in Azure Key Vault. Note: this check pattern-matches the current placeholder format only — it is not exhaustive.");
        }

        if (string.IsNullOrWhiteSpace(options.DeviceSessionId))
        {
            failures.Add("OpenPay:DeviceSessionId is required.");
        }
        else if (options.DeviceSessionId.StartsWith("set-openpay-", StringComparison.OrdinalIgnoreCase))
        {
            failures.Add("OpenPay:DeviceSessionId contains a placeholder value (matches bootstrap placeholder prefix 'set-openpay-*'). Set a real credential in Azure Key Vault. Note: this check pattern-matches the current placeholder format only — it is not exhaustive.");
        }

        if (string.IsNullOrWhiteSpace(options.RedirectUrl))
        {
            failures.Add("OpenPay:RedirectUrl is required.");
        }
        else if (!Uri.TryCreate(options.RedirectUrl, UriKind.Absolute, out _))
        {
            failures.Add("OpenPay:RedirectUrl must be an absolute URI.");
        }

        return failures.Count > 0
            ? ValidateOptionsResult.Fail(failures)
            : ValidateOptionsResult.Success;
    }
}