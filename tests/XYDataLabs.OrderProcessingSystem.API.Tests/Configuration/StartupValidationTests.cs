using FluentAssertions;
using Microsoft.Extensions.Hosting;
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

    private static void CreateSharedSettingsFile(string rootPath, bool includeActiveTenantCode)
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
                        ["Port"] = 5012,
                        ["HttpsEnabled"] = false
                    },
                    ["https"] = new Dictionary<string, object?>
                    {
                        ["Host"] = "localhost",
                        ["Port"] = 5013,
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

        var targetFile = Path.Combine(configurationPath, "sharedsettings.local.json");
        File.WriteAllText(targetFile, JsonSerializer.Serialize(payload, new JsonSerializerOptions
        {
            WriteIndented = true
        }));
    }
}