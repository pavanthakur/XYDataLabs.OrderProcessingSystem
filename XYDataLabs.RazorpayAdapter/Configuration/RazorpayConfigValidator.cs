using Microsoft.Extensions.Options;

namespace XYDataLabs.RazorpayAdapter.Configuration;

public sealed class RazorpayConfigValidator : IValidateOptions<RazorpayConfig>
{
    private static readonly HashSet<string> Placeholders = new(StringComparer.OrdinalIgnoreCase)
    {
        "__RAZORPAY_MERCHANT_ID__",
        "__RAZORPAY_PRIVATE_KEY__",
        "set-razorpay-merchant-id",
        "set-razorpay-private-key"
    };

    public ValidateOptionsResult Validate(string? name, RazorpayConfig options)
    {
        var failures = new List<string>();

        if (string.IsNullOrWhiteSpace(options.MerchantId))
            failures.Add("Razorpay:MerchantId is required.");
        else if (Placeholders.Contains(options.MerchantId))
            failures.Add("Razorpay:MerchantId is still set to a placeholder value.");

        if (string.IsNullOrWhiteSpace(options.PrivateKey))
            failures.Add("Razorpay:PrivateKey is required.");
        else if (Placeholders.Contains(options.PrivateKey))
            failures.Add("Razorpay:PrivateKey is still set to a placeholder value.");

        // Cross-validate key prefix against IsProduction mode.
        // Razorpay key IDs are prefixed with 'rzp_test_' (test) or 'rzp_live_' (live).
        // A live key with IsProduction=false would silently charge real customers under test-mode
        // assumptions — that is a safety hazard, not just a misconfiguration.
        if (!string.IsNullOrWhiteSpace(options.MerchantId) && !Placeholders.Contains(options.MerchantId))
        {
            var isLiveKey = options.MerchantId.StartsWith("rzp_live_", StringComparison.OrdinalIgnoreCase);
            var isTestKey = options.MerchantId.StartsWith("rzp_test_", StringComparison.OrdinalIgnoreCase);

            if (isLiveKey && !options.IsProduction)
                failures.Add(
                    "Razorpay:MerchantId (key_id) starts with 'rzp_live_' but IsProduction is false. " +
                    "Set Razorpay:IsProduction=true when using a live key, or switch to a test key (rzp_test_*). " +
                    "Using a live key in test mode risks real charges without production safeguards.");

            if (isTestKey && options.IsProduction)
                failures.Add(
                    "Razorpay:MerchantId (key_id) starts with 'rzp_test_' but IsProduction is true. " +
                    "Set Razorpay:IsProduction=false when using a test key.");
        }

        return failures.Count > 0
            ? ValidateOptionsResult.Fail(failures)
            : ValidateOptionsResult.Success;
    }
}
