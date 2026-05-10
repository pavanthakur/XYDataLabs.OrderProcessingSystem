using Microsoft.Extensions.Options;

namespace XYDataLabs.OrderProcessingSystem.SharedKernel.Configuration;

public sealed class ApiSettingsValidator : IValidateOptions<ApiSettings>
{
    public ValidateOptionsResult Validate(string? name, ApiSettings options)
    {
        ArgumentNullException.ThrowIfNull(options);

        var failures = new List<string>();

        ValidateGroup(options.UI, nameof(ApiSettings.UI), failures);
        ValidateGroup(options.API, nameof(ApiSettings.API), failures);

        return failures.Count > 0
            ? ValidateOptionsResult.Fail(failures)
            : ValidateOptionsResult.Success;
    }

    private static void ValidateGroup(ApiSettingsGroup group, string groupName, ICollection<string> failures)
    {
        ValidateSection(group.http, $"{groupName}:http", failures);
        ValidateSection(group.https, $"{groupName}:https", failures);
    }

    private static void ValidateSection(ApiSettingsSection section, string sectionName, ICollection<string> failures)
    {
        if (string.IsNullOrWhiteSpace(section.Host))
        {
            failures.Add($"ApiSettings:{sectionName}:Host is required.");
        }

        if (section.Port is < 1 or > 65535)
        {
            failures.Add($"ApiSettings:{sectionName}:Port must be between 1 and 65535.");
        }
    }
}