using FluentAssertions;
using Microsoft.Extensions.Options;
using XYDataLabs.OpenPayAdapter.Configuration;
using XYDataLabs.OrderProcessingSystem.SharedKernel;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Configuration;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Configuration;

public class OptionsValidationTests
{
    [Fact]
    public void TenantConfigurationValidator_Fails_WhenActiveTenantCodeIsMissing()
    {
        var validator = new TenantConfigurationOptionsValidator();

        var result = validator.Validate(Options.DefaultName, new TenantConfigurationOptions());

        result.Failed.Should().BeTrue();
        result.Failures.Should().ContainSingle(failure => failure.Contains(Constants.Configuration.ActiveTenantCode, StringComparison.Ordinal));
    }

    [Fact]
    public void TenantConfigurationValidator_Fails_WhenUiOverrideEnabledButSelectorHidden()
    {
        var validator = new TenantConfigurationOptionsValidator();

        var result = validator.Validate(
            Options.DefaultName,
            new TenantConfigurationOptions
            {
                ActiveTenantCode = "TenantA",
                UiSelectorEnabled = false,
                UiTenantOverrideEnabled = true,
                SwaggerSelectorEnabled = true
            });

        result.Failed.Should().BeTrue();
        result.Failures.Should().ContainSingle(failure =>
            failure.Contains(Constants.Configuration.UiTenantOverrideEnabled, StringComparison.Ordinal)
            && failure.Contains(Constants.Configuration.UiSelectorEnabled, StringComparison.Ordinal));
    }

    [Fact]
    public void TenantConfigurationValidator_Succeeds_WhenTenantUiPolicyIsConsistent()
    {
        var validator = new TenantConfigurationOptionsValidator();

        var result = validator.Validate(
            Options.DefaultName,
            new TenantConfigurationOptions
            {
                ActiveTenantCode = "TenantA",
                UiSelectorEnabled = false,
                UiTenantOverrideEnabled = false,
                SwaggerSelectorEnabled = false
            });

        result.Failed.Should().BeFalse();
    }

    [Fact]
    public void ApiSettingsValidator_Fails_WhenPortIsInvalid()
    {
        var validator = new ApiSettingsValidator();
        var settings = new ApiSettings
        {
            UI = new ApiSettingsGroup
            {
                http = new ApiSettingsSection { Host = "localhost", Port = 0 },
                https = new ApiSettingsSection { Host = "localhost", Port = 5174, HttpsEnabled = true }
            },
            API = new ApiSettingsGroup
            {
                http = new ApiSettingsSection { Host = "localhost", Port = 5010 },
                https = new ApiSettingsSection { Host = "localhost", Port = 5011, HttpsEnabled = true }
            }
        };

        var result = validator.Validate(Options.DefaultName, settings);

        result.Failed.Should().BeTrue();
        result.Failures.Should().ContainSingle(failure => failure.Contains("ApiSettings:UI:http:Port", StringComparison.Ordinal));
    }

    [Fact]
    public void OpenPayConfigValidator_Fails_WhenRedirectUrlIsRelative()
    {
        var validator = new OpenPayConfigValidator();
        var settings = new OpenPayConfig
        {
            MerchantId = "merchant",
            PrivateKey = "private-key",
            DeviceSessionId = "device-session",
            RedirectUrl = "/payment/callback",
            IsProduction = false
        };

        var result = validator.Validate(Options.DefaultName, settings);

        result.Failed.Should().BeTrue();
        result.Failures.Should().ContainSingle(failure => failure.Contains("absolute URI", StringComparison.Ordinal));
    }

    [Fact]
    public void OpenPayConfigValidator_Fails_WhenMerchantIdIsEmpty()
    {
        var validator = new OpenPayConfigValidator();
        var settings = new OpenPayConfig
        {
            MerchantId = "",
            PrivateKey = "private-key",
            DeviceSessionId = "device-session",
            RedirectUrl = "https://example.com/payment/callback",
            IsProduction = false
        };

        var result = validator.Validate(Options.DefaultName, settings);

        result.Failed.Should().BeTrue();
        result.Failures.Should().ContainSingle(failure => failure.Contains("OpenPay:MerchantId is required", StringComparison.Ordinal));
    }

    [Fact]
    public void OpenPayConfigValidator_Fails_WhenPrivateKeyIsEmpty()
    {
        var validator = new OpenPayConfigValidator();
        var settings = new OpenPayConfig
        {
            MerchantId = "merchant",
            PrivateKey = "",
            DeviceSessionId = "device-session",
            RedirectUrl = "https://example.com/payment/callback",
            IsProduction = false
        };

        var result = validator.Validate(Options.DefaultName, settings);

        result.Failed.Should().BeTrue();
        result.Failures.Should().ContainSingle(failure => failure.Contains("OpenPay:PrivateKey is required", StringComparison.Ordinal));
    }

    [Fact]
    public void OpenPayConfigValidator_Fails_WhenDeviceSessionIdIsEmpty()
    {
        var validator = new OpenPayConfigValidator();
        var settings = new OpenPayConfig
        {
            MerchantId = "merchant",
            PrivateKey = "private-key",
            DeviceSessionId = "",
            RedirectUrl = "https://example.com/payment/callback",
            IsProduction = false
        };

        var result = validator.Validate(Options.DefaultName, settings);

        result.Failed.Should().BeTrue();
        result.Failures.Should().ContainSingle(failure => failure.Contains("OpenPay:DeviceSessionId is required", StringComparison.Ordinal));
    }

    [Fact]
    public void OpenPayConfigValidator_Fails_WhenMerchantIdIsPlaceholder()
    {
        var validator = new OpenPayConfigValidator();
        var settings = new OpenPayConfig
        {
            MerchantId = "set-openpay-merchant-id-dev",
            PrivateKey = "private-key",
            DeviceSessionId = "device-session",
            RedirectUrl = "https://example.com/payment/callback",
            IsProduction = false
        };

        var result = validator.Validate(Options.DefaultName, settings);

        result.Failed.Should().BeTrue();
        result.Failures.Should().ContainSingle(failure => failure.Contains("placeholder", StringComparison.Ordinal));
    }

    [Fact]
    public void OpenPayConfigValidator_Succeeds_WhenAllRequiredFieldsProvided()
    {
        var validator = new OpenPayConfigValidator();
        var settings = new OpenPayConfig
        {
            MerchantId = "real-merchant-id",
            PrivateKey = "real-private-key",
            DeviceSessionId = "real-device-session",
            RedirectUrl = "https://example.com/payment/callback",
            IsProduction = false
        };

        var result = validator.Validate(Options.DefaultName, settings);

        result.Failed.Should().BeFalse();
    }
}