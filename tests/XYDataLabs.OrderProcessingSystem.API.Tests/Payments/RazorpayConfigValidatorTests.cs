using FluentAssertions;
using Microsoft.Extensions.Options;
using XYDataLabs.RazorpayAdapter.Configuration;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Payments;

/// <summary>
/// Unit tests for RazorpayConfigValidator — covers required fields, placeholder detection,
/// and key-prefix vs IsProduction mode cross-validation.
/// </summary>
public class RazorpayConfigValidatorTests
{
    private static RazorpayConfig ValidTestConfig() => new()
    {
        MerchantId = "rzp_test_AbCdEfGhIj",
        PrivateKey = "secret_test_key",
        IsProduction = false
    };

    private static RazorpayConfig ValidLiveConfig() => new()
    {
        MerchantId = "rzp_live_AbCdEfGhIj",
        PrivateKey = "secret_live_key",
        IsProduction = true
    };

    private static ValidateOptionsResult Validate(RazorpayConfig config)
        => new RazorpayConfigValidator().Validate(null, config);

    // ------------------------------------------------------------------ happy paths

    [Fact]
    public void Validate_TestKeyWithIsProductionFalse_Succeeds()
    {
        Validate(ValidTestConfig()).Succeeded.Should().BeTrue();
    }

    [Fact]
    public void Validate_LiveKeyWithIsProductionTrue_Succeeds()
    {
        Validate(ValidLiveConfig()).Succeeded.Should().BeTrue();
    }

    // ------------------------------------------------------------------ required fields

    [Fact]
    public void Validate_MissingMerchantId_Fails()
    {
        var config = ValidTestConfig();
        config.MerchantId = string.Empty;
        Validate(config).Failed.Should().BeTrue();
    }

    [Fact]
    public void Validate_MissingPrivateKey_Fails()
    {
        var config = ValidTestConfig();
        config.PrivateKey = string.Empty;
        Validate(config).Failed.Should().BeTrue();
    }

    // ------------------------------------------------------------------ placeholder detection

    [Theory]
    [InlineData("__RAZORPAY_MERCHANT_ID__")]
    [InlineData("set-razorpay-merchant-id")]
    public void Validate_PlaceholderMerchantId_Fails(string placeholder)
    {
        var config = ValidTestConfig();
        config.MerchantId = placeholder;
        Validate(config).Failed.Should().BeTrue();
    }

    [Theory]
    [InlineData("__RAZORPAY_PRIVATE_KEY__")]
    [InlineData("set-razorpay-private-key")]
    public void Validate_PlaceholderPrivateKey_Fails(string placeholder)
    {
        var config = ValidTestConfig();
        config.PrivateKey = placeholder;
        Validate(config).Failed.Should().BeTrue();
    }

    // ------------------------------------------------------------------ key-prefix vs mode cross-validation

    [Fact]
    public void Validate_LiveKeyWithIsProductionFalse_Fails()
    {
        var config = new RazorpayConfig
        {
            MerchantId = "rzp_live_AbCdEfGhIj",
            PrivateKey = "secret_live_key",
            IsProduction = false   // mismatch — live key but test mode
        };

        var result = Validate(config);
        result.Failed.Should().BeTrue(
            because: "a live key with IsProduction=false risks real charges without production safeguards");
        result.FailureMessage.Should().Contain("rzp_live_");
    }

    [Fact]
    public void Validate_TestKeyWithIsProductionTrue_Fails()
    {
        var config = new RazorpayConfig
        {
            MerchantId = "rzp_test_AbCdEfGhIj",
            PrivateKey = "secret_test_key",
            IsProduction = true   // mismatch — test key but production mode
        };

        var result = Validate(config);
        result.Failed.Should().BeTrue(
            because: "a test key should never be used with IsProduction=true");
        result.FailureMessage.Should().Contain("rzp_test_");
    }

    [Fact]
    public void Validate_NonPrefixedKeyWithAnyMode_DoesNotFailOnCrossCheck()
    {
        // A key without a recognised rzp_ prefix (e.g. custom staging key) should not
        // trigger the cross-check — only the required-field validation applies.
        var config = new RazorpayConfig
        {
            MerchantId = "custom_staging_key_id",
            PrivateKey = "secret_key",
            IsProduction = false
        };

        Validate(config).Succeeded.Should().BeTrue(
            because: "cross-check only applies to keys with a recognised rzp_test_ or rzp_live_ prefix");
    }
}
