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
    public void ApiSettingsValidator_Fails_WhenPortIsInvalid()
    {
        var validator = new ApiSettingsValidator();
        var settings = new ApiSettings
        {
            UI = new ApiSettingsGroup
            {
                http = new ApiSettingsSection { Host = "localhost", Port = 0 },
                https = new ApiSettingsSection { Host = "localhost", Port = 5013, HttpsEnabled = true }
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
}