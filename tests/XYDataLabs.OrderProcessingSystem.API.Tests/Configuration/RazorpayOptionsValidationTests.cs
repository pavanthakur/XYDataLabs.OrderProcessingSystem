using FluentAssertions;
using Microsoft.Extensions.Options;
using XYDataLabs.RazorpayAdapter.Configuration;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Configuration;

public class RazorpayOptionsValidationTests
{
    [Fact]
    public void RazorpayConfigValidator_Fails_WhenMerchantIdIsEmpty()
    {
        var validator = new RazorpayConfigValidator();
        var settings = new RazorpayConfig
        {
            MerchantId = "",
            PrivateKey = "rzp_test_abc123",
            IsProduction = false
        };

        var result = validator.Validate(Options.DefaultName, settings);

        result.Failed.Should().BeTrue();
        result.Failures.Should().ContainSingle(failure =>
            failure.Contains("Razorpay:MerchantId is required", StringComparison.Ordinal));
    }

    [Fact]
    public void RazorpayConfigValidator_Fails_WhenPrivateKeyIsEmpty()
    {
        var validator = new RazorpayConfigValidator();
        var settings = new RazorpayConfig
        {
            MerchantId = "Sve5JtE8tsGogn",
            PrivateKey = "",
            IsProduction = false
        };

        var result = validator.Validate(Options.DefaultName, settings);

        result.Failed.Should().BeTrue();
        result.Failures.Should().ContainSingle(failure =>
            failure.Contains("Razorpay:PrivateKey is required", StringComparison.Ordinal));
    }

    [Fact]
    public void RazorpayConfigValidator_Fails_WhenMerchantIdIsPlaceholder()
    {
        var validator = new RazorpayConfigValidator();
        var settings = new RazorpayConfig
        {
            MerchantId = "__RAZORPAY_MERCHANT_ID__",
            PrivateKey = "rzp_test_abc123",
            IsProduction = false
        };

        var result = validator.Validate(Options.DefaultName, settings);

        result.Failed.Should().BeTrue();
        result.Failures.Should().ContainSingle(failure =>
            failure.Contains("placeholder", StringComparison.Ordinal));
    }

    [Fact]
    public void RazorpayConfigValidator_Fails_WhenPrivateKeyIsPlaceholder()
    {
        var validator = new RazorpayConfigValidator();
        var settings = new RazorpayConfig
        {
            MerchantId = "Sve5JtE8tsGogn",
            PrivateKey = "__RAZORPAY_PRIVATE_KEY__",
            IsProduction = false
        };

        var result = validator.Validate(Options.DefaultName, settings);

        result.Failed.Should().BeTrue();
        result.Failures.Should().ContainSingle(failure =>
            failure.Contains("placeholder", StringComparison.Ordinal));
    }

    [Fact]
    public void RazorpayConfigValidator_Fails_WhenBothFieldsArePlaceholders()
    {
        var validator = new RazorpayConfigValidator();
        var settings = new RazorpayConfig
        {
            MerchantId = "__RAZORPAY_MERCHANT_ID__",
            PrivateKey = "__RAZORPAY_PRIVATE_KEY__",
            IsProduction = false
        };

        var result = validator.Validate(Options.DefaultName, settings);

        result.Failed.Should().BeTrue();
        result.Failures.Should().HaveCount(2);
    }

    [Fact]
    public void RazorpayConfigValidator_Succeeds_WhenAllRequiredFieldsProvided()
    {
        var validator = new RazorpayConfigValidator();
        var settings = new RazorpayConfig
        {
            MerchantId = "Sve5JtE8tsGogn",
            PrivateKey = "rzp_test_SveO8BqHN3uFSk",
            IsProduction = false
        };

        var result = validator.Validate(Options.DefaultName, settings);

        result.Failed.Should().BeFalse();
    }
}
