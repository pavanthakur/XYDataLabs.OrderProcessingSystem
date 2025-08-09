using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Configuration.Json; // Ensure this namespace is included
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options; // For IOptions<T>

namespace XYDataLabs.OrderProcessingSystem.Utilities
{
    public static class SharedSettingsLoader
    {
        // Loads environment-specific settings with dev as fallback default
        public static IConfigurationBuilder LoadSharedSettings(this IConfigurationBuilder builder, string environmentName, bool isDocker)
        {
            Console.WriteLine($"[DEBUG SharedSettingsLoader] environmentName: {environmentName}, isDocker: {isDocker}");
            
            // Ensure we have a valid environment name, default to dev
            if (string.IsNullOrEmpty(environmentName))
            {
                environmentName = "dev";
            }

            if (isDocker)
            {
                // Docker scenario: Keep existing behavior - load both shared and local appsettings
                builder
                    .SetBasePath(Directory.GetCurrentDirectory())
                    .AddJsonFile($"sharedsettings.{environmentName}.json", optional: false, reloadOnChange: true)
                    .AddJsonFile($"appsettings.{environmentName}.json", optional: false);
                Console.WriteLine($"[DEBUG] Docker: Loading sharedsettings.{environmentName}.json + appsettings.{environmentName}.json");
                    //.AddEnvironmentVariables();
            }
            else
            {
                // Non-Docker scenario: Use only sharedsettings.{environment}.json (simplified)
                // Default to 'dev' profile which contains all necessary configuration
                var currentDir = Directory.GetCurrentDirectory();
                var sharedSettingsFileName = $"sharedsettings.{environmentName}.json";
                
                string sharedSettingsPath = sharedSettingsFileName;
                
                // Check if sharedsettings exists in current directory
                if (!File.Exists(Path.Combine(currentDir, sharedSettingsFileName)))
                {
                    // Try parent directory (for projects running from their own folders)
                    if (File.Exists(Path.Combine(currentDir, "..", sharedSettingsFileName)))
                    {
                        sharedSettingsPath = Path.GetFullPath(Path.Combine(currentDir, "..", sharedSettingsFileName));
                    }
                    else
                    {
                        // Find the solution root by looking for .sln file
                        var searchDir = currentDir;
                        while (searchDir != null)
                        {
                            if (Directory.GetFiles(searchDir, "*.sln").Length > 0)
                            {
                                var candidatePath = Path.Combine(searchDir, sharedSettingsFileName);
                                if (File.Exists(candidatePath))
                                {
                                    sharedSettingsPath = Path.GetRelativePath(currentDir, candidatePath);
                                    break;
                                }
                            }
                            searchDir = Directory.GetParent(searchDir)?.FullName;
                        }
                    }
                }
                
                builder
                    .SetBasePath(Directory.GetCurrentDirectory())
                    .AddJsonFile(sharedSettingsPath, optional: false, reloadOnChange: true);
                
                Console.WriteLine($"[DEBUG] Non-Docker: Using single shared settings file: {sharedSettingsPath}");
                Console.WriteLine($"[DEBUG] Non-Docker: Simplified configuration - no local appsettings dependencies");
                    //.AddEnvironmentVariables();
            }
            return builder;
        }

        // Combined method for both API and UI settings
        public static ApiSettingsSection AddAndBindSettings(
            IServiceCollection? services, // Make nullable
            IConfigurationBuilder builder,
            string environmentName,
            bool isDocker,
            Func<ApiSettings, ApiSettingsGroup> groupSelector,
            out ApiSettings apiSettings,
            out bool useHttps,
            bool? forceUseHttps = null)
        {
            LoadSharedSettings(builder, environmentName, isDocker);
            var configuration = builder.Build();
            if (services != null)
            {
                services.Configure<ApiSettings>(configuration.GetSection("ApiSettings"));
            }
            apiSettings = configuration.GetSection("ApiSettings").Get<ApiSettings>() ?? new ApiSettings();

            // Default to HTTP unless explicitly overridden
            useHttps = false;
            if (forceUseHttps.HasValue)
                useHttps = forceUseHttps.Value;
            else if (groupSelector(apiSettings).https.HttpsEnabled)
                useHttps = true;
            var envHttps = Environment.GetEnvironmentVariable("USE_HTTPS");
            if (!string.IsNullOrEmpty(envHttps))
                useHttps = bool.TryParse(envHttps, out var parsed) ? parsed : useHttps;

            // Get the active section (API or UI)
            var activeSettings = groupSelector(apiSettings).GetActive(useHttps);
            
            // Resolve certificate path for non-Docker scenarios
            if (!isDocker && activeSettings.HttpsEnabled && !string.IsNullOrEmpty(activeSettings.CertPath))
            {
                // Convert Docker certificate path to local path
                if (activeSettings.CertPath.StartsWith("/https/"))
                {
                    var certFileName = Path.GetFileName(activeSettings.CertPath);
                    var currentDir = Directory.GetCurrentDirectory();
                    
                    // Look for dev-certs folder starting from current directory
                    string? certPath = null;
                    
                    // Check if dev-certs exists in current directory
                    var localCertPath = Path.Combine(currentDir, "dev-certs", certFileName);
                    if (File.Exists(localCertPath))
                    {
                        certPath = localCertPath;
                    }
                    else
                    {
                        // Try parent directory
                        localCertPath = Path.Combine(currentDir, "..", "dev-certs", certFileName);
                        if (File.Exists(localCertPath))
                        {
                            certPath = Path.GetFullPath(localCertPath);
                        }
                        else
                        {
                            // Find the solution root by looking for .sln file
                            var searchDir = currentDir;
                            while (searchDir != null)
                            {
                                if (Directory.GetFiles(searchDir, "*.sln").Length > 0)
                                {
                                    var candidatePath = Path.Combine(searchDir, "dev-certs", certFileName);
                                    if (File.Exists(candidatePath))
                                    {
                                        certPath = candidatePath;
                                        break;
                                    }
                                }
                                searchDir = Directory.GetParent(searchDir)?.FullName;
                            }
                        }
                    }
                    
                    if (!string.IsNullOrEmpty(certPath))
                    {
                        activeSettings.CertPath = certPath;
                        Console.WriteLine($"[DEBUG] Resolved certificate path for non-Docker: {certPath}");
                    }
                    else
                    {
                        Console.WriteLine($"[WARNING] Certificate file {certFileName} not found in dev-certs folder");
                    }
                }
            }
            
            return activeSettings;
        }

        // Centralized method to print ApiSettings and active section info
        public static void PrintApiSettingsDebug(ApiSettings apiSettings, ApiSettingsSection activeSettings, string context, bool isDocker)
        {
            Console.WriteLine($"[ENV VALIDATION] {context}.Host: {activeSettings.Host}");
            Console.WriteLine($"[ENV VALIDATION] {context}.Port: {activeSettings.Port}");
            Console.WriteLine($"[ENV VALIDATION] {context}.HttpsEnabled: {activeSettings.HttpsEnabled}");
            if (activeSettings.HttpsEnabled)
            {
                Console.WriteLine($"[ENV VALIDATION] {context}.CertPath: {activeSettings.CertPath}");
                Console.WriteLine($"[ENV VALIDATION] {context}.CertPassword: {activeSettings.CertPassword}");
            }
            Console.WriteLine($"[DEBUG] Running in Docker: {isDocker}");
            Console.WriteLine($"[DEBUG] UI.Http Port: {apiSettings.UI.http.Port}");
            Console.WriteLine($"[DEBUG] UI.Https Port: {apiSettings.UI.https.Port}");
            Console.WriteLine($"[DEBUG] API.Http Port: {apiSettings.API.http.Port}");
            Console.WriteLine($"[DEBUG] API.Https Port: {apiSettings.API.https.Port}");
            Console.WriteLine($"[DEBUG] Active {context} Port: {activeSettings.Port}");
        }
    }
}