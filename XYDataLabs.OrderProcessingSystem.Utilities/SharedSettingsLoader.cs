using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace XYDataLabs.OrderProcessingSystem.Utilities
{
    /// <summary>
    /// Provides helpers for loading shared configuration and binding strongly-typed ApiSettings
    /// for both API and UI applications across Docker and non-Docker environments.
    /// </summary>
    public static class SharedSettingsLoader
    {

        /// <summary>
        /// Load environment-specific sharedsettings and appsettings JSON files.
        /// Non-Docker local development uses the "local" profile (ports 5010-5013).
        /// Docker uses the provided environment or falls back to "dev" (ports 5000-5003).
        /// Azure App Service uses the provided environment based on ASPNETCORE_ENVIRONMENT.
        /// </summary>
        /// <param name="builder">The configuration builder to add sources to.</param>
        /// <param name="environmentName">The ASP.NET Core environment name.</param>
        /// <param name="isDocker">Whether the app is running inside a Docker container.</param>
        /// <returns>The same configuration builder for chaining.</returns>
        public static IConfigurationBuilder LoadSharedSettings(this IConfigurationBuilder builder, string environmentName, bool isDocker)
        {
            // Detect Azure App Service using WEBSITE_SITE_NAME environment variable
            var isAzure = !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("WEBSITE_SITE_NAME"));
            
            // Determine effective environment:
            // - Azure/Docker: Use the provided environment or fall back to "dev"
            // - Local (non-Docker, non-Azure): Always use "local" to avoid port conflicts
            var effectiveEnvironment = (isAzure || isDocker)
                ? (string.IsNullOrWhiteSpace(environmentName) ? "dev" : environmentName)
                : "local";
            
            // Find the solution root directory for shared settings
            var currentDirectory = Directory.GetCurrentDirectory();
            var basePath = (isDocker || isAzure) ? currentDirectory : (GetSolutionRoot(currentDirectory) ?? currentDirectory);
            
            Console.WriteLine($"[DEBUG] Loading shared settings: Environment={environmentName}, IsDocker={isDocker}, IsAzure={isAzure}, Effective={effectiveEnvironment}");
            Console.WriteLine($"[DEBUG] Base path: {basePath}");
            
            return builder
                .SetBasePath(basePath)
                .AddJsonFile($"Resources/Configuration/sharedsettings.{effectiveEnvironment}.json", optional: false, reloadOnChange: true);
                // REMOVED: .AddJsonFile($"appsettings.{effectiveEnvironment}.json", optional: true, reloadOnChange: true);
                // All configuration now consolidated in sharedsettings files for Azure Key Vault readiness
        }

        /// <summary>
        /// Load configuration, bind ApiSettings, compute the active section (API/UI) based on HTTPS selection,
        /// and resolve local certificate paths for non-Docker scenarios.
        /// </summary>
        /// <param name="services">Optional DI container for binding ApiSettings.</param>
        /// <param name="builder">Configuration builder (sources will be added and built).</param>
        /// <param name="environmentName">The ASP.NET Core environment name.</param>
        /// <param name="isDocker">True when running inside Docker.</param>
        /// <param name="groupSelector">Selector for API or UI settings group.</param>
        /// <param name="apiSettings">Outputs the bound ApiSettings.</param>
        /// <param name="useHttps">Outputs whether HTTPS is active.</param>
        /// <param name="forceUseHttps">Optional override to force HTTPS selection.</param>
        /// <returns>The active ApiSettingsSection for the chosen group (API or UI).</returns>
        public static ApiSettingsSection AddAndBindSettings(
            IServiceCollection? services,
            IConfigurationBuilder builder,
            string environmentName,
            bool isDocker,
            Func<ApiSettings, ApiSettingsGroup> groupSelector,
            out ApiSettings apiSettings,
            out bool useHttps,
            bool? forceUseHttps = null)
        {
            // Guards
            ArgumentNullException.ThrowIfNull(builder);
            ArgumentNullException.ThrowIfNull(groupSelector);

            // Load config and bind
            LoadSharedSettings(builder, environmentName, isDocker);
            var configuration = builder.Build();

            services?.Configure<ApiSettings>(configuration.GetSection("ApiSettings"));
            apiSettings = configuration.GetSection("ApiSettings").Get<ApiSettings>() ?? new ApiSettings();

            // Diagnostics for DB connection
            var connectionString = configuration.GetConnectionString(Constants.Configuration.OrderProcessingSystemDbConnectionString);
            if (string.IsNullOrWhiteSpace(connectionString))
                Console.WriteLine($"[WARNING] ConnectionStrings:{Constants.Configuration.OrderProcessingSystemDbConnectionString} not found or empty after loading settings.");

            // Decide HTTPS: force > config > env override
            useHttps = forceUseHttps ?? groupSelector(apiSettings).https.HttpsEnabled;
            if (bool.TryParse(Environment.GetEnvironmentVariable("USE_HTTPS"), out var environmentHttpsOverride))
                useHttps = environmentHttpsOverride;

            // Pick active section
            var activeSettings = groupSelector(apiSettings).GetActive(useHttps);

            // Resolve local cert path when not in Docker
            if (!isDocker && activeSettings.HttpsEnabled && !string.IsNullOrWhiteSpace(activeSettings.CertPath)
                && activeSettings.CertPath.StartsWith("/https/", StringComparison.Ordinal))
            {
                var certificateFileName = Path.GetFileName(activeSettings.CertPath);
                var currentDirectory = Directory.GetCurrentDirectory();

                var certificateSearchPaths = new[]
                {
                    Path.Combine(currentDirectory, "Resources", "Certificates", certificateFileName),
                    Path.GetFullPath(Path.Combine(currentDirectory, "..", "Resources", "Certificates", certificateFileName)),
                    GetSolutionRoot(currentDirectory) is string root ? Path.Combine(root, "Resources", "Certificates", certificateFileName) : null
                };

                string? resolvedCertificatePath = null;
                foreach (var path in certificateSearchPaths)
                {
                    if (!string.IsNullOrWhiteSpace(path) && File.Exists(path)) { resolvedCertificatePath = path; break; }
                }

                if (!string.IsNullOrWhiteSpace(resolvedCertificatePath))
                {
                    activeSettings.CertPath = resolvedCertificatePath;
                    Console.WriteLine($"[DEBUG] Resolved certificate path for non-Docker: {resolvedCertificatePath}");
                }
                else
                {
                    Console.WriteLine($"[WARNING] Certificate file {certificateFileName} not found in Resources/Certificates folder(s)");
                }
            }

            return activeSettings;
        }

        /// <summary>
        /// Centralized method to print ApiSettings and active section info for debugging.
        /// </summary>
        /// <param name="apiSettings">The bound ApiSettings instance.</param>
        /// <param name="activeSettings">The active ApiSettingsSection (API or UI).</param>
        /// <param name="context">Context string for identifying the settings block.</param>
        /// <param name="isDocker">True if the application is running in Docker.</param>
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

        /// <summary>
        /// Finds the solution root directory by looking for .sln files.
        /// </summary>
        /// <param name="startPath">The directory to start searching from.</param>
        /// <returns>The solution root directory path, or null if not found.</returns>
        private static string? GetSolutionRoot(string startPath)
        {
            var dir = new DirectoryInfo(startPath);
            while (dir != null)
            {
                if (dir.GetFiles("*.sln").Length > 0) return dir.FullName;
                dir = dir.Parent;
            }
            return null;
        }
    }
}