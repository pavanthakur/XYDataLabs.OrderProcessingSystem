using FluentAssertions;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using System.Text.Json;
using XYDataLabs.OrderProcessingSystem.SharedKernel;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Configuration;

public sealed class StartupValidationTests
{
    private static readonly SemaphoreSlim WorkingDirectoryGate = new(1, 1);

    [Fact]
    public async Task HostStartup_Fails_WhenActiveTenantCodeIsMissing()
    {
        await WorkingDirectoryGate.WaitAsync();

        var originalCurrentDirectory = Directory.GetCurrentDirectory();
        var tempRoot = Path.Combine(Path.GetTempPath(), $"ops-startup-validation-{Guid.NewGuid():N}");

        try
        {
            CreateSharedSettingsFile(tempRoot, includeActiveTenantCode: false);
            Directory.SetCurrentDirectory(tempRoot);

            var builder = Host.CreateApplicationBuilder();
            builder.Logging.ClearProviders();

            SharedSettingsLoader.AddAndBindSettings(
                builder.Services,
                builder.Configuration,
                Constants.Environments.Dev,
                isDocker: false,
                groupSelector: settings => settings.API,
                out _,
                out _);

            using var host = builder.Build();

            var act = async () => await host.StartAsync();

            var exception = await act.Should().ThrowAsync<OptionsValidationException>();
            exception.Which.Message.Should().Contain(Constants.Configuration.ActiveTenantCode);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalCurrentDirectory);
            if (Directory.Exists(tempRoot))
            {
                Directory.Delete(tempRoot, recursive: true);
            }

            WorkingDirectoryGate.Release();
        }
    }

    [Fact]
    public async Task SharedSettingsLoader_Fails_When_DeploymentExpectedEnvironment_Differs_From_RuntimeEnvironment()
    {
        await WorkingDirectoryGate.WaitAsync();

        var originalCurrentDirectory = Directory.GetCurrentDirectory();
        var originalExpectedEnvironment = Environment.GetEnvironmentVariable("ORDERPROCESSING_EXPECTED_ENVIRONMENT");
        var tempRoot = Path.Combine(Path.GetTempPath(), $"ops-startup-validation-{Guid.NewGuid():N}");

        try
        {
            CreateSharedSettingsFile(tempRoot, includeActiveTenantCode: true, sharedSettingsFileName: "sharedsettings.prod.json");
            Directory.SetCurrentDirectory(tempRoot);
            Environment.SetEnvironmentVariable("ORDERPROCESSING_EXPECTED_ENVIRONMENT", "staging");

            var builder = Host.CreateApplicationBuilder();
            builder.Logging.ClearProviders();

            var act = () => SharedSettingsLoader.AddAndBindSettings(
                builder.Services,
                builder.Configuration,
                Constants.Environments.Production,
                isDocker: true,
                groupSelector: settings => settings.API,
                out _,
                out _);

            act.Should()
                .Throw<InvalidOperationException>()
                .Which.Message.Should().Contain("deployment expected 'staging'");
        }
        finally
        {
            Environment.SetEnvironmentVariable("ORDERPROCESSING_EXPECTED_ENVIRONMENT", originalExpectedEnvironment);
            Directory.SetCurrentDirectory(originalCurrentDirectory);
            if (Directory.Exists(tempRoot))
            {
                Directory.Delete(tempRoot, recursive: true);
            }

            WorkingDirectoryGate.Release();
        }
    }

    [Fact]
    public async Task SharedSettingsLoader_Fails_When_AspNetCore_And_DotNet_Environment_Vars_Disagree()
    {
        await WorkingDirectoryGate.WaitAsync();

        var originalCurrentDirectory = Directory.GetCurrentDirectory();
        var originalAspNetCoreEnvironment = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT");
        var originalDotNetEnvironment = Environment.GetEnvironmentVariable("DOTNET_ENVIRONMENT");
        var tempRoot = Path.Combine(Path.GetTempPath(), $"ops-startup-validation-{Guid.NewGuid():N}");

        try
        {
            CreateSharedSettingsFile(tempRoot, includeActiveTenantCode: true, sharedSettingsFileName: "sharedsettings.stg.json");
            Directory.SetCurrentDirectory(tempRoot);
            Environment.SetEnvironmentVariable("ASPNETCORE_ENVIRONMENT", "Staging");
            Environment.SetEnvironmentVariable("DOTNET_ENVIRONMENT", "Production");

            var builder = Host.CreateApplicationBuilder();
            builder.Logging.ClearProviders();

            var act = () => SharedSettingsLoader.AddAndBindSettings(
                builder.Services,
                builder.Configuration,
                Constants.Environments.Staging,
                isDocker: true,
                groupSelector: settings => settings.API,
                out _,
                out _);

            act.Should()
                .Throw<InvalidOperationException>()
                .Which.Message.Should().Contain("ASPNETCORE_ENVIRONMENT='Staging'")
                .And.Contain("DOTNET_ENVIRONMENT='Production'");
        }
        finally
        {
            Environment.SetEnvironmentVariable("ASPNETCORE_ENVIRONMENT", originalAspNetCoreEnvironment);
            Environment.SetEnvironmentVariable("DOTNET_ENVIRONMENT", originalDotNetEnvironment);
            Directory.SetCurrentDirectory(originalCurrentDirectory);
            if (Directory.Exists(tempRoot))
            {
                Directory.Delete(tempRoot, recursive: true);
            }

            WorkingDirectoryGate.Release();
        }
    }

    private static void CreateSharedSettingsFile(string rootPath, bool includeActiveTenantCode, string sharedSettingsFileName = "sharedsettings.local.json")
    {
        var configurationPath = Path.Combine(rootPath, "Resources", "Configuration");
        Directory.CreateDirectory(configurationPath);

        var payload = new Dictionary<string, object?>
        {
            ["ApiSettings"] = new Dictionary<string, object?>
            {
                ["UI"] = new Dictionary<string, object?>
                {
                    ["http"] = new Dictionary<string, object?>
                    {
                        ["Host"] = "localhost",
                        ["Port"] = 5173,
                        ["HttpsEnabled"] = false
                    },
                    ["https"] = new Dictionary<string, object?>
                    {
                        ["Host"] = "localhost",
                        ["Port"] = 5174,
                        ["HttpsEnabled"] = true,
                        ["CertPassword"] = "password",
                        ["CertPath"] = "/https/aspnetapp.pfx"
                    }
                },
                ["API"] = new Dictionary<string, object?>
                {
                    ["http"] = new Dictionary<string, object?>
                    {
                        ["Host"] = "localhost",
                        ["Port"] = 5010,
                        ["HttpsEnabled"] = false
                    },
                    ["https"] = new Dictionary<string, object?>
                    {
                        ["Host"] = "localhost",
                        ["Port"] = 5011,
                        ["HttpsEnabled"] = true,
                        ["CertPassword"] = "password",
                        ["CertPath"] = "/https/aspnetapp.pfx"
                    }
                }
            }
        };

        if (includeActiveTenantCode)
        {
            payload["TenantConfiguration"] = new Dictionary<string, object?>
            {
                ["ActiveTenantCode"] = "TenantA"
            };
        }

        var targetFile = Path.Combine(configurationPath, sharedSettingsFileName);
        File.WriteAllText(targetFile, JsonSerializer.Serialize(payload, new JsonSerializerOptions
        {
            WriteIndented = true
        }));
    }
}
