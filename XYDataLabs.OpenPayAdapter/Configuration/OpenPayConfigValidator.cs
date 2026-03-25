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

        if (string.IsNullOrWhiteSpace(options.PrivateKey))
        {
            failures.Add("OpenPay:PrivateKey is required.");
        }

        if (string.IsNullOrWhiteSpace(options.DeviceSessionId))
        {
            failures.Add("OpenPay:DeviceSessionId is required.");
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