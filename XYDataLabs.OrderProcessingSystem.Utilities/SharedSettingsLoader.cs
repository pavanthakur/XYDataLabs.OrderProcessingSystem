using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Azure.Identity;
using System;

namespace XYDataLabs.OrderProcessingSystem.Utilities
{
    /// <summary>
    /// Provides helpers for loading shared configuration and binding strongly-typed ApiSettings
    /// for both API and UI applications across Docker and non-Docker environments.
    /// </summary>
    public static partial class SharedSettingsLoader
    {

        /// <summary>
        /// Load environment-specific sharedsettings and appsettings JSON files.
        /// Non-Docker local development uses the "local" profile (ports 5010-5013).
        /// Docker uses the provided environment or falls back to "dev" (ports 5000-5003).
        /// Azure App Service uses the provided environment based on ASPNETCORE_ENVIRONMENT and loads secrets from Key Vault.
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
            
            // Build configuration with JSON file first, then environment variables override
            // This allows Azure App Service connection strings to take precedence over local JSON settings
            builder
                .SetBasePath(basePath)
                .AddJsonFile($"Resources/Configuration/sharedsettings.{effectiveEnvironment}.json", optional: false, reloadOnChange: true);
            
            // Add environment variables AFTER JSON file so they can override
            // Azure App Service sets connection strings as environment variables with specific prefixes:
            // - SQLAZURECONNSTR_<name> for SQL Azure connection strings
            // - CUSTOMCONNSTR_<name> for custom connection strings
            // ASP.NET Core automatically maps these to ConnectionStrings:<name> in configuration
            if (isAzure)
            {
                Console.WriteLine("[DEBUG] Azure environment detected - adding environment variables for connection string override");
                builder.AddEnvironmentVariables();
                
                // Add Azure Key Vault configuration using Managed Identity
                // ENTERPRISE REQUIREMENT: Key Vault is mandatory for Azure deployments
                try
                {
                    // Get Key Vault name from environment variable (set by bootstrap/deployment)
                    var keyVaultName = Environment.GetEnvironmentVariable("KEY_VAULT_NAME");
                    if (string.IsNullOrWhiteSpace(keyVaultName))
                    {
                        // Fallback: Construct Key Vault name (assumes standard naming: kv-{baseName}-{env})
                        // Bootstrap script sets KEY_VAULT_NAME, so this fallback is rarely used
                        keyVaultName = $"kv-orderprocessing-{effectiveEnvironment}";
                        Console.WriteLine($"[WARN] KEY_VAULT_NAME environment variable not set. Using constructed name: {keyVaultName}");
                    }
                    
                    // Validate Key Vault name format (alphanumeric and hyphens only, 3-24 chars)
                    // Using static readonly regex for performance
                    if (!IsValidKeyVaultName(keyVaultName))
                    {
                        var errorMsg = $"[ERROR] Invalid Key Vault name format: {keyVaultName}. " +
                                      "Key Vault names must be 3-24 characters, alphanumeric and hyphens only. " +
                                      "Set KEY_VAULT_NAME environment variable or fix naming convention.";
                        Console.WriteLine(errorMsg);
                        throw new InvalidOperationException(errorMsg);
                    }
                    
                    var keyVaultUri = $"https://{keyVaultName}.vault.azure.net/";
                    Console.WriteLine($"[INFO] Attempting to load secrets from Key Vault: {keyVaultUri}");
                    
                    // Use DefaultAzureCredential which supports Managed Identity in Azure
                    builder.AddAzureKeyVault(
                        new Uri(keyVaultUri),
                        new DefaultAzureCredential());
                    
                    Console.WriteLine($"[SUCCESS] Azure Key Vault configuration added successfully: {keyVaultUri}");
                    Console.WriteLine("[INFO] Application will use Key Vault for secure secret management");
                }
                catch (Exception ex)
                {
                    // WARNING: Key Vault configuration failed - application will fall back to sharedsettings.json
                    // For production deployments, Key Vault should be properly configured
                    var errorMsg = $"[WARNING] Failed to configure Azure Key Vault in Azure environment. " +
                                  $"Application will fall back to configuration from sharedsettings.json. " +
                                  $"Error: {ex.Message}";
                    Console.WriteLine(errorMsg);
                    Console.WriteLine("[ERROR DETAILS] Possible causes:");
                    Console.WriteLine("  1. Managed Identity is not enabled on the App Service");
                    Console.WriteLine("  2. Managed Identity does not have access policies for Key Vault");
                    Console.WriteLine("  3. KEY_VAULT_NAME environment variable is not set or incorrect");
                    Console.WriteLine("  4. Key Vault does not exist or is not accessible");
                    Console.WriteLine($"[REMEDIATION] Run: ./Resources/Azure-Deployment/enable-managed-identity.ps1 -Environment {effectiveEnvironment}");
                    Console.WriteLine("[IMPORTANT] For production environments, Key Vault should be properly configured for secure secret management.");
                    
                    // Log warning but allow application to continue with sharedsettings.json fallback
                    // This allows the application to start even when Key Vault is not accessible
                }
            }
            
            return builder;
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
        /// Validates Key Vault name format.
        /// </summary>
        /// <param name="name">The Key Vault name to validate.</param>
        /// <returns>True if valid, false otherwise.</returns>
        private static bool IsValidKeyVaultName(string name)
        {
            // Key Vault names: alphanumeric and hyphens only, 3-24 chars, globally unique
            return !string.IsNullOrWhiteSpace(name) 
                && name.Length >= 3 
                && name.Length <= 24 
                && KeyVaultNameRegex().IsMatch(name);
        }

        [System.Text.RegularExpressions.GeneratedRegex(@"^[a-zA-Z0-9\-]+$", System.Text.RegularExpressions.RegexOptions.Compiled)]
        private static partial System.Text.RegularExpressions.Regex KeyVaultNameRegex();

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