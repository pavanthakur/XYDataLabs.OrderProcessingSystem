using Microsoft.Extensions.Options;

namespace XYDataLabs.OrderProcessingSystem.PaymentGateway.Configuration;

public sealed class PaymentGatewayOptionsValidator : IValidateOptions<PaymentGatewayOptions>
{
    public ValidateOptionsResult Validate(string? name, PaymentGatewayOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);

        var failures = new List<string>();

        if (string.IsNullOrWhiteSpace(options.AccountId))
        {
            failures.Add("PaymentGateway:AccountId is required.");
        }
        else if (options.AccountId.StartsWith("set-payment-gateway-", StringComparison.OrdinalIgnoreCase))
        {
            failures.Add("PaymentGateway:AccountId contains a placeholder value (matches bootstrap placeholder prefix 'set-payment-gateway-*'). Set a real credential before deployment.");
        }

        if (string.IsNullOrWhiteSpace(options.ApiKey))
        {
            failures.Add("PaymentGateway:ApiKey is required.");
        }
        else if (options.ApiKey.StartsWith("set-payment-gateway-", StringComparison.OrdinalIgnoreCase))
        {
            failures.Add("PaymentGateway:ApiKey contains a placeholder value (matches bootstrap placeholder prefix 'set-payment-gateway-*'). Set a real credential before deployment.");
        }

        if (string.IsNullOrWhiteSpace(options.DeviceSessionId))
        {
            failures.Add("PaymentGateway:DeviceSessionId is required.");
        }
        else if (options.DeviceSessionId.StartsWith("set-payment-gateway-", StringComparison.OrdinalIgnoreCase))
        {
            failures.Add("PaymentGateway:DeviceSessionId contains a placeholder value (matches bootstrap placeholder prefix 'set-payment-gateway-*'). Set a real credential before deployment.");
        }

        if (string.IsNullOrWhiteSpace(options.RedirectUrl))
        {
            failures.Add("PaymentGateway:RedirectUrl is required.");
        }
        else if (!Uri.TryCreate(options.RedirectUrl, UriKind.Absolute, out _))
        {
            failures.Add("PaymentGateway:RedirectUrl must be an absolute URI.");
        }

        return failures.Count > 0
            ? ValidateOptionsResult.Fail(failures)
            : ValidateOptionsResult.Success;
    }
}